# Ubuntu 24.04 (Noble)

Packages, systemd and netplan conventions and generic diagnostics shared by all
infra repositories are in the canonical
[Ubuntu 24.04 notes](https://github.com/lightwebinc/bsv-multicast/blob/main/docs/infra/os/ubuntu-24.04.md). This page lists what is specific to
`retry-endpoint`.

## Service

```sh
systemctl status retry-endpoint
systemctl restart retry-endpoint
journalctl -u retry-endpoint -f
```

## File locations

| Path | Content |
|---|---|
| `/etc/systemd/system/retry-endpoint.service` | systemd unit (template `retry-endpoint.service.j2`) |
| `/etc/retry-endpoint/config.env` | Environment config |
| `/etc/netplan/60-retry-endpoint.yaml` | Ingress ethernet |
| `/etc/netplan/61-retry-endpoint-gre.yaml` | GRE6 tunnel (`ingress_mode: gre`) |
| `/etc/sysctl.d/60-retry-endpoint.conf` | Sysctls |
| `/etc/nftables.d/60-retry-endpoint.nft` | Firewall ruleset (`nft list table inet retry-endpoint`) |

## Diagnostics

```sh
# Multicast frame receive (listen_port) and re-multicast (egress_port)
tcpdump -i eth0 -nn 'udp and ip6 multicast and port 9001'

# NACKs are unicast to nack_port (multicast on 9300 is beacon ADVERTs)
tcpdump -i eth0 -nn 'udp and port 9300 and not ip6 multicast'
```

## Known issues

- **`mc_iface` precedence.** Set it (and `ingress_iface`) per host, not in
  group vars.
