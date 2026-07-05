variable "aerospike_hosts" {
  description = "Comma-separated Aerospike host:port list (required when cache_backend=aerospike)"
  type        = string
  default     = ""
}

variable "aerospike_namespace" {
  description = "Aerospike namespace (must be provisioned on the cluster)"
  type        = string
  default     = "cache"
}

variable "aerospike_set" {
  description = "Aerospike set name"
  type        = string
  default     = "bre"
}

variable "ansible_inventory_path" {
  description = "Path to write the generated Ansible inventory file"
  type        = string
  default     = ""
}

variable "ansible_playbook_path" {
  description = "Absolute path to the Ansible site.yml playbook"
  type        = string
  default     = ""
}

variable "cache_backend" {
  description = "Cache backend: memory, redis, or aerospike"
  type        = string
  default     = "memory"

  validation {
    condition     = contains(["aerospike", "memory", "redis"], var.cache_backend)
    error_message = "cache_backend must be 'memory', 'redis', or 'aerospike'."
  }
}

variable "cache_max_keys" {
  description = "Maximum cache entries"
  type        = number
  default     = 100000
}

variable "cache_ttl" {
  description = "Global fallback cache TTL (Go duration); collapses all per-FrameVer TTLs when explicitly set"
  type        = string
  default     = "60s"
}

variable "cache_ttl_anchor" {
  description = "Cache TTL for FrameVer V6 (BRC-134 anchor tx)"
  type        = string
  default     = "2m"
}

variable "cache_ttl_block" {
  description = "Cache TTL for FrameVer V4 (BRC-131 block control)"
  type        = string
  default     = "10m"
}

variable "cache_ttl_subtree" {
  description = "Cache TTL for FrameVer V5 (BRC-132 subtree data)"
  type        = string
  default     = "5m"
}

variable "cache_ttl_tx" {
  description = "Cache TTL for FrameVer V2 (BRC-124/128 regular tx)"
  type        = string
  default     = "60s"
}

variable "egress_iface" {
  description = "Interface for retransmission egress"
  type        = string
  default     = "eth0"
}

variable "egress_port" {
  description = "UDP port for retransmission multicast (matches listener ingress)"
  type        = number
  default     = 9001
}

variable "enable_firewall" {
  description = "Enable nftables/pf perimeter rules (default on for security)"
  type        = bool
  default     = true
}

variable "extra_ansible_vars" {
  description = "Additional Ansible variables to pass as --extra-vars"
  type        = map(any)
  default     = {}
}

variable "gre_inner_ipv6" {
  description = "IPv6 address/prefix assigned to the tunnel interface"
  type        = string
  default     = ""
}

variable "gre_local_ip4" {
  description = "Local IPv4 address for the GRE tunnel endpoint (ingress_mode=gre, gre_outer_proto=ipv4)"
  type        = string
  default     = ""
}

variable "gre_local_ip6" {
  description = "Local IPv6 address for the ip6gre tunnel endpoint (ingress_mode=gre only)"
  type        = string
  default     = ""
}

variable "gre_outer_proto" {
  description = "GRE outer transport: ipv6 (ip6gre) or ipv4 (gre). Inner is always IPv6."
  type        = string
  default     = "ipv6"

  validation {
    condition     = contains(["ipv4", "ipv6"], var.gre_outer_proto)
    error_message = "gre_outer_proto must be one of: ipv4, ipv6."
  }
}

variable "gre_remote_ip4" {
  description = "Remote IPv4 address for the GRE tunnel endpoint (ingress_mode=gre, gre_outer_proto=ipv4)"
  type        = string
  default     = ""
}

variable "gre_remote_ip6" {
  description = "Remote IPv6 address for the ip6gre tunnel endpoint (ingress_mode=gre only)"
  type        = string
  default     = ""
}

variable "host_ip" {
  description = "Public IP address of the target host"
  type        = string
}

variable "ingress_iface" {
  description = "Multicast ingress interface (per host). For GRE mode use gre_iface."
  type        = string
  default     = "eth0"
}

variable "ingress_mode" {
  description = "Ingress interface mode: ethernet or gre"
  type        = string
  default     = "ethernet"

  validation {
    condition     = contains(["ethernet", "gre"], var.ingress_mode)
    error_message = "ingress_mode must be 'ethernet' or 'gre'."
  }
}

variable "listen_port" {
  description = "UDP port for multicast frame receive (matches proxy egress)"
  type        = number
  default     = 9001
}

variable "mc_group_id" {
  description = "IANA group-id (bytes 12-13 of the IPv6 multicast address); default 0x000B = IANA Bitcoin allocation FF0X::B"
  type        = string
  default     = "0x000B"
}

variable "mc_iface" {
  description = "Interface for multicast receive"
  type        = string
  default     = "eth0"
}

variable "mc_route_prefix" {
  description = "IPv6 multicast route prefix for the ingress interface (empty = auto-derive from mc_scope)"
  type        = string
  default     = ""
}

variable "mc_scope" {
  description = "Multicast scope: link, site, org, or global"
  type        = string
  default     = "site"
}

variable "metrics_addr" {
  description = "HTTP bind address for /metrics, /healthz, /readyz"
  type        = string
  default     = ":9400"
}

variable "mgmt_cidrs_v4" {
  description = "IPv4 CIDR allow-list for SSH / metrics scrape (non-fabric ifaces only)"
  type        = list(string)
  default     = []
}

variable "mgmt_cidrs_v6" {
  description = "IPv6 CIDR allow-list for SSH / metrics scrape (non-fabric ifaces only)"
  type        = list(string)
  default     = []
}

variable "nack_port" {
  description = "UDP port for NACK receive (listeners dial this)"
  type        = number
  default     = 9300
}

variable "otlp_endpoint" {
  description = "OTLP gRPC endpoint for metric push (empty = disabled)"
  type        = string
  default     = ""
}

variable "otlp_interval" {
  description = "OTLP metric export interval (Go duration)"
  type        = string
  default     = "30s"
}

variable "redis_addr" {
  description = "Redis address (if cache_backend=redis)"
  type        = string
  default     = ""
}

variable "retry_repo" {
  description = "Git URL of the retry-endpoint repository"
  type        = string
  default     = "https://github.com/lightwebinc/retry-endpoint.git"
}

variable "retry_version" {
  description = "Git ref (branch, tag, or SHA) to check out; \"main\" for lab builds from tip"
  type        = string
  default     = "v1.5.0"
}

variable "rl_chain_rate" {
  description = "Max NACKs per window per (srcIP, chainID)"
  type        = number
  default     = 500
}

variable "rl_chain_window" {
  description = "Sliding window for per-chain NACK limiter (Go duration)"
  type        = string
  default     = "1m"
}

variable "rl_group_burst" {
  description = "Burst size per (srcIP, groupIdx)"
  type        = number
  default     = 50
}

variable "rl_group_rate" {
  description = "Retransmits per second per (srcIP, groupIdx)"
  type        = number
  default     = 200
}

variable "rl_ip_burst" {
  description = "Per-IP burst"
  type        = number
  default     = 100
}

variable "rl_ip_rate" {
  description = "Per-IP rate limit (tokens/sec)"
  type        = number
  default     = 1000
}

variable "rl_sequence_max" {
  description = "Max requests per LookupSeq per sliding window"
  type        = number
  default     = 100
}

variable "rl_sequence_window" {
  description = "Per-LookupSeq sliding window (Go duration)"
  type        = string
  default     = "1m"
}

variable "shard_bits" {
  description = "Shard bit width (1-24); must match fabric"
  type        = number
  default     = 2
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key file"
  type        = string
}

variable "ssh_user" {
  description = "SSH username for the target host"
  type        = string
  default     = "ubuntu"
}
