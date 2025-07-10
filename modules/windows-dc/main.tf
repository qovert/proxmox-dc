# Windows Domain Controller Module
# This module creates a Windows Server 2025 Domain Controller on Proxmox

terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
  }
}

# Local values for the module
locals {
  dc_name = "${var.name_prefix}-${format("%02d", var.dc_index + 1)}"
  dc_ip   = "${var.ip_prefix}.${var.ip_start + var.dc_index}"
  
  common_tags = {
    Environment = var.environment
    DCRole      = var.dc_index == 0 ? "Primary" : "Additional"
    Project     = "ProxmoxAD"
    Module      = "windows-dc"
  }
}

# Deploy Windows Server 2025 Domain Controller
resource "proxmox_vm_qemu" "dc" {
  # VM Identity
  name        = local.dc_name
  target_node = var.proxmox_node
  vmid        = var.vmid_start + var.dc_index
  desc        = "Windows Server 2025 Active Directory Domain Controller - ${var.dc_index == 0 ? "Primary" : "Additional"}"
  
  # Clone from template
  clone = var.template_name
  
  # VM Resources
  cores    = var.cpu_cores
  sockets  = var.cpu_sockets
  memory   = var.memory_mb
  
  # VM Configuration
  agent    = 1
  os_type  = "win10"
  qemu_os  = "win10"
  onboot   = true
  startup  = "order=3,up=30"
  
  # Network Configuration
  network {
    model    = "virtio"
    bridge   = var.network_bridge
    firewall = var.enable_firewall
  }
  
  # Primary Disk (OS)
  disk {
    slot     = "scsi0"
    type     = "scsi"
    storage  = var.storage_pool
    size     = var.os_disk_size
    cache    = "writeback"
    iothread = 1
    ssd      = 1
  }
  
  # Data Disk (for AD database and logs)
  disk {
    slot     = "scsi1"
    type     = "scsi"
    storage  = var.storage_pool
    size     = var.data_disk_size
    cache    = "writeback"
    iothread = 1
    ssd      = 1
  }
  
  # Cloud-init configuration
  cloudinit_cdrom_storage = var.storage_pool
  
  # IP Configuration
  ipconfig0 = "ip=${local.dc_ip}/${var.network_cidr_bits},gw=${var.gateway_ip}"
  
  # DNS Configuration
  nameserver = var.dns_servers
  
  # User configuration
  ciuser     = var.admin_username
  cipassword = var.admin_password
  
  # SSH Keys (if needed for management)
  sshkeys = var.ssh_public_keys
  
  tags = join(";", [for k, v in local.common_tags : "${k}=${v}"])
  
  # Lifecycle management
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = var.prevent_destroy
  }
}

# Wait for VM to be ready
resource "null_resource" "wait_for_vm" {
  depends_on = [proxmox_vm_qemu.dc]
  
  connection {
    type        = "ssh"
    user        = var.admin_username
    private_key = file(var.ssh_private_key_path)
    host        = local.dc_ip
    port        = 22
    timeout     = "10m"
  }
  
  provisioner "remote-exec" {
    inline = [
      "echo 'VM is ready for configuration'",
    ]
  }
}

# Upload scripts to the VM
resource "null_resource" "upload_scripts" {
  depends_on = [null_resource.wait_for_vm]
  
  connection {
    type        = "ssh"
    user     = var.admin_username
    user        = var.admin_username
    private_key = file(var.ssh_private_key_path)
    host        = local.dc_ip
    port        = 22
    timeout     = "10m"
  }
  
  provisioner "file" {
    source      = var.scripts_path
    destination = "C:\\Scripts"
  }
}

# Execute initial setup
resource "null_resource" "initial_setup" {
  depends_on = [null_resource.upload_scripts]
  
  connection {
    type        = "ssh"
    user        = var.admin_username
    private_key = file(var.ssh_private_key_path)
    host        = local.dc_ip
    port        = 22
    timeout     = "15m"
  }
  
  provisioner "remote-exec" {
    inline = [
      "powershell.exe -ExecutionPolicy Bypass -File C:\\Scripts\\initial-setup.ps1 -ComputerName ${local.dc_name} -DomainName ${var.domain_name} -IsPrimary ${var.dc_index == 0 ? "true" : "false"}",
    ]
  }
}

# Configure Active Directory
resource "null_resource" "configure_ad" {
  depends_on = [null_resource.initial_setup]
  
  connection {
    type        = "ssh"
    user        = var.admin_username
    private_key = file(var.ssh_private_key_path)
    host        = local.dc_ip
    port        = 22
    timeout     = "20m"
  }
  
  provisioner "remote-exec" {
    inline = [
      "powershell.exe -ExecutionPolicy Bypass -File C:\\Scripts\\configure-adds.ps1 -DomainName ${var.domain_name} -SafeModePassword ${var.dsrm_password} -IsPrimary ${var.dc_index == 0 ? "true" : "false"} -PrimaryDcIp ${var.primary_dc_ip}",
    ]
  }
}

# Wait for reboot after AD installation
resource "null_resource" "wait_after_reboot" {
  depends_on = [null_resource.configure_ad]
  
  provisioner "local-exec" {
    command = "sleep 120"  # Wait 2 minutes for reboot
  }
  
  connection {
    type        = "ssh"
    user        = var.admin_username
    private_key = file(var.ssh_private_key_path)
    host        = local.dc_ip
    port        = 22
    timeout     = "10m"
  }
  
  provisioner "remote-exec" {
    inline = [
      "echo 'DC is ready after reboot'",
    ]
  }
}

# Post-configuration tasks
resource "null_resource" "post_config" {
  depends_on = [null_resource.wait_after_reboot]
  
  connection {
    type        = "ssh"
    user        = var.admin_username
    private_key = file(var.ssh_private_key_path)
    host        = local.dc_ip
    port        = 22
    timeout     = "15m"
  }
  
  provisioner "remote-exec" {
    inline = [
      "powershell.exe -ExecutionPolicy Bypass -File C:\\Scripts\\post-config.ps1 -DomainName ${var.domain_name} -DcIp ${local.dc_ip}",
    ]
  }
}

# Configure DNS
resource "null_resource" "configure_dns" {
  depends_on = [null_resource.post_config]
  
  connection {
    type        = "ssh"
    user        = var.admin_username
    private_key = file(var.ssh_private_key_path)
    host        = local.dc_ip
    port        = 22
    timeout     = "10m"
  }
  
  provisioner "remote-exec" {
    inline = [
      "powershell.exe -ExecutionPolicy Bypass -File C:\\Scripts\\configure-dns.ps1 -ForwarderIPs ${join(",", var.dns_forwarders)} -DomainName ${var.domain_name}",
    ]
  }
}
