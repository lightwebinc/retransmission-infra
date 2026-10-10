# Terraform usage

Module and example structure, requirements, the Ansible hand-off, running the
`generic` and `aws-ec2` examples and adding a cloud are documented once in
[Terraform layout](https://github.com/lightwebinc/bsv-multicast/blob/main/docs/infra/terraform-layout.md). This page covers what is specific
to retransmission-infra.

## Module

`modules/retry-endpoint-node` provisions one retry-endpoint host. Inputs cover
the full configuration (ports, shard bits, cache backend, rate limits, metrics,
OTLP interval, firewall mgmt CIDRs). There is no BGP helper.

`retry_version` in `modules/retry-endpoint-node/variables.tf` must equal
`retry_version` in `ansible/group_vars/all.yml`, the single source of truth, and
like it must never drop below **`v1.9.5`**: earlier releases re-injected
proxied cross-domain repairs by multicast whatever the retransmit mode, the
amplifier behind own-source repair storms. A stale Terraform default puts that
build back on a node while `group_vars` still reads as pinned
([version pin coupling](https://github.com/lightwebinc/bsv-multicast/blob/main/docs/infra/terraform-layout.md#version-pin-coupling)).

## Cloud firewall

The AWS example's security group is the cloud-level perimeter; the on-host
nftables ruleset from the `firewall` role is the fine-grained one (see
[security.md](security.md)). A cloud firewall for retry endpoints must permit:

- UDP/`listen_port` (9001, multicast frames) and UDP/`nack_port` (9300, NACK)
  inbound from fabric sources
- UDP/`egress_port` (9001) and UDP/`nack_port` (9300) outbound to the fabric
- TCP/22 and TCP/9400 from `mgmt_cidrs_*`

## Defaults worth double-checking

| Variable | Default | Why |
|-------------------|----------|-------------------------------------------------------------|
| `listen_port` | `9001` | Multicast frame receive (matches proxy/listener egress) |
| `nack_port` | `9300` | NACK receive (listeners dial this) |
| `egress_port` | `9001` | Retransmission multicast (matches listener ingress) |
| `metrics_addr` | `:9400` | Avoid collision with listener (`:9200`) and proxy (`:9100`) |
| `enable_firewall` | `true` | Default-on for security |
| `otlp_interval` | `"30s"` | Preserves prior hardcoded value |
| `cache_backend` | `memory` | In-memory cache by default |
