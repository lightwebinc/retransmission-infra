variable "allocate_eips" {
  description = "Allocate Elastic IPs for each instance"
  type        = bool
  default     = false
}

variable "availability_zones" {
  description = "List of AZs to deploy subnets and instances into"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "enable_firewall" {
  description = "Enable host-level perimeter firewall"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment tag (e.g. production, staging)"
  type        = string
  default     = "production"
}

variable "fabric_source_cidrs_v6" {
  description = "IPv6 CIDRs from which the fabric may send NACK UDP to the retry endpoint (fabric is IPv6-only)"
  type        = list(string)
  default     = ["::/0"]
}

variable "gre_local_ip4" {
  description = "Local IPv4 endpoint for GRE tunnel (ingress_mode=gre, gre_outer_proto=ipv4)"
  type        = string
  default     = ""
}

variable "gre_local_ip6" {
  description = "Local IPv6 endpoint for ip6gre tunnel (ingress_mode=gre, gre_outer_proto=ipv6)"
  type        = string
  default     = ""
}

variable "gre_outer_proto" {
  description = "GRE outer transport: ipv6 (ip6gre / gif over v6) or ipv4 (gre / gif over v4). Inner is always IPv6."
  type        = string
  default     = "ipv6"
  validation {
    condition     = contains(["ipv4", "ipv6"], var.gre_outer_proto)
    error_message = "gre_outer_proto must be one of: ipv4, ipv6."
  }
}

variable "gre_remote_ip4" {
  description = "Remote IPv4 endpoint for GRE tunnel (ingress_mode=gre, gre_outer_proto=ipv4)"
  type        = string
  default     = ""
}

variable "gre_remote_ip6" {
  description = "Remote IPv6 endpoint for ip6gre tunnel (ingress_mode=gre, gre_outer_proto=ipv6)"
  type        = string
  default     = ""
}

variable "ingress_iface" {
  description = "Ingress interface name on the target host"
  type        = string
  default     = "eth0"
}

variable "ingress_mode" {
  description = "Ingress interface mode: ethernet or gre"
  type        = string
  default     = "ethernet"
}

variable "instance_count" {
  description = "Number of EC2 retry-endpoint nodes to create"
  type        = number
  default     = 1
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of the AWS EC2 key pair for SSH access"
  type        = string
}

variable "listen_port" {
  description = "UDP port for NACK receive"
  type        = number
  default     = 9300
}

variable "mc_route_prefix" {
  description = "IPv6 multicast route prefix for the ingress interface (empty = auto-derive from mc_scope)"
  type        = string
  default     = ""
}

variable "metrics_allowed_cidrs" {
  description = "CIDR ranges allowed to reach the metrics port (9400)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "mgmt_cidrs_v6" {
  description = "IPv6 CIDRs for host-level firewall mgmt allow-list"
  type        = list(string)
  default     = []
}

variable "name_prefix" {
  description = "Prefix for all resource names"
  type        = string
  default     = "bitcoin-retry-endpoint"
}

variable "shard_bits" {
  description = "Shard bit width (1-24); must match fabric"
  type        = number
  default     = 2
}

variable "ssh_allowed_cidrs" {
  description = "CIDR ranges allowed to SSH to retry-endpoint nodes"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ssh_private_key" {
  description = "Path to the local SSH private key file"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.10.0.0/16"
}
