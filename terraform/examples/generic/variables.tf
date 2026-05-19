variable "enable_firewall" {
  description = "Enable perimeter firewall (default on)"
  type        = bool
  default     = true
}

variable "gre_remote_ip6" {
  description = "Remote IPv6 endpoint for ip6gre tunnel (ingress_mode=gre, shared across hosts)"
  type        = string
  default     = ""
}

variable "hosts" {
  description = "List of target hosts. Per-host optional fields: gre_local_ip6, gre_inner_ipv6."
  type = list(object({
    name           = string
    public_ip      = string
    ssh_user       = string
    ssh_key        = string
    gre_local_ip6  = optional(string, "")
    gre_inner_ipv6 = optional(string, "")
  }))
}

variable "ingress_iface" {
  description = "Multicast ingress interface name"
  type        = string
  default     = "eth0"
}

variable "ingress_mode" {
  description = "Ingress interface mode: ethernet or gre"
  type        = string
  default     = "ethernet"
}

variable "mc_route_prefix" {
  description = "IPv6 multicast route prefix (empty = auto-derive from mc_scope)"
  type        = string
  default     = ""
}

variable "mgmt_cidrs_v4" {
  description = "IPv4 CIDR allow-list for SSH / metrics"
  type        = list(string)
  default     = []
}

variable "mgmt_cidrs_v6" {
  description = "IPv6 CIDR allow-list for SSH / metrics"
  type        = list(string)
  default     = []
}

variable "shard_bits" {
  description = "Shard bit width (1-24); must match fabric"
  type        = number
  default     = 2
}
