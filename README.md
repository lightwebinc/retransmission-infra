# retransmission-infra

[![Lint](https://github.com/lightwebinc/retransmission-infra/actions/workflows/lint.yml/badge.svg)](https://github.com/lightwebinc/retransmission-infra/actions/workflows/lint.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)

> Part of the [**BSV Layered Multicast**](https://github.com/lightwebinc/bsv-multicast) open-source project — see the main repository for the full architecture, design docs, and BRC specifications.

Ansible and Terraform automation for deploying
[`retry-endpoint`](https://github.com/lightwebinc/retry-endpoint)
nodes — the NACK-based retransmission cache in the BSV multicast pipeline.

```text
shard-listener ──NACK──▶  retry-endpoint  ──retransmit──▶  FF05::<shard>:9001
                                  (this repo deploys)
```

Includes a simplified perimeter firewall (nftables / pf) for UDP-only traffic.
No BGP integration — retry endpoints are pure cache-and-retransmit services.

## Platforms

Ubuntu 24.04, Debian 13 and FreeBSD 14 via Ansible; AWS EC2 or any SSH host via
Terraform. See [supported platforms](https://github.com/lightwebinc/bsv-multicast/blob/main/docs/infra/platforms.md).

## Quick Start

```sh
cd ansible
ansible-galaxy collection install -r requirements.yml
cp inventory/hosts.example.yml inventory/hosts.yml
$EDITOR inventory/hosts.yml
ansible-playbook -i inventory/hosts.yml site.yml
```

## Documentation

- [Shared host-deployment docs](https://github.com/lightwebinc/bsv-multicast/blob/main/docs/infra/README.md) (platforms, Ansible operations, Terraform layout, OS notes)
- [Architecture](docs/architecture.md)
- [Ansible usage](docs/ansible.md)
- [Security (perimeter firewall)](docs/security.md)
- [Networking](docs/networking.md)
- [Terraform](docs/terraform.md)
- OS notes: [Ubuntu 24.04](docs/os/ubuntu-24.04.md), [Debian 13](docs/os/debian-13.md), [FreeBSD 14](docs/os/freebsd-14.md)

## Repository Layout

```text
ansible/     Roles and playbooks
terraform/   Modules and cloud examples
docs/        Per-topic documentation
```

## License

Apache 2.0 — see [LICENSE](LICENSE).
