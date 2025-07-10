# Proxmox Configuration Variables
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
  default     = "https://proxmox.example.com:8006/api2/json"
}

variable "proxmox_user" {
  description = "Proxmox username"
  type        = string
  default     = "terraform@pve"
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Disable TLS verification"
  type        = bool
  default     = true
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "proxmox-01"
}

# Windows Template Configuration
variable "windows_template_name" {
  description = "Name of the Windows Server 2025 template"
  type        = string
  default     = "windows-server-2025-template"
}

# Domain Controller Configuration
variable "dc_count" {
  description = "Number of domain controllers to deploy"
  type        = number
  default     = 2
  validation {
    condition     = var.dc_count >= 1 && var.dc_count <= 10
    error_message = "Domain controller count must be between 1 and 10."
  }
}

variable "dc_name_prefix" {
  description = "Prefix for domain controller names"
  type        = string
  default     = "dc"
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.dc_name_prefix))
    error_message = "DC name prefix must start with a letter and contain only letters, numbers, and hyphens."
  }
}

variable "dc_vmid_start" {
  description = "Starting VM ID for domain controllers"
  type        = number
  default     = 200
}

# VM Resource Configuration
variable "dc_cpu_cores" {
  description = "Number of CPU cores per DC"
  type        = number
  default     = 4
}

variable "dc_cpu_sockets" {
  description = "Number of CPU sockets per DC"
  type        = number
  default     = 1
}

variable "dc_memory_mb" {
  description = "Memory in MB per DC"
  type        = number
  default     = 8192
}

# Storage Configuration
variable "storage_pool" {
  description = "Proxmox storage pool"
  type        = string
  default     = "local-lvm"
}

variable "os_disk_size" {
  description = "OS disk size (e.g., 80G)"
  type        = string
  default     = "80G"
}

variable "data_disk_size" {
  description = "Data disk size for AD database (e.g., 40G)"
  type        = string
  default     = "40G"
}

# Network Configuration
variable "network_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "dc_ip_prefix" {
  description = "IP prefix for domain controllers (e.g., 192.168.1)"
  type        = string
  default     = "192.168.1"
}

variable "dc_ip_start" {
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
  default     = "192.168.1.1"
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
  default     = "testdomain.local"
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$", var.domain_name))
    error_message = "Domain name must be a valid FQDN."
  }
}

variable "netbios_name" {
  description = "NetBIOS domain name"
  type        = string
  default     = "TESTDOMAIN"
  validation {
    condition     = can(regex("^[A-Z0-9]{1,15}$", var.netbios_name))
    error_message = "NetBIOS name must be 1-15 characters, uppercase letters and numbers only."
  }
}

variable "domain_functional_level" {
  description = "Domain functional level"
  type        = string
  default     = "WinThreshold"
  validation {
    condition = contains([
      "Win2008",
      "Win2008R2",
      "Win2012",
      "Win2012R2",
      "WinThreshold"
    ], var.domain_functional_level)
    error_message = "Domain functional level must be a valid Windows version."
  }
}

variable "forest_functional_level" {
  description = "Forest functional level"
  type        = string
  default     = "WinThreshold"
  validation {
    condition = contains([
      "Win2008",
      "Win2008R2",
      "Win2012",
      "Win2012R2",
      "WinThreshold"
    ], var.forest_functional_level)
    error_message = "Forest functional level must be a valid Windows version."
  }
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

# Environment Configuration
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "development"
  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "prevent_destroy" {
  description = "Prevent accidental destruction of resources"
  type        = bool
  default     = false
}

# Organizational Unit Configuration
variable "create_default_ous" {
  description = "Create default organizational units"
  type        = bool
  default     = true
}

variable "organizational_units" {
  description = "List of organizational units to create"
  type        = list(string)
  default = [
    "Servers",
    "Workstations",
    "Users",
    "Groups",
    "Service Accounts"
  ]
}

# Security Configuration
variable "enable_recycle_bin" {
  description = "Enable Active Directory Recycle Bin"
  type        = bool
  default     = true
}

variable "password_policy" {
  description = "Domain password policy settings"
  type = object({
    min_length              = number
    complexity_enabled      = bool
    max_password_age_days   = number
    min_password_age_days   = number
    password_history_count  = number
    lockout_threshold       = number
    lockout_duration_minutes = number
    lockout_reset_minutes   = number
  })
  default = {
    min_length              = 12
    complexity_enabled      = true
    max_password_age_days   = 90
    min_password_age_days   = 1
    password_history_count  = 24
    lockout_threshold       = 5
    lockout_duration_minutes = 30
    lockout_reset_minutes   = 30
  }
}

# Backup Configuration
variable "enable_backup" {
  description = "Enable automated backups"
  type        = bool
  default     = true
}

variable "backup_schedule" {
  description = "Backup schedule (cron format)"
  type        = string
  default     = "0 2 * * *"  # Daily at 2 AM
}

# Monitoring Configuration
variable "enable_monitoring" {
  description = "Enable performance monitoring"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Log retention period in days"
  type        = number
  default     = 30
}
