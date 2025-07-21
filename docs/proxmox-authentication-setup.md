# Proxmox Authentication Setup for Ansible

This guide covers setting up authentication between Ansible and Proxmox VE for automated VM management.

## 🎯 Overview

The Ansible playbooks in this project require API access to your Proxmox VE cluster to:

- Create and configure virtual machines
- Clone from Windows Server templates
- Manage VM lifecycle (start, stop, delete)
- Configure network and storage settings

## 🔐 Authentication Methods

### Method 1: API User with Password (Recommended for Development)

This method creates a dedicated Proxmox user for Ansible automation.

#### Step 1: Create Ansible User in Proxmox Web Interface

1. **Login to Proxmox Web Interface**

   ```text
   https://your-proxmox-host:8006
   ```

2. **Navigate to Datacenter → Permissions → Users**
   - Click **"Add"** button
   - Fill in user details:
     - **User name**: `ansible`
     - **Realm**: `pve` (Proxmox VE authentication server)
     - **Full Name**: `Ansible Automation User`
     - **Email**: `ansible@yourcompany.com` (optional)
     - **Password**: Use a strong password (minimum 8 characters)
   - Click **"Add"**

3. **Create Role for Ansible (if needed)**
   - Navigate to **Datacenter → Permissions → Roles**
   - Click **"Create"** if you want a custom role
   - **Role ID**: `AnsibleAutomation`
   - **Privileges**: Select the following permissions:

     ```text
     VM.Allocate       # Create new VMs
     VM.Clone          # Clone templates
     VM.Config.CDROM   # CD-ROM configuration
     VM.Config.CPU     # CPU configuration  
     VM.Config.Disk    # Disk configuration
     VM.Config.HWType  # Hardware configuration
     VM.Config.Memory  # Memory configuration
     VM.Config.Network # Network configuration
     VM.Config.Options # VM options
     VM.Console        # Console access
     VM.Migrate        # VM migration
     VM.Monitor        # VM monitoring
     VM.PowerMgmt      # Power management
     Datastore.Allocate # Storage allocation
     ```

4. **Assign Permissions**
   - Navigate to **Datacenter → Permissions**
   - Click **"Add" → "User Permission"**
   - **Path**: `/` (root path for full access) or specific paths like `/nodes/proxmox-01`
   - **User**: `ansible@pve`
   - **Role**: `Administrator` (easiest) or `AnsibleAutomation` (if you created custom role)
   - **Propagate**: ✅ Checked
   - Click **"Add"**

#### Step 2: Configure Ansible Inventory

Update your inventory file with the user credentials:

```yaml
all:
  vars:
    proxmox_api_url: "https://your-proxmox-host:8006/api2/json"
    proxmox_user: "ansible@pve"
    proxmox_password: "{{ vault_proxmox_password }}"
    proxmox_node: "your-node-name"
    proxmox_tls_insecure: true  # Use false for production with valid SSL
```

#### Step 3: Store Password in Ansible Vault

1. **Edit vault file**:

   ```bash
   ansible-vault edit ansible/group_vars/vault.yml --vault-password-file ansible/vault_pass
   ```

2. **Add the password**:

   ```yaml
   ---
   # Proxmox API password for ansible@pve user
   vault_proxmox_password: "your-secure-password-here"
   
   # Other vault variables...
   vault_admin_password: "your-windows-admin-password"
   vault_dsrm_password: "your-dsrm-password"
   ```

### Method 2: API Token (Recommended for Production)

API tokens provide more secure, granular access control.

#### Step 1: Create API Token

1. **Navigate to Datacenter → Permissions → API Tokens**
2. **Click "Add"**
3. **Configure Token**:
   - **User**: `ansible@pve` (must exist - create user first using Method 1 steps 1-4)
   - **Token ID**: `automation`
   - **Privilege Separation**: ✅ Checked (recommended)
   - **Comment**: `Ansible automation token`
4. **Copy the token value** (displayed only once)

#### Step 2: Configure Role for Token (if using Privilege Separation)

1. **Navigate to Datacenter → Permissions**
2. **Click "Add" → "API Token Permission"**
3. **Configure Permission**:
   - **Path**: `/`
   - **API Token**: `ansible@pve!automation`
   - **Role**: `Administrator` or custom role
   - **Propagate**: ✅ Checked

#### Step 3: Update Ansible Configuration

For API tokens, modify your configuration:

```yaml
all:
  vars:
    proxmox_api_url: "https://your-proxmox-host:8006/api2/json"
    proxmox_user: "ansible@pve!automation"  # Note the !token-id format
    proxmox_password: "{{ vault_proxmox_token }}"
    proxmox_node: "your-node-name"
```

And in your vault:

```yaml
---
vault_proxmox_token: "your-api-token-here"
```

## 🛠️ Using Proxmox CLI (Alternative)

You can also create users via SSH/console:

```bash
# Create user
pveum user add ansible@pve --password "secure-password" --firstname "Ansible" --lastname "Automation"

# Create role (optional - can use built-in Administrator)
pveum role add AnsibleAutomation -privs "VM.Allocate,VM.Clone,VM.Config.CDROM,VM.Config.CPU,VM.Config.Disk,VM.Config.HWType,VM.Config.Memory,VM.Config.Network,VM.Config.Options,VM.Console,VM.Migrate,VM.Monitor,VM.PowerMgmt,Datastore.Allocate"

# Assign permissions
pveum aclmod / -user ansible@pve -role Administrator

# Create API token (optional)
pveum user token add ansible@pve automation --privsep 1
```

## 🔧 Testing Authentication

### Test 1: Direct API Call

```bash
# Test with password authentication
curl -k -d "username=ansible@pve&password=your-password" https://your-proxmox-host:8006/api2/json/access/ticket

# Test with API token
curl -k -H "Authorization: PVEAPIToken=ansible@pve!automation=your-token" https://your-proxmox-host:8006/api2/json/version
```

### Test 2: Ansible Connectivity

```bash
# Test Ansible can connect to Proxmox
ansible-playbook ansible/site.yml --tags validate --check
```

### Test 3: VM Operations Test

```bash
# Test VM creation (dry run)
ansible-playbook ansible/site.yml --tags provision --check
```

## 🔒 Security Best Practices

### Password Authentication

1. **Use Strong Passwords**: Minimum 12 characters with mixed case, numbers, symbols
2. **Limit Scope**: Create specific roles instead of using Administrator
3. **Rotate Regularly**: Change passwords quarterly
4. **Audit Access**: Review Proxmox logs regularly

### API Token Authentication

1. **Enable Privilege Separation**: Always use `--privsep 1`
2. **Least Privilege**: Grant only required permissions
3. **Token Rotation**: Regenerate tokens annually
4. **Secure Storage**: Store tokens in Ansible Vault only

### Network Security

1. **TLS/SSL**: Use valid certificates in production (`proxmox_tls_insecure: false`)
2. **Firewall**: Restrict API access to specific source IPs
3. **VPN**: Access Proxmox through VPN when possible
4. **Monitoring**: Enable API access logging

## 🚨 Troubleshooting

### Common Issues

#### Authentication Failed

```text
TASK [Create Windows Domain Controller VMs] ***
fatal: [localhost]: FAILED! => {"msg": "authentication failed"}
```

**Solutions:**

1. Verify username format: `ansible@pve` (not just `ansible`)
2. Check password in vault file
3. Ensure user has required permissions
4. Test API access directly with curl

#### Permission Denied

```text
TASK [Create Windows Domain Controller VMs] ***
fatal: [localhost]: FAILED! => {"msg": "403 Forbidden"}
```

**Solutions:**

1. Check user permissions in Proxmox web interface
2. Verify path permissions (should be `/` with propagate)
3. Ensure role has VM creation privileges
4. For API tokens, check privilege separation settings

#### SSL Certificate Issues

```text
fatal: [localhost]: FAILED! => {"msg": "certificate verify failed"}
```

**Solutions:**

1. Set `proxmox_tls_insecure: true` for development
2. Install proper SSL certificate on Proxmox
3. Use `proxmox_tls_insecure: false` with valid certificates

#### Connection Timeout

```text
fatal: [localhost]: FAILED! => {"msg": "timeout"}
```

**Solutions:**

1. Check network connectivity to Proxmox host
2. Verify firewall allows port 8006
3. Confirm Proxmox API is running: `systemctl status pveproxy`

### Debug Commands

```bash
# Check Proxmox API status
systemctl status pveproxy

# View API logs
tail -f /var/log/pveproxy/access.log

# Test network connectivity
curl -k https://your-proxmox-host:8006/api2/json/version

# Verify user permissions
pveum user list
pveum aclmod / -user ansible@pve
```

## 📚 References

- [Proxmox VE API Documentation](https://pve.proxmox.com/pve-docs/api-viewer/)
- [Proxmox User Management](https://pve.proxmox.com/wiki/User_Management)
- [Ansible community.proxmox.proxmox_kvm module](https://docs.ansible.com/ansible/latest/collections/community/proxmox/proxmox_kvm_module.html)

## 📢 Recent Updates

**Module Migration (2024):** The `proxmox_kvm` module has been moved from `community.general` to `community.proxmox` collection. This project has been updated to use the new collection. If you encounter module not found errors, ensure you have the latest version of this repository and run `./setup-ansible.sh` to install the correct collections.

## 🔄 What's Next?

After setting up authentication:

1. **Configure Inventory**: Update `ansible/inventory.yml` with your Proxmox details
2. **Test Connection**: Run `ansible-playbook ansible/site.yml --tags validate --check`
3. **Deploy**: Execute `./deploy.sh` to create your Windows domain controllers

---

✅ **Success Indicator**: You should be able to run Ansible playbooks that create, configure, and manage VMs on your Proxmox cluster without authentication errors.

## 🔧 Template Resource Inheritance

When cloning VMs from a Proxmox template, you have two approaches for resource configuration:

### Approach 1: Inherit Template Resources (Recommended)

This approach uses the template's exact configuration, which is more efficient and maintains consistency with your template preparation:

```yaml
# Comment out or remove these variables to inherit from template:
# dc_cpu_cores: 4
# dc_cpu_sockets: 1  
# dc_memory_mb: 8192
# dc_cpu_type: "x86-64-v2-AES"
# dc_machine_type: "pc-q35-9.2+pve1"
# dc_bios_type: "ovmf"
```

**Benefits:**
- Faster cloning (no resource reconfiguration)
- Consistent with template preparation
- Template changes automatically propagate
- Simpler configuration management

### Approach 2: Override Template Resources (Current Default)

This approach standardizes all VMs to specific resource levels regardless of template configuration:

```yaml
# Specify custom resources (current approach):
dc_cpu_cores: 4
dc_cpu_sockets: 1
dc_memory_mb: 8192
dc_cpu_type: "x86-64-v2-AES"
dc_machine_type: "pc-q35-9.2+pve1"  
dc_bios_type: "ovmf"
```

**Benefits:**
- Guaranteed consistent sizing across deployments
- Easy to modify resources for different environments
- Override template if it doesn't match requirements
- Standardization across multiple templates

### What's Always Inherited vs. Configurable

**Always Inherited from Template:**
- Storage configuration (disk images, sizes)
- Network interface types (virtio, e1000, etc.)
- Hardware features (TPM, EFI disk, etc.)
- Installed software and OS configuration

**Can Be Overridden:**
- CPU cores and sockets
- Memory allocation
- CPU and machine types
- BIOS type (UEFI vs. Legacy)
- Network configuration (IP, bridge, etc.)

Choose the approach that best fits your deployment strategy!
