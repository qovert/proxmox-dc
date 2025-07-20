# Ansible Inventory Configuration

This document explains how to configure the Ansible inventory for your Windows Server 2025 Active Directory deployment.

## Quick Start

1. **Copy the minimal example:**
   ```bash
   cp ansible/inventory-minimal.yml.example ansible/inventory.yml
   ```

2. **Edit the inventory file:**
   ```bash
   nano ansible/inventory.yml
   ```

3. **Update key settings:**
   - Change IP addresses to match your network
   - Update domain name and NetBIOS name
   - Set your Proxmox host details
   - Verify VM IDs don't conflict

## Inventory Files

### `inventory-minimal.yml.example`
- **Purpose**: Simplest possible configuration
- **Use case**: Quick testing, single-domain deployments
- **Features**: Basic 2-DC setup with minimal configuration

### `inventory.yml.example`
- **Purpose**: Complete production-ready configuration
- **Use case**: Full deployments with monitoring and multiple environments
- **Features**: 
  - Multiple environment support (dev/prod/lab)
  - Member server configuration
  - Advanced WinRM settings
  - Comprehensive variable definitions

## Key Configuration Sections

### 1. Domain Controllers (`windows_domain_controllers`)

```yaml
windows_domain_controllers:
  hosts:
    dc01:
      ansible_host: 192.168.1.10  # IP address of DC
      vm_id: 200                  # Unique VM ID in Proxmox
      dc_role: primary            # 'primary' or 'additional'
```

**Important Notes:**
- First DC should have `dc_role: primary`
- Additional DCs should have `dc_role: additional`  
- VM IDs must be unique across your Proxmox cluster
- IP addresses should be static and within your network range

### 2. Connection Settings

```yaml
vars:
  ansible_user: Administrator
  ansible_password: "{{ vault_admin_password }}"
  ansible_connection: winrm
  ansible_port: 5985
```

**Security Notes:**
- Always use vault variables for passwords
- Port 5985 is HTTP WinRM (use 5986 for HTTPS)
- `ansible_winrm_server_cert_validation: ignore` disables cert checks

### 3. Domain Configuration

```yaml
vars:
  domain_name: "corp.example.com"        # FQDN of your domain
  domain_netbios_name: "CORP"           # NetBIOS name (15 chars max)
  safe_mode_password: "{{ vault_dsrm_password }}"  # DSRM password
```

**Domain Naming Guidelines:**
- Use your organization's domain name
- NetBIOS name should be short and descriptive
- Avoid special characters in NetBIOS names

### 4. Proxmox Settings

```yaml
all:
  vars:
    proxmox_api_url: "https://proxmox.example.com:8006/api2/json"
    proxmox_user: "ansible@pve"
    proxmox_node: "proxmox-01"
    template_name: "windows-server-2025-template"
    template_id: 9000
```

**Configuration Notes:**
- Use HTTPS for Proxmox API URL
- User should have VM create/modify permissions
- Node name must match exactly
- Template must exist before deployment

## Network Planning

### IP Address Assignment

```yaml
# Example for 192.168.1.0/24 network
dc01: 192.168.1.10
dc02: 192.168.1.11
# Reserve .1-.9 for infrastructure
# Use .10+ for servers
```

### DNS Configuration

```yaml
dns_servers: 
  - "1.1.1.1"      # Public DNS for initial setup
  - "8.8.8.8"      # Backup public DNS
```

**During Deployment:**
1. Initial setup uses public DNS
2. After AD installation, DCs become DNS servers
3. Client machines point to DC IPs for DNS

## Environment-Specific Configurations

### Development Environment
```yaml
dev:
  children:
    windows_domain_controllers:
  vars:
    domain_name: "dev.corp.local"
    cpu_cores: 2
    memory_mb: 4096
    enable_monitoring: false
```

### Production Environment
```yaml
prod:
  children:
    windows_domain_controllers:
  vars:
    domain_name: "corp.example.com"
    cpu_cores: 4
    memory_mb: 8192
    enable_monitoring: true
```

## Testing Your Inventory

### 1. Validate YAML syntax:
```bash
ansible-inventory --list --yaml -i ansible/inventory.yml
```

### 2. Test connectivity:
```bash
ansible windows_domain_controllers -i ansible/inventory.yml -m win_ping
```

### 3. Check variable resolution:
```bash
ansible-inventory --host dc01 -i ansible/inventory.yml
```

## Common Issues and Solutions

### Connection Problems
- **Issue**: `winrm or requests is not installed`
  - **Solution**: `pip3 install pywinrm requests-kerberos`

- **Issue**: `Connection timeout`
  - **Solution**: Check IP addresses and firewall settings

- **Issue**: `Authentication failure`
  - **Solution**: Verify vault passwords are correct

### Variable Problems
- **Issue**: `vault_admin_password is undefined`
  - **Solution**: Ensure vault.yml is encrypted and loaded

- **Issue**: `Template not found`
  - **Solution**: Verify template name and ID in Proxmox

### Deployment Issues
- **Issue**: `VM ID already exists`
  - **Solution**: Use unique VM IDs for each host

- **Issue**: `Insufficient resources`
  - **Solution**: Reduce CPU/memory or check Proxmox resources

## Best Practices

1. **Security:**
   - Always encrypt sensitive data with Ansible Vault
   - Use strong passwords for all accounts
   - Enable WinRM HTTPS in production

2. **Naming:**
   - Use consistent naming conventions
   - Include environment prefixes (dev-dc01, prod-dc01)
   - Document your naming scheme

3. **Resource Planning:**
   - Allocate adequate resources for domain controllers
   - Plan for growth and additional services
   - Monitor resource usage post-deployment

4. **Network Design:**
   - Use static IP addresses for domain controllers
   - Plan subnet allocation carefully
   - Document IP address assignments

## Additional Resources

- [Ansible Windows Modules](https://docs.ansible.com/ansible/latest/collections/ansible/windows/)
- [Microsoft AD PowerShell](https://docs.microsoft.com/en-us/powershell/module/activedirectory/)
- [Proxmox VE API](https://pve.proxmox.com/pve-docs/api-viewer/)
