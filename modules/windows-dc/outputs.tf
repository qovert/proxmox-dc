# Module Outputs for Windows DC

output "vm_id" {
  description = "VM ID of the domain controller"
  value       = proxmox_vm_qemu.dc.vmid
}

output "vm_name" {
  description = "Name of the domain controller"
  value       = proxmox_vm_qemu.dc.name
}

output "ip_address" {
  description = "IP address of the domain controller"
  value       = local.dc_ip
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = "${proxmox_vm_qemu.dc.name}.${var.domain_name}"
}

output "dc_role" {
  description = "Role of the domain controller"
  value       = var.dc_index == 0 ? "Primary" : "Additional"
}

output "is_primary" {
  description = "Whether this is the primary domain controller"
  value       = var.dc_index == 0
}

output "winrm_connection" {
  description = "WinRM connection information"
  value = {
    host     = local.dc_ip
    port     = 5986
    username = var.admin_username
    https    = true
  }
}

output "vm_resources" {
  description = "VM resource allocation"
  value = {
    cpu_cores   = var.cpu_cores
    cpu_sockets = var.cpu_sockets
    memory_mb   = var.memory_mb
    os_disk     = var.os_disk_size
    data_disk   = var.data_disk_size
  }
}

output "network_config" {
  description = "Network configuration"
  value = {
    ip_address  = local.dc_ip
    gateway     = var.gateway_ip
    cidr_bits   = var.network_cidr_bits
    bridge      = var.network_bridge
  }
}

output "deployment_info" {
  description = "Deployment information"
  value = {
    proxmox_node  = var.proxmox_node
    template_name = var.template_name
    storage_pool  = var.storage_pool
    environment   = var.environment
    deployed_at   = timestamp()
  }
}
