# Minimal Windows VM Configuration for Initial Setup
# This creates the VMs without provisioning - manual setup required

terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

# Configure the Proxmox Provider
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_user}=${var.proxmox_token}"
  insecure  = var.proxmox_tls_insecure
}

# Data source to get available Proxmox nodes
data "proxmox_virtual_environment_nodes" "available_nodes" {}

# Local values for IP address generation
locals {
  dc_ips = [
    for i in range(var.dc_count) : "${var.dc_ip_prefix}.${var.dc_ip_start + i}"
  ]
}

# Deploy Windows Server 2025 Domain Controllers (Basic)
resource "proxmox_virtual_environment_vm" "windows_dc" {
  count = var.dc_count
  
  # VM Identity
  name        = "${var.dc_name_prefix}-${format("%02d", count.index + 1)}"
  node_name   = var.proxmox_node
  vm_id       = var.dc_vmid_start + count.index
  description = "Windows Server 2025 Active Directory Domain Controller ${count.index + 1}"
  
  # Clone from template
  clone {
    vm_id        = var.windows_template_vm_id
    full         = true
    datastore_id = var.storage_pool
  }
  
  # VM Configuration to match template exactly
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
    cores   = var.dc_cpu_cores
    sockets = var.dc_cpu_sockets
    type    = "x86-64-v2-AES"  # Match template CPU type
  }
  
  memory {
    dedicated = var.dc_memory_mb
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
        address = "${local.dc_ips[count.index]}/${var.network_cidr_bits}"
        gateway = var.gateway_ip
      }
    }
    
    dns {
      servers = split(" ", var.dns_servers)
    }
    
    user_account {
      username = var.admin_username
      password = var.admin_password
      keys     = [var.ssh_public_key]
    }
  }
  
  # Lifecycle management
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = false  # Set to true in production
  }
}
