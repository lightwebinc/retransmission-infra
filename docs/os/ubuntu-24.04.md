# Ubuntu 24.04 (Noble)

## Service management

```sh
systemctl status retry-endpoint
systemctl restart retry-endpoint
journalctl -u retry-endpoint -f
```

Unit file: `/etc/systemd/system/retry-endpoint.service`
(see template `ansible/roles/retry-endpoint/templates/retry-endpoint.service.j2`).

Environment file: `/etc/retry-endpoint/config.env`.

## Network configuration

Netplan:

- `/etc/netplan/60-retry-endpoint.yaml` — ingress ethernet
- `/etc/netplan/61-retry-endpoint-gre.yaml` — GRE6 tunnel (when
  `ingress_mode: gre`)

Apply:

```sh
netplan apply
```

Sysctl: `/etc/sysctl.d/60-retry-endpoint.conf`.

## Firewall

nftables ruleset: `/etc/nftables.d/retry-endpoint.nft` (included from
`/etc/nftables.conf`).

```sh
nft list table inet retry-endpoint
systemctl status nftables
```

## Package installation

The `common` role installs:

- `acl`, `build-essential`, `git`, `curl`, `ca-certificates`, `tar`
- `nftables` (when `enable_firewall: true`)

The Go toolchain is installed to `/usr/local/go` (version configured via
`go_version`).

## Multicast diagnostics

```sh
# Multicast route
ip -6 route show ff00::/16

# Live NACK receive capture
tcpdump -i eth0 -nn 'udp and ip6 multicast and port 9300'

# Live re-multicast capture
tcpdump -i eth0 -nn 'udp and ip6 multicast and port 9100'

# Sysctl state
sysctl net.ipv6.conf.eth0.accept_ra
```

## Known issues

- **`mc_iface` precedence.** Must be set per-host, not on group_vars.
- **LXD `acl` missing.** Installed by `common` role.
- **`git` "dubious ownership".** Handled by setting `safe.directory`.
