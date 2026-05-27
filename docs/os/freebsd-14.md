# FreeBSD 14

## Service management

```sh
service retry_endpoint status
service retry_endpoint restart
tail -f /var/log/retry_endpoint.log
```

rc.d script: `/usr/local/etc/rc.d/retry_endpoint`
(see template `ansible/roles/retry-endpoint/templates/retry_endpoint.rc.j2`).

Environment file: `/usr/local/etc/retry-endpoint.conf`.

Enable at boot:

```sh
sysrc retry_endpoint_enable=YES
```

## Network configuration

`/etc/rc.conf` entries managed by the `networking` role:

- `ifconfig_<iface>`, `ifconfig_<iface>_ipv6` (ethernet ingress)
- `cloned_interfaces="gif0"` + `ifconfig_gif0*` (GRE mode)
- `ipv6_route_retry_mcast` (multicast route on ingress iface)

Apply:

```sh
service netif restart
service routing restart
```

## Firewall (pf)

Anchor file: `/etc/pf.d/retry-endpoint.conf`, loaded from `/etc/pf.conf`
via an include line.

```sh
pfctl -sr
pfctl -f /etc/pf.conf
```

Enable:

```sh
sysrc pf_enable=YES pflog_enable=YES
service pf start
```

## Packages

The `common` role installs via `pkg`:

- `gmake`, `git`, `curl`, `ca_root_nss`, `bash`, `tar`

Go toolchain: `/usr/local/go` (via tarball download).

## Multicast diagnostics

```sh
# Multicast route
netstat -rn -f inet6 | grep ff

# Live NACK receive capture
tcpdump -i vtnet0 -nn 'udp and ip6 multicast and port 9300'

# Live re-multicast capture
tcpdump -i vtnet0 -nn 'udp and ip6 multicast and port 9100'
```

## Known issues

- **Interface naming.** FreeBSD uses `vtnet0` / `em0` — set `mc_iface`
  per-host accordingly.
- **`gif` interface name** is hard-coded in the rc.conf template to `gif0`.
  If multiple tunnels are needed, adapt the template.
