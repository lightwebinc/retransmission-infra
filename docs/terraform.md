# Terraform usage

Terraform orchestrates cloud infrastructure and hands off per-host provisioning
to the Ansible playbook in `ansible/`.

## Modules

### `modules/retry-endpoint-node`

Provisions a single retry-endpoint host:

1. Renders a per-host Ansible inventory (`generated-inventory-*.yml`).
2. Runs `ansible-playbook site.yml` via `local-exec`, passing all retry-endpoint
   variables as `--extra-vars`.

Inputs include the full retry-endpoint configuration (ports, shard bits,
cache backend, rate limits, metrics, OTLP interval, firewall mgmt CIDRs).

## Examples

### `examples/generic/`

Cloud-agnostic. Accepts a list of existing hosts and provisions each via
Ansible. Use this when you already have VMs (e.g. bare metal, a lab, or
another IaC tool created them).

```sh
cd terraform/examples/generic
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
terraform init
terraform apply
```

### `examples/aws-ec2/`

Provisions VPC, subnets, SGs, EC2 instances (Ubuntu 24.04), optional EIPs,
then runs Ansible.

```sh
cd terraform/examples/aws-ec2
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars
terraform init
terraform apply
```

The AWS example creates a Security Group that is the cloud-level perimeter.
The on-host nftables ruleset (deployed by the `firewall` Ansible role) is
the fine-grained perimeter. Both must stay aligned — see
[`security.md`](security.md).

## Extending to other clouds

Copy `examples/generic/` or `examples/aws-ec2/` and adapt:

1. Create VMs / VPC / security groups.
2. Collect the resulting host IPs into `local.node_ips` (or equivalent).
3. Pass them to `module.retry_endpoint_nodes` (one instance per host).
4. Ensure cloud-level firewall permits:
   - UDP/`listen_port` (9001, multicast frames) and UDP/`nack_port` (9300,
     NACK) inbound from fabric sources
   - UDP/`egress_port` (9001) and UDP/`nack_port` (9300) outbound to fabric
   - TCP/22 and TCP/9400 from `mgmt_cidrs_*`
   - Outbound per your organisation's policy

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
