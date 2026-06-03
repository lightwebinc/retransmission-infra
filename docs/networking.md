# Networking

## Interface modes

### Ethernet mode (default)

The retry-endpoint receives NACK datagrams directly on a physical interface
(`mc_iface`, default `eth0`). This is the simplest mode and works for most
deployments.

```
┌─────────────────┐
│ retry-endpoint  │
│                 │
│ eth0 (mc_iface)│ ← NACK multicast from listeners
└─────────────────┘
```

### GRE tunnel mode

When the fabric is reached over a public IPv4 internet (or other routed
network), use GRE tunneling. The inner payload is always IPv6 multicast;
the outer transport can be IPv6 (ip6gre) or IPv4 (gre).

```
┌─────────────────┐
│ retry-endpoint  │
│                 │
│ eth0 (mgmt)     │ ← GRE outer transport
│ gre6-retry      │ ← IPv6 multicast (NACK receive)
└─────────────────┘
```

Configuration (in `ansible/group_vars/all.yml`):

```yaml
ingress_mode: "gre"
gre_outer_proto: "ipv6"  # or "ipv4"
gre_iface: "gre6-retry"
gre_inner_ipv6: "fd00::10/64"
gre_local_ip6: "2001:db8:a::10"
gre_remote_ip6: "2001:db8:feed::1"
```

Then set `mc_iface: gre6-retry` per-host in the inventory.

## Multicast routing

The retry-endpoint needs a multicast route prefix for the receive interface.
If `mc_route_prefix` is unset, it's auto-derived from `mc_scope`:

| `mc_scope` | Prefix |
|------------|-------------|
| `link` | `ff02::/16` |
| `site` | `ff05::/16` |
| `org` | `ff08::/16` |
| `global` | `ff0e::/16` |

The `networking` role installs this route via:

- **Linux**: `ip -6 route replace <prefix> dev <mc_iface>`
- **FreeBSD**: `route add -inet6 -net <prefix> -interface <mc_iface>`

## Netplan (Ubuntu 24.04)

When `ingress_mode=ethernet`, the `networking` role deploys a netplan config at
`/etc/netplan/60-retry-endpoint.yaml`. This config:

- Enables IPv6 RA acceptance on `ingress_iface`
- (Optional) Configures GRE tunnel when `ingress_mode=gre`

When `ingress_mode=gre`, a second netplan file
`/etc/netplan/61-retry-endpoint-gre.yaml` configures the tunnel.

## rc.conf (FreeBSD 14)

The `networking` role manages FreeBSD networking via `/etc/rc.conf`:

- Enables IPv6 globally
- Configures `ingress_iface` for IPv6 autoconfiguration
- (Optional) Configures GRE (gif) tunnel when `ingress_mode=gre`
- Adds persistent multicast route

Changes are applied via `service netif restart`.

## Cache backend connectivity

The frame cache backend (`cache_backend`) is an out-of-band TCP service on the
**management network**, not the multicast fabric. Open the relevant ports from
the retry-endpoint nodes to the backend nodes:

| Backend | Ports (TCP) | Notes |
|---------|-------------|-------|
| `redis` | 6379 | Redis/Valkey/Dragonfly client port |
| `aerospike` | 3000 (service), 3001 (fabric), 3003 (info) | client → 3000; 3001/3003 between Aerospike nodes |

The optional `aerospike` role provisions a Community Edition node with a
namespace matching `aerospike_namespace`. A multi-node Aerospike cluster also
uses a **mesh or multicast heartbeat** (default multicast `239.1.99.222:9918`
in the role's `aerospike.conf.j2`) on the node interconnect — keep it on the
management segment, away from the BSV multicast groups. Aerospike TTL is
whole-seconds (floor 1s); the retry-endpoint rounds up, and the namespace's
`default-ttl` MUST stay `0` so client-supplied per-frame TTLs are honoured.

Backend outages fail open: the retry endpoint treats cache errors as misses and
keeps serving, so a backend restart never blocks NACK handling.
