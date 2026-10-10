# Ansible usage

Shared workflow, requirements, variable precedence, version pins, the `common`
and `perf-tuning` roles, stat-guarded builds (`retry_force_build`,
`retry_local_binary`) and known issues are documented once in
[Ansible operations](https://github.com/lightwebinc/bsv-multicast/blob/main/docs/infra/ansible-operations.md). This page covers what is
specific to `retry-endpoint`.

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

## Role ordering

`site.yml` runs roles in this order on `retry_endpoint_nodes`:

1. `common` — install packages, Go toolchain, journald cap + disk-reclaim timer (Linux); opt-in `--tags os_update` patching
2. `perf-tuning` *(default on; skipped when `perf_tuning_enabled: false`)* — host network/CPU tuning
3. `retry-endpoint` — build binary, install service
4. `networking` — configure `mc_iface`, GRE, multicast route
5. `firewall` *(when `enable_firewall: true`)* — lock down the perimeter

Firewall runs **after** networking so interface names resolve. Optional
`redis_nodes` and `aerospike_nodes` plays (cache-backend hosts) run first.

## Per-host overrides

Because `group_vars/all.yml` has higher precedence than inventory group vars,
the following must be set on each host (not in group vars):

- `mc_iface` and `ingress_iface` (set both to the same NIC)
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

## Service variables

Every variable in `group_vars/all.yml`, with its default. Keep `retry_version`
at or above `v1.9.5` (earlier releases re-injected proxied cross-domain repairs
by multicast, amplifying repair storms).

### retry-endpoint source and build

| Variable | Default | Notes |
|---|---|---|
| `retry_repo` | `https://github.com/lightwebinc/retry-endpoint.git` | Git source of the service |
| `retry_version` | pinned in `group_vars/all.yml` | Git ref to build (tag, branch, or SHA); keep ≥ `v1.9.5` (see the note in `group_vars/all.yml`), and keep the `retry-endpoint-node` Terraform default in step |
| `retry_install_dir` | `/opt/retry-endpoint` | Clone and build directory |
| `retry_bin_dir` | `/usr/local/bin` | Binary install directory |
| `retry_user` | `retry-endpoint` | Service user |
| `retry_group` | `retry-endpoint` | Service group |
| `retry_local_binary` | `""` | Pre-built local binary to push; empty = clone and build on the host |
| `retry_force_build` | `false` | Rebuild even when a binary already exists |
| `go_version` | pinned in `group_vars/all.yml` | Go toolchain; must be at or above the `go` directive in the service go.mod at the pinned tag |
| `go_install_dir` | `/usr/local/go` | Go toolchain install directory |

### Retry-endpoint runtime configuration

| Variable | Default | Notes |
|---|---|---|
| `mc_iface` | `eth0` | **Must be set per-host** (group_vars precedence); the NIC the binary binds (`MC_IFACE`) and the firewall's fabric iface |
| `listen_port` | `9001` | Multicast frame receive (matches proxy/listener egress) |
| `nack_port` | `9300` | NACK receive (listeners dial this) |
| `egress_iface` | `eth0` | Retransmission egress interface |
| `egress_port` | `9001` | Retransmission multicast (matches listener ingress) |
| `egress_multicast_loop` | `false` | IPV6_MULTICAST_LOOP on retransmits (collapsed/mesh node only) |
| `retry_tee_listen` | `""` | Tee ingest: loopback address fed by a co-resident proxy/listener -retry-tee, e.g. "[::1]:9002" (empty = off). retry_mc_join_enabled false = tee-only ingest (no multicast join); requires retry_tee_listen. |
| `retry_mc_join_enabled` | `true` |  |
| `subtree_data_enabled` | `false` | BRC-132 subtree-data caching; under `ssm` also set `ssm_bootstrap_subtree_announce` |
| `beef_enabled` | `false` | BRC-148 BEEF plane caching; beef_shard_bits MUST match the proxies. |
| `beef_shard_bits` | `0` |  |
| `cache_ttl_beef` | `60s` |  |
| `shard_bits` | `2` | Must match fabric |
| `mc_scope` | `site` | link \| site \| org \| global |
| `mc_group_id` | `0x000B` | IANA group-id (default 0x000B = IANA Bitcoin) |
| `source_mode` | `asm` | Or `ssm` (then `bind_source` is required and `ssm_publishers_static` lists the publishers to (S,G)-join) |
| `bind_source` | `""` | per-node source address; REQUIRED when source_mode=ssm |
| `ssm_publishers_static` | `""` | comma-separated publisher addresses (ssm only) |
| `ssm_bootstrap_subtree_announce` | `""` | SSM sources of the subtree-announce group (with subtree_data_enabled) |
| `ssm_bootstrap_manifest` | `""` | SSM sources of the manifest group (rendered only when set) |
| `ssm_bootstrap_beacon` | `""` | SSM sources of the beacon group (rendered only when set) |
| `ssm_bootstrap_refresh` | `30s` | DNS re-resolve interval for SSM bootstrap entries |
| `cache_backend` | `memory` | Or `redis` / `aerospike` |
| `redis_addr` | `""` | Redis address (if cache_backend=redis) |
| `aerospike_hosts` | `""` | comma-separated host:port (required when cache_backend=aerospike); empty leaves Aerospike env unset |
| `aerospike_namespace` | `cache` | Aerospike namespace (must be provisioned; see aerospike role / docs/networking.md) |
| `aerospike_set` | `bre` | Aerospike set |
| `cache_dial_timeout` | `1s` | Backend dial timeout |
| `cache_op_timeout` | `1s` | Backend per-op timeout (fail-open on exceed; Aerospike TTL floor is 1s) |
| `cache_ttl` | `60s` | Global fallback cache TTL; collapses per-FrameVer TTLs when explicitly set |
| `cache_ttl_tx` | `60s` | FrameVer V2 (BRC-124/128 regular tx) cache TTL |
| `cache_ttl_block` | `10m` | FrameVer V4 (BRC-131 block control) cache TTL |
| `cache_ttl_subtree` | `5m` | FrameVer V5 (BRC-132 subtree data) cache TTL |
| `cache_ttl_anchor` | `2m` | FrameVer V6 (BRC-134 anchor tx) cache TTL |
| `dedup_window` | `2s` | Cross-instance retransmit dedup window; must be < NACK_BACKOFF_MAX (5s) so lost retransmits can be re-sent |
| `cache_max_keys` | `100000` | Maximum cache entries |
| `rl_ip_rate` | `1000` | Per-IP NACK rate limit |
| `rl_ip_burst` | `100` | Per-IP burst |
| `rl_chain_rate` | `500` | Max NACKs per window per (srcIP, chainID) |
| `rl_chain_window` | `1m` | Sliding window for per-chain NACK limiter |
| `rl_sequence_max` | `100` | Max requests per LookupSeq per sliding window |
| `rl_sequence_window` | `1m` | Per-LookupSeq sliding window |
| `rl_group_rate` | `200` | Retransmits per second per (srcIP, groupIdx) |
| `rl_group_burst` | `50` | Burst size per (srcIP, groupIdx) |
| `rl_throttle_response` | `false` | Emit THROTTLED hint on seq/chain/group throttle |

### BRC-126 cross-domain NACK relay (one-hop). OFF by default.

| Variable | Default | Notes |
|---|---|---|
| `proxy_enabled` | `false` | BRC-126 one-hop NACK relay to `upstream_retry_endpoints` (tuning: `proxy_workers`, `proxy_queue`, `proxy_timeout`, `proxy_max_endpoints`, `proxy_dedup_window`) |
| `upstream_retry_endpoints` | `""` | comma-separated upstream host:port (required when proxy_enabled) |
| `proxy_workers` | `4` | concurrent upstream fetches |
| `proxy_queue` | `1024` | queued relay requests before shedding |
| `proxy_timeout` | `300ms` | per-fetch upstream deadline; MUST exceed upstream RTT |
| `proxy_max_endpoints` | `0` | cap on upstreams tried per gap (0 = all) |
| `proxy_dedup_window` | `60s` | suppress duplicate upstream fetches for the same gap |
| `nack_addr` | `""` | Explicit IPv6 for NACK bind + ADVERT; empty = auto-detect |
| `beacon_enabled` | `true` | Enable ADVERT beacon multicasting |
| `beacon_tier` | `0` | 0 = closest to source |
| `beacon_preference` | `128` | Weighting within tier; higher = more preferred |
| `beacon_interval` | `60s` | Beacon multicast interval |
| `beacon_scope` | `site` | site \| org \| global \| both \| all |
| `beacon_flags_unicast` | `false` | Advertise unicast retransmit capability |
| `beacon_flags_multicast` | `true` | Advertise multicast retransmit capability |
| `beacon_flags_draining` | `false` | Set true during planned maintenance |
| `suppress_ack` | `false` | Suppress ACK responses (high-volume mode) |
| `suppress_miss` | `false` | Suppress MISS responses |
| `num_workers` | `0` | 0 = runtime.NumCPU() |
| `metrics_addr` | `:9400` | Metrics endpoint |
| `otlp_endpoint` | `""` | OTLP gRPC push; empty disables |
| `otlp_interval` | `30s` | OTLP metric export cadence |
| `log_format` | `json` | text \| json (json for fleet aggregation) |
| `log_level` | `info` | debug\|info\|warn\|error; runtime-togglable via POST /loglevel + SIGHUP |
| `trace_sampling` | `0` | 0..1 trace head sampling (0 = off; exports via otlp_endpoint) |
| `drain_timeout` | `0s` | Pre-shutdown drain |
| `instance_id` | `""` | OTel service.instance.id; empty = hostname |
| `retry_debug` | `false` |  |

### Firewall perimeter (simplified for UDP)

| Variable | Default | Notes |
|---|---|---|
| `enable_firewall` | `true` | Set `false` for labs only |
| `mgmt_cidrs_v4` | `[]` | **Must be set per-host**; SSH + metrics allow-list |
| `mgmt_cidrs_v6` | `[]` | SSH / metrics scrape allow-list (IPv6). |

### Networking

| Variable | Default | Notes |
|---|---|---|
| `ingress_mode` | `ethernet` | Or `gre` |
| `ingress_iface` | `eth0` | **Must be set per-host** and equal `mc_iface`; the NIC the `networking` role configures (netplan / rc.conf, multicast route) |
| `manage_netplan` | `true` | set false where the OS image / lab manages netplan itself |
| `gre_outer_proto` | `ipv6` | ipv6 \| ipv4 |
| `gre_iface` | `gre6-retry` | Tunnel interface name |
| `gre_inner_ipv6` | `""` | IPv6 address/prefix assigned to tunnel |
| `gre_local_ip6` | `""` | Local outer endpoint (ipv6 outer) |
| `gre_remote_ip6` | `""` | Remote outer endpoint (ipv6 outer) |
| `gre_local_ip4` | `""` | Local outer endpoint (ipv4 outer) |
| `gre_remote_ip4` | `""` | Remote outer endpoint (ipv4 outer) |

