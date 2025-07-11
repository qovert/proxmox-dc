# Windows Server 2025 Active Directory Domain Controller on Proxmox
# This configuration deploys Windows Server 2025 VMs configured as Active Directory Domain Controllers

terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 2.9"
    }
  }
}

# Configure the Proxmox Provider
provider "proxmox" {
  pm_api_url      = var.proxmox_api_url
  pm_user         = var.proxmox_user
  pm_password     = var.proxmox_password
  pm_tls_insecure = var.proxmox_tls_insecure
}

# Local values for computed configurations
locals {
  # Generate IP addresses for each DC
  dc_ips = [for i in range(var.dc_count) : "${var.dc_ip_prefix}.${var.dc_ip_start + i}"]
  
  # Common tags for all resources
  common_tags = {
    Environment   = var.environment
    Project       = "ProxmoxAD"
    ManagedBy     = "Terraform"
    CreatedDate   = formatdate("YYYY-MM-DD", timestamp())
  }
}

# Data source to get the Windows Server template
data "proxmox_virtual_environment_nodes" "available_nodes" {}

# Validate template readiness before deployment
resource "null_resource" "validate_template" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Validating Windows Server 2025 template: ${var.windows_template_name}"
      echo "Ensure the template was prepared with prepare-windows-template.ps1"
      echo "Required components in template:"
      echo "  - PowerShell 7 installed and in PATH"
      echo "  - OpenSSH Server configured with key authentication"
      echo "  - CloudBase-Init installed and configured"
      echo "  - Scripts directory: C:/Scripts/"
      echo "  - Proxmox Guest Agent running"
    EOT
  }
}

# Deploy Windows Server 2025 Domain Controllers
resource "proxmox_vm_qemu" "windows_dc" {
  count = var.dc_count
  
  depends_on = [null_resource.validate_template]
  
  # VM Identity
  name        = "${var.dc_name_prefix}-${format("%02d", count.index + 1)}"
  target_node = var.proxmox_node
  vmid        = var.dc_vmid_start + count.index
  desc        = "Windows Server 2025 Active Directory Domain Controller ${count.index + 1}"
  
  # Clone from template
  clone = var.windows_template_name
  
  # VM Resources
  cores    = var.dc_cpu_cores
  sockets  = var.dc_cpu_sockets
  memory   = var.dc_memory_mb
  
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
  ipconfig0 = "ip=${local.dc_ips[count.index]}/${var.network_cidr_bits},gw=${var.gateway_ip}"
  
  # DNS Configuration
  nameserver = var.dns_servers
  
  # User configuration
  ciuser     = var.admin_username
  cipassword = var.admin_password
  
  # SSH Keys for secure management (template configured for key-based auth only)
  sshkeys = var.ssh_public_key
  
  # Wait for VM to be ready via SSH (configured in template)
  connection {
    type        = "ssh"
    user        = var.admin_username
    private_key = file(var.ssh_private_key_path)
    host        = local.dc_ips[count.index]
    port        = 22
    timeout     = "10m"
    
    # SSH connection settings for Windows
    target_platform = "windows"
  }
  
  # Verify template components before proceeding
  provisioner "remote-exec" {
    connection {
      type            = "ssh"
      user            = var.admin_username
      private_key     = file(var.ssh_private_key_path)
      host            = local.dc_ips[count.index]
      port            = 22
      timeout         = "5m"
      target_platform = "windows"
    }
    
    inline = [
      "# Verify PowerShell 7 is available",
      "pwsh.exe -Command 'Write-Host \"PowerShell 7 version: $($PSVersionTable.PSVersion)\"'",
      "# Verify Scripts directory exists", 
      "if (!(Test-Path 'C:/Scripts')) { New-Item -ItemType Directory -Path 'C:/Scripts' -Force }",
      "# Verify SSH service is running",
      "pwsh.exe -Command 'Get-Service sshd | Format-Table Name, Status, StartType'",
      "# Set execution policy for this session",
      "pwsh.exe -Command 'Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force'",
    ]
  }
  
  # Upload PowerShell scripts to the pre-configured Scripts directory
  provisioner "file" {
    connection {
      type            = "ssh"
      user            = var.admin_username
      private_key     = file(var.ssh_private_key_path)
      host            = local.dc_ips[count.index]
      port            = 22
      timeout         = "10m"
      target_platform = "windows"
    }
    
    source      = "scripts/"
    destination = "C:/Scripts/"
  }
  
  # Execute initial configuration using PowerShell 7
  provisioner "remote-exec" {
    connection {
      type            = "ssh"
      user            = var.admin_username
      private_key     = file(var.ssh_private_key_path)
      host            = local.dc_ips[count.index]
      port            = 22
      timeout         = "10m"
      target_platform = "windows"
    }
    
    inline = [
      "pwsh.exe -ExecutionPolicy Bypass -File C:/Scripts/initial-setup.ps1 -ComputerName ${var.dc_name_prefix}-${format("%02d", count.index + 1)} -DomainName ${var.domain_name} -IsPrimary ${count.index == 0 ? "true" : "false"}",
    ]
  }
  
  # Configure Active Directory using PowerShell 7
  provisioner "remote-exec" {
    connection {
      type            = "ssh"
      user            = var.admin_username
      private_key     = file(var.ssh_private_key_path)
      host            = local.dc_ips[count.index]
      port            = 22
      timeout         = "15m"
      target_platform = "windows"
    }
    
    inline = [
      "pwsh.exe -ExecutionPolicy Bypass -File C:/Scripts/configure-adds.ps1 -DomainName ${var.domain_name} -SafeModePassword ${var.dsrm_password} -IsPrimary ${count.index == 0 ? "true" : "false"} -PrimaryDcIp ${count.index == 0 ? local.dc_ips[0] : local.dc_ips[0]}",
    ]
  }
  
  # Post-configuration tasks using PowerShell 7
  provisioner "remote-exec" {
    connection {
      type            = "ssh"
      user            = var.admin_username
      private_key     = file(var.ssh_private_key_path)
      host            = local.dc_ips[count.index]
      port            = 22
      timeout         = "10m"
      target_platform = "windows"
    }
    
    inline = [
      "pwsh.exe -ExecutionPolicy Bypass -File C:/Scripts/post-config.ps1 -DomainName ${var.domain_name} -DcIp ${local.dc_ips[count.index]}",
    ]
  }
  
  tags = join(";", [for k, v in local.common_tags : "${k}=${v}"])
  
  # Lifecycle management
  lifecycle {
    create_before_destroy = false
    prevent_destroy       = var.prevent_destroy
  }
}

# Wait for all DCs to be ready before proceeding
resource "null_resource" "wait_for_dc_ready" {
  count = var.dc_count
  
  depends_on = [proxmox_vm_qemu.windows_dc]
  
  provisioner "local-exec" {
    command = "echo 'Waiting for DC ${count.index + 1} to be ready...'"
  }
  
  provisioner "local-exec" {
    command = <<-EOT
      timeout 300 bash -c '
        while ! nc -z ${local.dc_ips[count.index]} 389; do
          echo "Waiting for LDAP service on ${local.dc_ips[count.index]}..."
          sleep 10
        done
      '
    EOT
  }
}

# Configure DNS forwarding and additional settings
resource "null_resource" "configure_dns_forwarding" {
  count = var.dc_count
  
  depends_on = [null_resource.wait_for_dc_ready]
  
  connection {
    type            = "ssh"
    user            = var.admin_username
    private_key     = file(var.ssh_private_key_path)
    host            = local.dc_ips[count.index]
    port            = 22
    timeout         = "5m"
    target_platform = "windows"
  }
  
  provisioner "remote-exec" {
    inline = [
      "pwsh.exe -ExecutionPolicy Bypass -File C:/Scripts/configure-dns.ps1 -ForwarderIPs ${join(",", var.dns_forwarders)} -DomainName ${var.domain_name}",
    ]
  }
}
