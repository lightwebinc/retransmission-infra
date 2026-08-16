# Security

## Perimeter model

The retry-endpoint enforces a simplified perimeter (UDP-only, no BGP):

- **Fabric interface** (`mc_iface`): multicast frame + NACK receive (inbound), re-multicast (outbound)
- **Non-fabric interfaces**: SSH + metrics (inbound from `mgmt_cidrs_*`)
- **Forwarding**: disabled

This is enforced at two levels:

1. **Cloud-level** (AWS SG, GCP firewall rules, etc.) — coarse-grained
2. **Host-level** (nftables on Linux, pf on FreeBSD) — fine-grained

Both must stay aligned.

## Host-level firewall

The `firewall` Ansible role deploys:

- **Linux**: `/etc/nftables.d/60-retry-endpoint.nft`
- **FreeBSD**: `/etc/pf.d/retry-endpoint.conf`

### Input chain (inbound)

Allowed on fabric interface (`mc_iface`):
- ICMPv6 (NDP, MLD, diagnostics)
- UDP/`listen_port` (9001) to ff00::/8 (multicast frame receive)
- UDP/`nack_port` (9300) unicast (NACK receive)

Allowed on non-fabric interfaces:
- ICMPv4 (echo, dest-unreachable)
- TCP/22 (SSH) from `mgmt_cidrs_v4`
- TCP/9400 (metrics) from `mgmt_cidrs_v4`
- IPv6 equivalents from `mgmt_cidrs_v6`
- GRE (protocol 47) from the tunnel remote (when `ingress_mode=gre`)
- DNS/NTP/HTTP/HTTPS outbound

### Output chain (outbound)

Allowed from fabric interface:
- ICMPv6 (NDP, MLD, diagnostics)
- UDP/`egress_port` (9001) and UDP/`nack_port` (9300) to ff00::/8
  (re-multicast + beacon ADVERT)
- Unicast UDP from source port `nack_port` (9300) — ACK/MISS responses

Allowed from non-fabric interfaces:
- ICMPv4
- GRE (protocol 47) to the tunnel remote (when `ingress_mode=gre`)
- DNS/NTP/HTTP/HTTPS outbound
- TCP to the Redis backend port (when `redis_addr` set)

### Forward chain

Always dropped — retry-endpoint does not route.

## Management CIDRs

Set `mgmt_cidrs_v4` and `mgmt_cidrs_v6` in `ansible/group_vars/all.yml` or
per-host in the inventory. These CIDRs control:

- SSH access (TCP/22)
- Prometheus metrics scrape (TCP/9400)

**Important**: `group_vars/all.yml` has higher precedence than inventory group
vars. Always set `mgmt_cidrs_*` on each host, not on the group.

## Cloud-level firewall (AWS example)

The AWS EC2 example creates a security group with rules that mirror the
host-level rules:

- Inbound UDP/9300 (NACK) from `fabric_source_cidrs_v6` (default `::/0` — tighten this)
- Inbound TCP/22 from `ssh_allowed_cidrs`
- Inbound TCP/9400 from `metrics_allowed_cidrs`
- Outbound all (host-level nftables narrows further)

When deploying to other clouds, ensure your cloud firewall rules align with
the host-level ruleset.

## Hardening

The systemd unit (`retry-endpoint.service`) includes:

- `NoNewPrivileges=true`
- `PrivateTmp=true`
- `ProtectSystem=strict`
- `ReadWritePaths={{ retry_install_dir }}`
- `AmbientCapabilities=CAP_NET_BIND_SERVICE`

The FreeBSD rc.d script runs the daemon as the unprivileged
`retry-endpoint` user.
