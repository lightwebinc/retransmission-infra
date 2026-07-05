terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------
# Data: latest Ubuntu 24.04 AMI
# ---------------------------------------------------------------
data "aws_ami" "ubuntu_24_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------
# VPC and networking
# ---------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block                       = var.vpc_cidr
  enable_dns_hostnames             = true
  enable_dns_support               = true
  assign_generated_ipv6_cidr_block = true

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${var.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  count                           = length(var.availability_zones)
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = cidrsubnet(var.vpc_cidr, 4, count.index)
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.main.ipv6_cidr_block, 8, count.index)
  availability_zone               = var.availability_zones[count.index]
  map_public_ip_on_launch         = true
  assign_ipv6_address_on_creation = true

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-public-${count.index}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-rt-public" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------
# Security group
#
# Note: this SG is the cloud-level perimeter. On-host nftables/pf rules
# (provisioned by the `firewall` Ansible role) enforce the finer-grained
# isolation. Keep this SG aligned with those rules.
# ---------------------------------------------------------------
resource "aws_security_group" "retry_endpoint_node" {
  name        = "${var.name_prefix}-retry-endpoint-node"
  description = "retry-endpoint node"
  vpc_id      = aws_vpc.main.id

  tags = merge(local.common_tags, { Name = "${var.name_prefix}-sg" })
}

# NACK receive (UDP) — fabric is IPv6-only
resource "aws_vpc_security_group_ingress_rule" "nack_udp6" {
  for_each = toset(var.fabric_source_cidrs_v6)

  security_group_id = aws_security_group.retry_endpoint_node.id
  description       = "NACK receive UDP (IPv6)"
  from_port         = var.nack_port
  to_port           = var.nack_port
  ip_protocol       = "udp"
  cidr_ipv6         = each.value
}

# GRE outer-transport (ingress_mode = "gre")
resource "aws_vpc_security_group_ingress_rule" "gre_outer_v4" {
  count = var.ingress_mode == "gre" && var.gre_outer_proto == "ipv4" && var.gre_remote_ip4 != "" ? 1 : 0

  security_group_id = aws_security_group.retry_endpoint_node.id
  description       = "GRE outer transport (IPv4) from tunnel peer"
  ip_protocol       = "47"
  cidr_ipv4         = "${var.gre_remote_ip4}/32"
}

resource "aws_vpc_security_group_ingress_rule" "gre_outer_v6" {
  count = var.ingress_mode == "gre" && var.gre_outer_proto == "ipv6" && var.gre_remote_ip6 != "" ? 1 : 0

  security_group_id = aws_security_group.retry_endpoint_node.id
  description       = "GRE outer transport (IPv6) from tunnel peer"
  ip_protocol       = "47"
  cidr_ipv6         = "${var.gre_remote_ip6}/128"
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_allowed_cidrs)

  security_group_id = aws_security_group.retry_endpoint_node.id
  description       = "SSH management"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "metrics" {
  for_each = toset(var.metrics_allowed_cidrs)

  security_group_id = aws_security_group.retry_endpoint_node.id
  description       = "Prometheus metrics"
  from_port         = 9400
  to_port           = 9400
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.retry_endpoint_node.id
  description       = "Allow all outbound (IPv4) — host-level nftables/pf narrows further"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "all6" {
  security_group_id = aws_security_group.retry_endpoint_node.id
  description       = "Allow all outbound (IPv6) — host-level nftables/pf narrows further"
  ip_protocol       = "-1"
  cidr_ipv6         = "::/0"
}

# ---------------------------------------------------------------
# EC2 instances
# ---------------------------------------------------------------
resource "aws_instance" "retry_endpoint_node" {
  count         = var.instance_count
  ami           = data.aws_ami.ubuntu_24_04.id
  instance_type = var.instance_type
  key_name      = var.key_name
  subnet_id     = aws_subnet.public[count.index % length(aws_subnet.public)].id

  vpc_security_group_ids = [aws_security_group.retry_endpoint_node.id]

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-node-${count.index + 1}"
  })
}

# Optional Elastic IPs (for stable inbound addressing)
resource "aws_eip" "retry_endpoint_node" {
  count  = var.allocate_eips ? var.instance_count : 0
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-eip-${count.index + 1}"
  })
}

resource "aws_eip_association" "retry_endpoint_node" {
  count         = var.allocate_eips ? var.instance_count : 0
  instance_id   = aws_instance.retry_endpoint_node[count.index].id
  allocation_id = aws_eip.retry_endpoint_node[count.index].id
}

locals {
  common_tags = {
    Project     = "retry-endpoint"
    ManagedBy   = "terraform"
    Environment = var.environment
  }

  # Use EIP if allocated, otherwise use the public IP assigned to the instance.
  node_ips = var.allocate_eips ? [for eip in aws_eip.retry_endpoint_node : eip.public_ip] : [
    for inst in aws_instance.retry_endpoint_node : inst.public_ip
  ]
}

# ---------------------------------------------------------------
# Provision each instance via Ansible
# ---------------------------------------------------------------
module "retry_endpoint_nodes" {
  source = "../../modules/retry-endpoint-node"
  count  = var.instance_count

  host_ip              = local.node_ips[count.index]
  ssh_user             = "ubuntu"
  ssh_private_key_path = var.ssh_private_key

  shard_bits      = var.shard_bits
  ingress_mode    = var.ingress_mode
  ingress_iface   = var.ingress_iface
  mc_route_prefix = var.mc_route_prefix

  gre_inner_ipv6  = ""
  gre_local_ip4   = var.gre_local_ip4 != "" ? var.gre_local_ip4 : aws_instance.retry_endpoint_node[count.index].private_ip
  gre_local_ip6   = var.gre_local_ip6 != "" ? var.gre_local_ip6 : try(aws_instance.retry_endpoint_node[count.index].ipv6_addresses[0], "")
  gre_outer_proto = var.gre_outer_proto
  gre_remote_ip4  = var.gre_remote_ip4
  gre_remote_ip6  = var.gre_remote_ip6

  nack_port = var.nack_port

  enable_firewall = var.enable_firewall
  mgmt_cidrs_v4   = concat(var.ssh_allowed_cidrs, var.metrics_allowed_cidrs)
  mgmt_cidrs_v6   = var.mgmt_cidrs_v6

  depends_on = [aws_instance.retry_endpoint_node, aws_eip.retry_endpoint_node]
}
