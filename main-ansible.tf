# Windows Server 2025 Active Directory Domain Controller on Proxmox
# This configuration deploys Windows Server 2025 VMs configured as Active Directory Domain Controllers
# Configuration is handled by Ansible for better maintainability

terraform {
  required_version = ">= 1.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

# Configure the Proxmox Provider
provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_user}=${var.proxmox_token}"
  insecure  = var.proxmox_tls_insecure
}

# Local values for IP calculations and common settings
locals {
  dc_ips = [for i in range(var.dc_count) : "${var.dc_ip_prefix}.${var.dc_ip_start + i}"]
  
  common_tags = {
    Environment = var.environment
    Project     = "ProxmoxAD"
    Terraform   = "true"
    Domain      = var.domain_name
  }
}

# Data source to get available Proxmox nodes
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
resource "proxmox_virtual_environment_vm" "windows_dc" {
  count = var.dc_count
  
  depends_on = [null_resource.validate_template]
  
  # VM Identity
  name        = "${var.dc_name_prefix}-${format("%02d", count.index + 1)}"
  node_name   = var.proxmox_node
  vm_id       = var.dc_vmid_start + count.index
  description = "Windows Server 2025 Active Directory Domain Controller ${count.index + 1}"
  
  # Clone from template
  clone {
    vm_id = var.windows_template_vm_id
    full  = true
  }
  
  # VM Configuration
  agent {
    enabled = true
  }
  
  # BIOS configuration - using SeaBIOS (legacy) to match common templates
  bios = "seabios"
  
  # Boot order
  boot_order = ["scsi0"]
  
  started = true
  on_boot = true
  
  # VM Resources
  cpu {
    cores   = var.dc_cpu_cores
    sockets = var.dc_cpu_sockets
    type    = "host"  # Better performance and compatibility
  }
  
  memory {
    dedicated = var.dc_memory_mb
  }
  
  # Network Configuration
  network_device {
    bridge      = var.network_bridge
    enabled     = true
    firewall    = var.enable_firewall
    model       = "virtio"
  }
  
  # Primary Disk (OS) - inherited from clone, don't resize to avoid boot issues
  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"
    iothread     = true
    ssd          = true
    cache        = "writeback"
    # Note: size omitted to inherit from template and avoid boot issues
  }
  
  # Data Disk (for AD database and logs)
  disk {
    datastore_id = var.storage_pool
    interface    = "scsi1"
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

# Generate Ansible inventory from Terraform outputs
resource "local_file" "ansible_inventory" {
  depends_on = [proxmox_virtual_environment_vm.windows_dc]
  
  content = templatefile("${path.module}/templates/inventory.yml.tpl", {
    domain_controllers = [
      for i, dc in proxmox_virtual_environment_vm.windows_dc : {
        name       = dc.name
        ip_address = local.dc_ips[i]
        vm_id      = dc.vm_id
        is_primary = i == 0
      }
    ]
    domain_name = var.domain_name
    admin_user  = var.admin_username
  })
  filename = "${path.module}/ansible/inventory.yml"
}

# Create group_vars directory
resource "local_file" "ansible_group_vars_dir" {
  content  = ""
  filename = "${path.module}/ansible/group_vars/.gitkeep"
}

# Generate Ansible variables
resource "local_file" "ansible_vars" {
  depends_on = [local_file.ansible_group_vars_dir]
  
  content = templatefile("${path.module}/templates/group_vars.yml.tpl", {
    domain_name              = var.domain_name
    netbios_name            = var.netbios_name
    admin_username          = var.admin_username
    admin_password          = var.admin_password
    dsrm_password           = var.dsrm_password
    domain_functional_level = var.domain_functional_level
    forest_functional_level = var.forest_functional_level
    gateway_ip              = var.gateway_ip
    network_cidr_bits       = var.network_cidr_bits
    dns_servers             = var.dns_servers
    dns_forwarders          = var.dns_forwarders
    organizational_units    = var.organizational_units
    password_policy         = var.password_policy
    enable_recycle_bin      = var.enable_recycle_bin
    enable_backup           = var.enable_backup
    enable_monitoring       = var.enable_monitoring
  })
  filename = "${path.module}/ansible/group_vars/domain_controllers.yml"
}

# Create Ansible vault password file
resource "local_file" "ansible_vault_pass" {
  content  = "changeme"  # Change this to a secure password
  filename = "${path.module}/ansible/vault_pass"
  
  provisioner "local-exec" {
    command = "chmod 600 ${self.filename}"
  }
}

# Wait for VMs to be ready for SSH
resource "null_resource" "wait_for_ssh" {
  count = var.dc_count
  
  depends_on = [proxmox_virtual_environment_vm.windows_dc]
  
  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for SSH connectivity to ${local.dc_ips[count.index]}"
      timeout 300 bash -c 'until nc -z ${local.dc_ips[count.index]} 22; do sleep 5; done'
      echo "SSH is ready on ${local.dc_ips[count.index]}"
    EOT
  }
}

# Run Ansible after infrastructure is ready
resource "null_resource" "run_ansible" {
  depends_on = [
    proxmox_virtual_environment_vm.windows_dc,
    local_file.ansible_inventory,
    local_file.ansible_vars,
    local_file.ansible_vault_pass,
    null_resource.wait_for_ssh
  ]

  triggers = {
    inventory_hash = local_file.ansible_inventory.content_md5
    vars_hash     = local_file.ansible_vars.content_md5
    vm_ids        = join(",", [for dc in proxmox_virtual_environment_vm.windows_dc : dc.vm_id])
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Running Ansible configuration..."
      cd ${path.module}/ansible
      ansible-playbook -i inventory.yml site.yml --vault-password-file vault_pass
    EOT
  }
}
