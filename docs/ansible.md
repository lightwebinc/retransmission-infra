# Ansible usage

## Layout

```
ansible/
  site.yml                  Main playbook (redis_nodes, aerospike_nodes, retry_endpoint_nodes plays)
  requirements.yml          Collection dependencies (community.general, ansible.posix)
  group_vars/all.yml        Default variables for all retry-endpoint nodes
  inventory/hosts.example.yml
  roles/
    common/                 Base OS deps + Go toolchain
    perf-tuning/            High-PPS host tuning (UDP buffers, busy-poll, C-states)
    retry-endpoint/         Build + systemd / rc.d unit + config
    networking/             Interface / multicast route / GRE config
    firewall/               nftables (Linux) / pf (FreeBSD) perimeter (simplified)
    redis/                  Optional Redis cache node (redis_nodes group)
    aerospike/              Optional Aerospike CE cache node (aerospike_nodes group)
```

## First run

```sh
cd ansible
ansible-galaxy collection install -r requirements.yml
cp inventory/hosts.example.yml inventory/hosts.yml
$EDITOR inventory/hosts.yml               # fill in host IPs, mc_iface
ansible-playbook -i inventory/hosts.yml site.yml
```

## Role ordering

`site.yml` runs roles in this order on `retry_endpoint_nodes`:

1. `common` — install packages, Go toolchain, journald cap + disk-reclaim timer (Linux); opt-in `--tags os_update` patching
2. `perf-tuning` *(default on; skipped when `perf_tuning_enabled: false`)* — host network/CPU tuning
3. `retry-endpoint` — build binary, install service
4. `networking` — configure `mc_iface`, GRE, multicast route
5. `firewall` *(when `enable_firewall: true`)* — lock down the perimeter

Firewall runs **after** networking so interface names resolve. Optional
`redis_nodes` and `aerospike_nodes` plays (cache-backend hosts) run first.

## Key variables

See `ansible/group_vars/all.yml` for the full list. Quick reference:

| Variable | Default | Notes |
|-------------------|------------|----------------------------------------------------|
| `mc_iface` | `eth0` | **Must be set per-host** (group_vars precedence); the NIC the binary binds (`MC_IFACE`) and the firewall's fabric iface |
| `ingress_iface` | `eth0` | **Must be set per-host** and equal `mc_iface`; the NIC the `networking` role configures (netplan / rc.conf, multicast route) |
| `ingress_mode` | `ethernet` | Or `gre` |
| `listen_port` | `9001` | Multicast frame receive (matches proxy/listener egress) |
| `nack_port` | `9300` | NACK receive (listeners dial this) |
| `egress_iface` | `eth0` | Retransmission egress interface |
| `egress_port` | `9001` | Retransmission multicast (matches listener ingress) |
| `shard_bits` | `2` | Must match fabric |
| `retry_version` | `v1.10.1` | Git ref to build (tag, branch, or SHA); keep ≥ `v1.9.5` (see the note in `group_vars/all.yml`) |
| `retry_force_build` | `false` | Force a rebuild even if the binary exists |
| `retry_local_binary` | `""` | Push a pre-built local binary (skips git/build) |
| `source_mode` | `asm` | Or `ssm` (then `bind_source` is required and `ssm_publishers_static` lists the publishers to (S,G)-join) |
| `cache_backend` | `memory` | Or `redis` / `aerospike` |
| `redis_addr` | `""` | Redis address (if cache_backend=redis) |
| `cache_ttl` | `60s` | Global fallback cache TTL; collapses per-FrameVer TTLs when explicitly set |
| `cache_ttl_tx` | `60s` | FrameVer V2 (BRC-124/128 regular tx) cache TTL |
| `cache_ttl_block` | `10m` | FrameVer V4 (BRC-131 block control) cache TTL |
| `cache_ttl_subtree` | `5m` | FrameVer V5 (BRC-132 subtree data) cache TTL |
| `cache_ttl_anchor` | `2m` | FrameVer V6 (BRC-134 anchor tx) cache TTL |
| `cache_max_keys` | `100000` | Maximum cache entries |
| `rl_ip_rate` | `1000/s` | Per-IP NACK rate limit |
| `rl_chain_rate` | `500` | Max NACKs per window per (srcIP, chainID) |
| `rl_sequence_max` | `100` | Max requests per LookupSeq per sliding window |
| `rl_group_rate` | `200/s` | Retransmits per second per (srcIP, groupIdx) |
| `rl_throttle_response` | `false` | Emit THROTTLED hint on seq/chain/group throttle |
| `proxy_enabled` | `false` | BRC-126 one-hop NACK relay to `upstream_retry_endpoints` (tuning: `proxy_workers`, `proxy_queue`, `proxy_timeout`, `proxy_max_endpoints`, `proxy_dedup_window`) |
| `subtree_data_enabled` | unset (`false`) | BRC-132 subtree-data caching; under `ssm` also set `ssm_bootstrap_subtree_announce` (not declared in `group_vars/all.yml`) |
| `beef_enabled` / `beef_shard_bits` / `cache_ttl_beef` | unset (`false` / `0` / `60s`) | BRC-148 BEEF plane caching (retry ≥ v1.7.0); `beef_shard_bits` MUST match the proxies (not declared in `group_vars/all.yml`) |
| `retry_tee_listen` / `retry_mc_join_enabled` | unset (`""` / `true`) | `TEE_LISTEN` loopback mirror from a co-resident proxy/listener `-retry-tee`; `false` = tee-only ingest, requires the tee address (retry ≥ v1.10.1; not declared in `group_vars/all.yml`) |
| `metrics_addr` | `:9400` |  |
| `otlp_endpoint` | `""` |  |
| `otlp_interval` | `30s` |  |
| `enable_firewall` | `true` | Set `false` for labs only |
| `mgmt_cidrs_v4` | `[]` | **Must be set per-host**; SSH + metrics allow-list |

## Per-host overrides

Because `group_vars/all.yml` has higher precedence than inventory group vars,
the following must be set on each host (not in group vars):

- `mc_iface` and `ingress_iface` (set both to the same NIC)
- `mgmt_cidrs_v4`, `mgmt_cidrs_v6` — firewall allow-list; `group_vars/all.yml` defaults to empty lists
- `ansible_host`, `ansible_user`, `ansible_ssh_private_key_file`

## common role

Besides packages and the Go toolchain, `common` keeps the root filesystem
bounded on Linux hosts (journald `SystemMaxUse` drop-in plus a
`node-disk-maintenance.timer` that reclaims the apt cache and stale Go build
caches) and carries the opt-in patch path: `ansible-playbook site.yml --tags
os_update` dist-upgrades Debian-family hosts (rebooting when
`/var/run/reboot-required` appears) and runs `freebsd-update` + `pkg upgrade`
on FreeBSD (pending reboots are reported, never performed). Knobs live in
`roles/common/defaults/main.yml`:

| Variable | Default | Effect |
|----------|---------|--------|
| `common_disk_maintenance` | `true` | Install the reclaim timer; `false` removes it |
| `common_disk_maintenance_oncalendar` | `daily` | systemd `OnCalendar` for the timer |
| `common_disk_maintenance_splay_sec` | `3600` | `RandomizedDelaySec` so nodes do not fire in lockstep |
| `common_gocache_max_age_days` | `7` | Go build caches touched within this window are kept |
| `common_journal_max_use` | `300M` | journald `SystemMaxUse` |
| `common_journal_keep_free` | `1G` | journald `SystemKeepFree` |
| `common_journal_max_retention` | `2week` | journald `MaxRetentionSec` |

The reclaim script drops a node_exporter textfile under
`node_exporter_textfile_dir` (default `/var/lib/node_exporter/textfile_collector`).

## Common operations

```sh
# Re-deploy retry-endpoint code without touching firewall/networking
ansible-playbook site.yml --tags retry_endpoint

# Update firewall after changing mgmt CIDRs
ansible-playbook site.yml --tags firewall

# Apply high-PPS host tuning (UDP buffers, busy-poll, C-states, irqbalance)
ansible-playbook site.yml --tags perf-tuning

# Target one host
ansible-playbook site.yml -l retry-endpoint-01
```

The `perf-tuning` role (run before `retry-endpoint`) applies the same
host-level network/CPU tunings as `ingress-infra`. Knobs live in
`roles/perf-tuning/defaults/main.yml`; see
[ingress-infra ansible.md](https://github.com/lightwebinc/ingress-infra/blob/main/docs/ansible.md#perf-tuning-role)
for the variable reference.

## Known issues (inherited from `ingress-infra` / `listener-infra`)

- Ubuntu LXD images may lack `acl` — installed by the `common` role.
- The `git` module fails in some LXD images with "unsafe repository"; the
  role marks `retry_install_dir` as `safe.directory` before cloning.
- Remember: `group_vars/all.yml` beats inventory-group vars. Always set
  `mc_iface` and `mgmt_cidrs_*` on the host, not on the group.
- The binary build task is stat-guarded: it only compiles when the binary is
  missing or `retry_force_build=true`, so a plain `git` update does **not**
  trigger a rebuild. Set `retry_force_build=true` to rebuild from the
  checked-out source, or `retry_local_binary=<path>` to push a pre-built
  binary (skips git/build entirely). The `copy` step that follows only
  triggers a service restart when the binary actually changes.
