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

1. `common` — install packages, Go toolchain
2. `perf-tuning` *(when `perf_tuning_enabled: true`)* — host network/CPU tuning
3. `retry-endpoint` — build binary, install service
4. `networking` — configure `mc_iface`, GRE, multicast route
5. `firewall` *(when `enable_firewall: true`)* — lock down the perimeter

Firewall runs **after** networking so interface names resolve. Optional
`redis_nodes` and `aerospike_nodes` plays (cache-backend hosts) run first.

## Key variables

See `ansible/group_vars/all.yml` for the full list. Quick reference:

| Variable | Default | Notes |
|-------------------|------------|----------------------------------------------------|
| `mc_iface` | `eth0` | **Must be set per-host** (group_vars precedence) |
| `ingress_mode` | `ethernet` | Or `gre` |
| `listen_port` | `9001` | Multicast frame receive (matches proxy/listener egress) |
| `nack_port` | `9300` | NACK receive (listeners dial this) |
| `egress_iface` | `eth0` | Retransmission egress interface |
| `egress_port` | `9001` | Retransmission multicast (matches listener ingress) |
| `shard_bits` | `2` | Must match fabric |
| `retry_version` | `v1.5.0` | Git ref to build (tag, branch, or SHA) |
| `retry_force_build` | `false` | Force a rebuild even if the binary exists |
| `retry_local_binary` | `""` | Push a pre-built local binary (skips git/build) |
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
| `metrics_addr` | `:9400` |  |
| `otlp_endpoint` | `""` |  |
| `otlp_interval` | `30s` |  |
| `enable_firewall` | `true` | Set `false` for labs only |
| `mgmt_cidrs_v4` | `[]` | **Must be set per-host**; SSH + metrics allow-list |

## Per-host overrides

Because `group_vars/all.yml` has higher precedence than inventory group vars,
the following must be set on each host (not in group vars):

- `mc_iface`
- `mgmt_cidrs_v4`, `mgmt_cidrs_v6` — firewall allow-list; `group_vars/all.yml` defaults to empty lists
- `ansible_host`, `ansible_user`, `ansible_ssh_private_key_file`

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
