# Networking

## Interface modes

### Ethernet mode (default)

The retry-endpoint receives multicast frames and unicast NACK datagrams
directly on a physical interface (`mc_iface`, default `eth0`). This is the
simplest mode and works for most deployments.

```
┌─────────────────┐
│ retry-endpoint  │
│                 │
│ eth0 (mc_iface)│ ← multicast frames + beacons; unicast NACKs from listeners
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
│ gre6-retry      │ ← IPv6 multicast frames + unicast NACKs
└─────────────────┘
```

Configuration (in `ansible/group_vars/all.yml`):

```yaml
ingress_mode: "gre"
gre_outer_proto: "ipv6"  # or "ipv4"
gre_iface: "gre6-retry"
gre_inner_ipv6: "2001:db8:2::10/64"
gre_local_ip6: "2001:db8:a::10"
gre_remote_ip6: "2001:db8:feed::1"
```

Then set `mc_iface` and `ingress_iface` to the tunnel per-host in the
inventory: `gre6-retry` on Linux, and `gif0` on FreeBSD, where the role always
names the tunnel `gif0` and does not read `gre_iface`.

## Multicast routing

The retry-endpoint needs a multicast route prefix for the receive interface.
If `mc_route_prefix` is unset, it's auto-derived from `mc_scope`:

| `mc_scope` | Prefix |
|------------|-------------|
| `link` | `ff02::/16` |
| `site` | `ff05::/16` |
| `org` | `ff08::/16` |
| `global` | `ff0e::/16` |

`link` is refused on FreeBSD hosts: FreeBSD reserves `ff02::/16` (at boot
`rc.d/routing` installs `ff02::/16 ::1 -reject`), so a link-scope multicast
route can never be installed there, and `site.yml` fails before any role
changes the host. The same applies to an `mc_route_prefix` of `ff02::/16` in any spelling.

The `networking` role installs this route on `ingress_iface`:

- **Linux**: `ip -6 route replace <prefix> dev <ingress_iface>`
- **FreeBSD**: `route add -inet6 -net <prefix> -interface <ingress_iface>`,
  run after any interface restart. The route is also persisted as
  `ipv6_route_retry_mcast` in `/etc/rc.conf` and listed in
  `ipv6_static_routes`, so a boot installs it.

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
- (Optional) Configures GRE (gif) tunnel when `ingress_mode=gre`, adding
  `gif0` to `cloned_interfaces` (interfaces already listed stay)
- Adds the multicast route (`ipv6_route_retry_mcast`) and lists `retry_mcast`
  in `ipv6_static_routes` (names already listed stay), so a boot installs it

Changes are applied by restarting only the changed interface, by name
(`service netif restart gif0` in GRE mode, which creates it, or the ingress
interface in ethernet mode), when its configuration above changed or `gif0` is
missing: a converge that changes nothing leaves `gif0`, the retry endpoint
bound to it and every other interface alone. The live multicast route is added
after the restart.

## Cache backend connectivity

The frame cache backend (`cache_backend`) is an out-of-band TCP service on the
**management network**, not the multicast fabric. Open the relevant ports from
the retry-endpoint nodes to the backend nodes:

| Backend | Ports (TCP) | Notes |
|---------|-------------|-------|
| `redis` | 6379 | Redis/Valkey/Dragonfly client port |
| `aerospike` | 3000 (service), 3001 (fabric), 3003 (info) | client → 3000; 3001/3003 between Aerospike nodes |

**Host firewall note**: the shipped host firewall (`enable_firewall: true`,
default-drop outbound) only renders an outbound allow for `redis_addr`, and
only in the nftables template. With `cache_backend=aerospike` (or `redis` on
FreeBSD/pf), extend the host ruleset with the outbound TCP allows above;
otherwise the backend is silently blocked and, because cache errors fail open
as misses, the endpoint degrades to a de facto memory-only cache.

The optional `aerospike` role provisions a Community Edition node with a
namespace matching `aerospike_namespace`. A multi-node Aerospike cluster also
uses a **mesh or multicast heartbeat** (default multicast `239.1.99.222:9918`
in the role's `aerospike.conf.j2`) on the node interconnect; keep it on the
management segment, away from the BSV multicast groups. Aerospike TTL is
whole-seconds (floor 1s); the retry-endpoint rounds up, and the namespace's
`default-ttl` MUST stay `0` so client-supplied per-frame TTLs are honored.

Backend outages fail open: the retry endpoint treats cache errors as misses and
keeps serving, so a backend restart never blocks NACK handling.
