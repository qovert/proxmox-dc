# Windows Domain Controller Module
# This module creates a Windows Server 2025 Domain Controller on Proxmox

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
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
resource "proxmox_virtual_environment_vm" "dc" {
  # VM Identity
  name        = local.dc_name
  node_name   = var.proxmox_node
  vm_id       = var.vmid_start + var.dc_index
  description = "Windows Server 2025 Active Directory Domain Controller - ${var.dc_index == 0 ? "Primary" : "Additional"}"
  
  # Clone from template
  clone {
    vm_id        = var.template_vm_id
    full         = true
    datastore_id = var.storage_pool
  }
  
  # VM Configuration
  agent {
    enabled = true
  }
  
  # BIOS configuration - using OVMF (UEFI) to match template
  bios = "ovmf"
  
  # Machine type to match template
  machine = "q35"
  
  # SCSI hardware to match template
  scsi_hardware = "virtio-scsi-single"
  
  # OS type to match template
  operating_system {
    type = "win11"
  }
  
  # Boot order - using virtio0 to match template
  boot_order = ["virtio0"]
  
  started = true
  on_boot = true
  
  # VM Resources
  cpu {
    cores   = var.cpu_cores
    sockets = var.cpu_sockets
    type    = "x86-64-v2-AES"  # Match template CPU type
  }
  
  memory {
    dedicated = var.memory_mb
  }
  
  # TPM 2.0 to match template
  tpm_state {
    datastore_id = var.storage_pool
    version      = "v2.0"
  }
  
  # EFI Disk to match template UEFI boot
  efi_disk {
    datastore_id      = var.storage_pool
    file_format       = "raw"
    type              = "4m"
    pre_enrolled_keys = true
  }
  
  # Network Configuration
  network_device {
    bridge      = var.network_bridge
    enabled     = true
    firewall    = var.enable_firewall
    model       = "virtio"
  }
  
  # Primary Disk (OS) - inherited from clone, using virtio to match template
  disk {
    datastore_id = var.storage_pool
    interface    = "virtio0"
    iothread     = true
    ssd          = true
    cache        = "writeback"
    size         = parseint(replace(var.os_disk_size, "G", ""), 10)
  }
  
  # Data Disk (for AD database and logs)
  disk {
    datastore_id = var.storage_pool
    interface    = "virtio1"
    iothread     = true
    ssd          = true
    cache        = "writeback"
    size         = parseint(replace(var.data_disk_size, "G", ""), 10)
  }
  
  # Cloud-init configuration
  initialization {
    datastore_id = var.storage_pool
    
    ip_config {
      ipv4 {
        address = "${local.dc_ip}/${var.network_cidr_bits}"
        gateway = var.gateway_ip
      }
    }
    
    dns {
      servers = split(" ", var.dns_servers)
    }
    
    user_account {
      username = var.admin_username
      password = var.admin_password
      keys     = [var.ssh_public_keys]
    }
  }
  
  # Lifecycle management
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = false  # Set to true in production
  }
}

# Wait for VM to be ready
resource "null_resource" "wait_for_vm" {
  depends_on = [proxmox_virtual_environment_vm.dc]
  
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
