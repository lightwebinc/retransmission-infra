# FreeBSD 14

Packages, rc.d and rc.conf conventions, pf usage, `gif0` tunnels and generic
diagnostics shared by all infra repositories are in the canonical
[FreeBSD 14 notes](https://github.com/lightwebinc/bsv-multicast/blob/main/docs/infra/os/freebsd-14.md). This page lists what is specific to
`retry-endpoint`.

## Service

```sh
sysrc retry_endpoint_enable=YES
service retry_endpoint status
service retry_endpoint restart
tail -f /var/log/retry_endpoint.log
```

## File locations

| Path | Content |
|---|---|
| `/usr/local/etc/rc.d/retry_endpoint` | rc.d script (template `retry_endpoint.rc.j2`) |
| `/usr/local/etc/retry-endpoint.conf` | Environment config |
| `/etc/pf.d/retry-endpoint.conf` | pf rules, included from `/etc/pf.conf` |

`/etc/rc.conf` also carries `ipv6_route_retry_mcast` (multicast route on the
ingress interface).

## Diagnostics

```sh
tcpdump -i vtnet0 -nn 'udp and ip6 multicast and port 9001'
tcpdump -i vtnet0 -nn 'udp and port 9300 and not ip6 multicast'   # NACKs
```

## Known issues

- Set `mc_iface` per host to the FreeBSD name (`vtnet0`, `em0`, ...).
