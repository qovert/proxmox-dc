# Module Variables for Windows DC

# Basic Configuration
variable "dc_index" {
  description = "Index of the domain controller (0 for primary, 1+ for additional)"
  type        = number
}

variable "name_prefix" {
  description = "Prefix for domain controller name"
  type        = string
  default     = "dc"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "development"
}

# Proxmox Configuration
variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "template_name" {
  description = "Name of the Windows Server 2025 template"
  type        = string
}

variable "template_vm_id" {
  description = "VM ID of the Windows Server 2025 template"
  type        = number
}

variable "vmid_start" {
  description = "Starting VM ID for domain controllers"
  type        = number
  default     = 200
}

variable "storage_pool" {
  description = "Proxmox storage pool"
  type        = string
}

# VM Resources
variable "cpu_cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 4
}

variable "cpu_sockets" {
  description = "Number of CPU sockets"
  type        = number
  default     = 1
}

variable "memory_mb" {
  description = "Memory in MB"
  type        = number
  default     = 8192
}

variable "os_disk_size" {
  description = "OS disk size"
  type        = string
  default     = "80G"
}

variable "data_disk_size" {
  description = "Data disk size"
  type        = string
  default     = "40G"
}

# Network Configuration
variable "network_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "ip_prefix" {
  description = "IP prefix for domain controllers"
  type        = string
}

variable "ip_start" {
  description = "Starting IP address last octet"
  type        = number
  default     = 10
}

variable "network_cidr_bits" {
  description = "Network CIDR bits"
  type        = number
  default     = 24
}

variable "gateway_ip" {
  description = "Gateway IP address"
  type        = string
}

variable "dns_servers" {
  description = "DNS servers for initial configuration"
  type        = string
  default     = "1.1.1.1 8.8.8.8"
}

variable "dns_forwarders" {
  description = "DNS forwarders for AD DNS"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "enable_firewall" {
  description = "Enable VM firewall"
  type        = bool
  default     = true
}

# Active Directory Configuration
variable "domain_name" {
  description = "Active Directory domain name"
  type        = string
}

variable "primary_dc_ip" {
  description = "IP address of the primary domain controller"
  type        = string
}

# Authentication Configuration
variable "admin_username" {
  description = "Local administrator username"
  type        = string
  default     = "Administrator"
}

variable "admin_password" {
  description = "Local administrator password"
  type        = string
  sensitive   = true
}

variable "dsrm_password" {
  description = "Directory Services Restore Mode password"
  type        = string
  sensitive   = true
}

# SSH Configuration
variable "ssh_private_key_path" {
  description = "Path to SSH private key file"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  sensitive   = true
}

# Scripts Configuration
variable "scripts_path" {
  description = "Path to PowerShell scripts directory"
  type        = string
  default     = "scripts/"
}
