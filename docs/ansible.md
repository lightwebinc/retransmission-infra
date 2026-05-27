# Ansible usage

## Layout

```
ansible/
  site.yml                  Main playbook (retry_endpoint_nodes group)
  requirements.yml          Collection dependencies (community.general, ansible.posix)
  group_vars/all.yml        Default variables for all retry-endpoint nodes
  inventory/hosts.example.yml
  roles/
    common/                 Base OS deps + Go toolchain
    retry-endpoint/ Build + systemd / rc.d unit + config
    networking/             Interface / multicast route / GRE config
    firewall/               nftables (Linux) / pf (FreeBSD) perimeter (simplified)
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

`site.yml` runs roles in this order:

1. `common` — install packages, Go toolchain
2. `retry-endpoint` — build binary, install service
3. `networking` — configure `mc_iface`, GRE, multicast route
4. `firewall` *(when `enable_firewall: true`)* — lock down the perimeter

Firewall runs **after** networking so interface names resolve.

## Key variables

See `ansible/group_vars/all.yml` for the full list. Quick reference:

| Variable | Default | Notes |
|-------------------|------------|----------------------------------------------------|
| `mc_iface` | `eth0` | **Must be set per-host** (group_vars precedence) |
| `ingress_mode` | `ethernet` | Or `gre` |
| `listen_port` | `9300` | NACK receive port |
| `nack_port` | `9301` | NACK send port to listeners |
| `egress_iface` | `eth0` | Retransmission egress interface |
| `egress_port` | `9100` | Retransmission port to listeners |
| `shard_bits` | `2` | Must match fabric |
| `cache_backend` | `memory` | Or `redis` |
| `redis_addr` | `""` | Redis address (if cache_backend=redis) |
| `cache_ttl` | `60s` | Global fallback cache TTL; collapses per-FrameVer TTLs when explicitly set |
| `cache_ttl_tx` | `60s` | FrameVer V2 (BRC-124/128 regular tx) cache TTL |
| `cache_ttl_block` | `10m` | FrameVer V4 (BRC-131 block control) cache TTL |
| `cache_ttl_subtree` | `5m` | FrameVer V5 (BRC-132 subtree data) cache TTL |
| `cache_ttl_anchor` | `2m` | FrameVer V6 (BRC-134 anchor tx) cache TTL |
| `cache_max_keys` | `100000` | Maximum cache entries |
| `rl_ip_rate` | `1000/s` | Per-IP rate limit |
| `rl_sender_rate` | `10000/s` | Per-sender rate limit |
| `rl_global_rate` | `100000/s` | Global rate limit |
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

# Target one host
ansible-playbook site.yml -l retry-endpoint-01
```

## Known issues (inherited from `bitcoin-ingress` / `bitcoin-listener`)

- Ubuntu LXD images may lack `acl` — installed by the `common` role.
- The `git` module fails in some LXD images with "unsafe repository"; the
  role marks `retry_install_dir` as `safe.directory` before cloning.
- Remember: `group_vars/all.yml` beats inventory-group vars. Always set
  `mc_iface` and `mgmt_cidrs_*` on the host, not on the group.
- The binary build task runs on every playbook invocation (`changed_when: true`
  with no `creates:` guard) to ensure the installed binary always reflects the
  checked-out source. The `copy` step that follows only triggers a service
  restart when the binary actually changes.
