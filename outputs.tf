# Domain Controller Information
output "dc_names" {
  description = "Names of the deployed domain controllers"
  value       = [for dc in proxmox_virtual_environment_vm.windows_dc : dc.name]
}

output "dc_ip_addresses" {
  description = "IP addresses of the domain controllers"
  value       = local.dc_ips
}

output "dc_vm_ids" {
  description = "VM IDs of the domain controllers"
  value       = [for dc in proxmox_virtual_environment_vm.windows_dc : dc.vm_id]
}

# Domain Information
output "domain_name" {
  description = "Active Directory domain name"
  value       = var.domain_name
}

output "netbios_name" {
  description = "NetBIOS domain name"
  value       = var.netbios_name
}

output "primary_dc_ip" {
  description = "IP address of the primary domain controller"
  value       = local.dc_ips[0]
}

output "primary_dc_name" {
  description = "Name of the primary domain controller"
  value       = proxmox_virtual_environment_vm.windows_dc[0].name
}

# Connection Information
output "winrm_connection_info" {
  description = "WinRM connection information for domain controllers"
  value = {
    for i, dc in proxmox_virtual_environment_vm.windows_dc : dc.name => {
      host     = local.dc_ips[i]
      port     = 5986
      username = var.admin_username
      https    = true
    }
  }
}

# DNS Configuration
output "dns_server_ips" {
  description = "DNS server IP addresses (domain controllers)"
  value       = local.dc_ips
}

output "dns_forwarders" {
  description = "Configured DNS forwarders"
  value       = var.dns_forwarders
}

# Network Configuration
output "network_info" {
  description = "Network configuration details"
  value = {
    gateway     = var.gateway_ip
    cidr_bits   = var.network_cidr_bits
    bridge      = var.network_bridge
    ip_range    = "${var.dc_ip_prefix}.${var.dc_ip_start} - ${var.dc_ip_prefix}.${var.dc_ip_start + var.dc_count - 1}"
  }
}

# Resource Information
output "vm_resources" {
  description = "VM resource allocation"
  value = {
    cpu_cores   = var.dc_cpu_cores
    cpu_sockets = var.dc_cpu_sockets
    memory_mb   = var.dc_memory_mb
    os_disk     = var.os_disk_size
    data_disk   = var.data_disk_size
  }
}

# Proxmox Information
output "proxmox_info" {
  description = "Proxmox deployment information"
  value = {
    node         = var.proxmox_node
    storage_pool = var.storage_pool
    template     = var.windows_template_name
  }
}

# Security Information (non-sensitive)
output "security_config" {
  description = "Security configuration details"
  value = {
    domain_functional_level = var.domain_functional_level
    forest_functional_level = var.forest_functional_level
    recycle_bin_enabled     = var.enable_recycle_bin
    password_policy = {
      min_length           = var.password_policy.min_length
      complexity_enabled   = var.password_policy.complexity_enabled
      max_password_age     = var.password_policy.max_password_age_days
      lockout_threshold    = var.password_policy.lockout_threshold
    }
  }
}

# Deployment Summary
output "deployment_summary" {
  description = "Summary of the deployment"
  value = {
    total_dcs     = var.dc_count
    environment   = var.environment
    domain_name   = var.domain_name
    primary_dc    = proxmox_virtual_environment_vm.windows_dc[0].name
    deployed_time = timestamp()
  }
}

# Management URLs and Commands
output "management_info" {
  description = "Management information and commands"
  value = {
    rdp_connections = [
      for i, dc in proxmox_virtual_environment_vm.windows_dc : 
      "mstsc /v:${local.dc_ips[i]}:3389"
    ]
    winrm_test_commands = [
      for i, dc in proxmox_virtual_environment_vm.windows_dc : 
      "winrs -r:https://${local.dc_ips[i]}:5986 -u:${var.admin_username} -ssl hostname"
    ]
    powershell_remote_commands = [
      for i, dc in proxmox_virtual_environment_vm.windows_dc : 
      "Enter-PSSession -ComputerName ${local.dc_ips[i]} -Credential (Get-Credential) -UseSSL"
    ]
  }
}

# Backup and Maintenance
output "maintenance_info" {
  description = "Backup and maintenance information"
  value = {
    backup_enabled  = var.enable_backup
    backup_schedule = var.backup_schedule
    log_retention   = var.log_retention_days
    monitoring      = var.enable_monitoring
  }
}
