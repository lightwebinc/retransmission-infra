terraform {
  required_version = ">= 1.9"
  required_providers {
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

locals {
  ansible_playbook = var.ansible_playbook_path != "" ? var.ansible_playbook_path : "${path.module}/../../../ansible/site.yml"
  inventory_path   = var.ansible_inventory_path != "" ? var.ansible_inventory_path : "${path.root}/generated-inventory-${replace(var.host_ip, ".", "-")}.yml"

  ansible_extra_vars = merge(
    {
      retry_repo    = var.retry_repo
      retry_version = var.retry_version

      # Retry-endpoint runtime
      mc_iface        = var.mc_iface
      listen_port     = tostring(var.listen_port)
      nack_port       = tostring(var.nack_port)
      egress_iface    = var.egress_iface
      egress_port     = tostring(var.egress_port)
      shard_bits      = tostring(var.shard_bits)
      mc_scope        = var.mc_scope
      mc_group_id     = var.mc_group_id
      mc_route_prefix = var.mc_route_prefix

      # Cache
      cache_backend  = var.cache_backend
      redis_addr     = var.redis_addr
      cache_ttl      = var.cache_ttl
      cache_max_keys = tostring(var.cache_max_keys)

      # Rate limiting
      rl_ip_rate         = tostring(var.rl_ip_rate)
      rl_ip_burst        = tostring(var.rl_ip_burst)
      rl_chain_rate      = tostring(var.rl_chain_rate)
      rl_chain_window    = var.rl_chain_window
      rl_group_rate      = tostring(var.rl_group_rate)
      rl_group_burst     = tostring(var.rl_group_burst)
      rl_sequence_max    = tostring(var.rl_sequence_max)
      rl_sequence_window = var.rl_sequence_window

      # Observability
      metrics_addr  = var.metrics_addr
      otlp_endpoint = var.otlp_endpoint
      otlp_interval = var.otlp_interval

      # Networking
      ingress_mode   = var.ingress_mode
      ingress_iface  = var.ingress_iface
      gre_local_ip6  = var.gre_local_ip6
      gre_remote_ip6 = var.gre_remote_ip6
      gre_inner_ipv6 = var.gre_inner_ipv6

      # Firewall
      enable_firewall = tostring(var.enable_firewall)
      mgmt_cidrs_v4   = var.mgmt_cidrs_v4
      mgmt_cidrs_v6   = var.mgmt_cidrs_v6
    },
    var.extra_ansible_vars
  )
}

# Generate a per-host Ansible inventory file
resource "local_file" "inventory" {
  filename        = local.inventory_path
  file_permission = "0600"
  content         = <<-INVENTORY
    all:
      children:
        retry_endpoint_nodes:
          hosts:
            ${var.host_ip}:
              ansible_host: ${var.host_ip}
              ansible_user: ${var.ssh_user}
              ansible_ssh_private_key_file: ${var.ssh_private_key_path}
              ansible_ssh_common_args: '-o StrictHostKeyChecking=accept-new'
  INVENTORY
}

# Run Ansible playbook against the target host
resource "null_resource" "provision" {
  triggers = {
    host_ip    = var.host_ip
    extra_vars = jsonencode(local.ansible_extra_vars)
  }

  depends_on = [local_file.inventory]

  provisioner "local-exec" {
    command = <<-EOT
      ansible-playbook \
        -i ${local.inventory_path} \
        ${local.ansible_playbook} \
        --extra-vars '${jsonencode(local.ansible_extra_vars)}'
    EOT
  }
}
