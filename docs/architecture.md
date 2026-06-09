# Architecture

`retransmission-infra` is the deployment/operations repo for
[`retry-endpoint`](https://github.com/lightwebinc/retry-endpoint) — the
NACK-aware retransmission node in the Bitcoin shard multicast fabric. When
listeners detect sequence gaps, they send NACK datagrams to retry-endpoint
nodes, which cache frames and re-multicast missing data.

```
       ┌───────────────┐     IPv6 multicast fabric      ┌────────────────┐
       │ shard-listener│ ───►  NACK (UDP, send-only)  ──► retry-endpoint │
       │               │                                │                │
       └───────────────┘                                └──────┬─────────┘
                                                               │ re-multicast
                                                               ▼
                                                     ┌─────────────────┐
                                                     │ shard-listener  │
                                                     │ (receive path)  │
                                                     └─────────────────┘
```

## Protocol details

Deploys `retry-endpoint`, which caches and retransmits BRC-124/BRC-128 tx frames,
BRC-130 fragments, BRC-131 block control, BRC-132 subtree data, and BRC-134 anchor frames.
All frame versions share a single `HashKey ∥ SeqNum` cache key, so the retransmit path is
frame-version-agnostic. NACK/ACK/MISS wire formats, cache indexing scheme, rate limiting
tiers, and beacon discovery are documented in the service and project repos:

- [retry-endpoint — Architecture](https://github.com/lightwebinc/retry-endpoint/blob/main/docs/architecture.md)
- [retry-endpoint — Configuration](https://github.com/lightwebinc/retry-endpoint/blob/main/docs/configuration.md)
- [bsv-multicast — DESIGN.md](https://github.com/lightwebinc/bsv-multicast/blob/main/DESIGN.md)
- BRC drafts: `bsv-multicast/docs/brc-{124,126,127,128,129,130,131,132,133,134,135,139}-*.md`

## Data plane

1. **NACK receive** — Listeners send NACK datagrams via unicast UDP to
   `retry-endpoint` nodes on `nack_port` (default 9300).
2. **Cache lookup + rate limiting** — The retry-endpoint looks up the
   requested frame and applies multi-tier rate limiting.
3. **Response** — ACK if retransmit dispatched; MISS if not in cache
   (triggers listener escalation to the next endpoint).
4. **Retransmission** — Cached frames are re-multicasted via UDP on
   `egress_port` (default 9001) to the fabric, where listeners receive them
   on their normal multicast path.

## Cache backends

| `CACHE_BACKEND` | `REDIS_ADDR`          | Frame cache                          | Dedup                 | Use case                                       |
| --------------- | --------------------- | ------------------------------------ | --------------------- | ---------------------------------------------- |
| `memory`        | empty                 | striped in-memory map (per-instance) | none                  | Single-node; default                           |
| `memory`        | set                   | striped in-memory map (per-instance) | Redis SET NX          | Multi-node; per-instance frames + shared dedup |
| `redis`         | set (required)        | Redis (shared)                       | Redis SET NX          | Multi-node; fully shared cache + dedup         |
| `aerospike`     | `AEROSPIKE_HOSTS` set | Aerospike (shared)                   | Aerospike CREATE_ONLY | Largest fleets; auto-sharded hybrid RAM/SSD    |

The `memory` + `REDIS_ADDR` mode (row 2) is used in the LXD lab:
retry1/2/3 each maintain their own frame cache (preserving MISS-escalation
logic), while Redis deduplicates redundant retransmits when all three
endpoints receive NACKs for the same gap simultaneously.

When `REDIS_ADDR` is empty and `CACHE_BACKEND=redis`, startup fails with
an explicit error. When `CACHE_BACKEND=memory` and `REDIS_ADDR` is set,
a separate Redis connection is opened with the `bre:dedup:` key prefix
(distinct from the `bre:frame:` prefix used for full Redis frame storage).

## Control plane

- **Metrics** (Prometheus + OTLP) exposed on `:9400/healthz`, `:9400/readyz`,
  `:9400/metrics`. `OTLP_INTERVAL` controls the push cadence (default 30 s).
- **Firewall** (nftables on Linux, pf on FreeBSD) enforces a simplified
  perimeter (UDP-only, no BGP). See `security.md`.

## How this repo is organised

| Layer     | Location     | Purpose                                     |
| --------- | ------------ | ------------------------------------------- |
| Ansible   | `ansible/`   | Roles + playbooks for provisioning          |
| Terraform | `terraform/` | Node module + AWS / generic examples        |
| Docs      | `docs/`      | Architecture, ops, security, networking, OS |

## Relationship to other repos

| Concern       | `retransmission-infra` (this repo) | `listener-infra` | `ingress-infra`  |
| ------------- | ------------------------------------ | ------------------ | ------------------ |
| Direction     | RX NACK → TX re-multicast            | RX multicast       | TX multicast       |
| Primary iface | `mc_iface` (receive)                 | `ingress_iface`    | `egress_iface`     |
| Metrics port  | `:9400`                              | `:9200`            | `:9100`            |
| Listen port   | `9300` (NACK receive)                | `9001`             | `9000`             |
| Egress port   | `9001` (re-multicast)                | `egress_addr`      | `9001` (multicast) |
| BGP           | **No**                               | Optional           | Optional           |
| Firewall      | Simplified UDP                       | Full perimeter     | n/a                |

Shared patterns: Go toolchain install, systemd unit hardening, netplan-based
interface config on Ubuntu, rc.d on FreeBSD, management-plane helpers.
