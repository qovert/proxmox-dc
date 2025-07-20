# Usage Guide

This guide covers how to deploy and manage Windows Server 2025 Active Directory Domain Controllers using this Ansible-based automation.

## Prerequisites

### Proxmox Environment

- Proxmox VE cluster with sufficient resources
- Windows Server 2025 template properly configured (see [Template Preparation Guide](template-preparation.md))
- Storage pool with adequate space (120GB+ per DC)
- Network bridge configured for domain controllers

### Ansible Setup

- Ansible >= 2.9 with required collections
- SSH access to Proxmox API
- Network connectivity to Proxmox hosts

### Network Requirements

- Dedicated network segment for domain controllers
- Static IP addresses reserved for DCs
- DNS forwarders configured
- Firewall rules for AD traffic

## Quick Start

### 1. Prepare Environment

```bash
# Clone the repository
git clone https://github.com/qovert/proxmox-dc.git
cd proxmox-dc

# Set up Ansible environment
./setup-ansible.sh
```

### 2. Generate SSH Key Pair

```bash
# Generate SSH key pair for the project
ssh-keygen -t ed25519 -f ~/.ssh/proxmox-ad -C "proxmox-ad-deployment"

# Add to SSH agent
ssh-add ~/.ssh/proxmox-ad

# Copy public key content for configuration
cat ~/.ssh/proxmox-ad.pub
```

### 3. Configure Variables

```bash
# Edit main configuration
nano ansible/group_vars/all.yml

# Edit sensitive variables
nano ansible/group_vars/vault.yml

# Encrypt the vault file
ansible-vault encrypt ansible/group_vars/vault.yml
```

### 4. Deploy Infrastructure

```bash
# Full deployment (provision VMs + configure AD)
./deploy.sh

# Or step-by-step:
./deploy.sh provision   # Just create VMs
./deploy.sh configure   # Just configure AD
./deploy.sh validate    # Validate deployment
```

### 5. Cleanup (if needed)

```bash
# Remove all VMs and resources
./deploy.sh cleanup
```

## Configuration Options

### Domain Controller Settings

- `dc_count`: Number of domain controllers to deploy (default: 2)
- `dc_cpu_cores`: CPU cores per DC (default: 4)
- `dc_memory_mb`: Memory in MB per DC (default: 8192)
- `os_disk_size`: OS disk size (default: "80G")
- `data_disk_size`: Data disk size for AD database (default: "40G")

### Active Directory Settings

- `domain_name`: AD domain name (e.g., "testdomain.local")
- `netbios_name`: NetBIOS domain name (e.g., "TESTDOMAIN")
- `domain_functional_level`: Domain functional level (default: "WinThreshold")
- `forest_functional_level`: Forest functional level (default: "WinThreshold")

### Network Configuration

- `dc_ip_prefix`: IP prefix for DCs (e.g., "192.168.1")
- `dc_ip_start`: Starting IP last octet (default: 10)
- `gateway_ip`: Network gateway IP
- `dns_forwarders`: External DNS forwarders

### Security Settings

- `password_policy`: Fine-grained password policy settings
- `enable_recycle_bin`: Enable AD Recycle Bin (default: true)
- `organizational_units`: Custom OU structure

## Post-Deployment Configuration

The deployment includes comprehensive PowerShell scripts that handle:

### Initial Setup (`initial-setup.ps1`)

- System configuration and hardening
- Network adapter configuration
- Windows Firewall rules for AD
- Service configuration
- Performance optimization

### AD DS Installation (`configure-adds.ps1`)

- Primary DC forest installation
- Additional DC promotion
- DNS configuration
- Replication setup
- Security policies

### Post-Configuration (`post-config.ps1`)

- Sites and Services configuration
- Group Policy Central Store
- Password policies
- AD Recycle Bin
- Backup configuration
- Monitoring setup

### DNS Configuration (`configure-dns.ps1`)

- DNS forwarders
- Zone configuration
- Scavenging settings
- Conditional forwarders
- Health monitoring

### Health Monitoring (`health-check.ps1`)

- Service status checks
- AD replication monitoring
- DNS functionality tests
- System resource monitoring
- Event log analysis
- Automated reporting

## Monitoring and Maintenance

### Automated Health Checks

- Daily health check reports (HTML and CSV)
- Event log monitoring
- Service status verification
- Resource utilization tracking

### Backup Strategy

- Daily system state backups
- AD database backups
- Log file retention
- Automated cleanup

### Scheduled Tasks

- AD health monitoring (every 15 minutes)
- DNS health monitoring (every 30 minutes)
- Daily system state backup
- Weekly cleanup tasks

## Security Features

### Network Security

- Windows Firewall configured for AD services
- Secure LDAP configuration
- Kerberos optimization
- Network segmentation support

### AD Security

- Fine-grained password policies
- Account lockout policies
- Audit policy configuration
- Privileged account protection

### Operational Security

- SSH key-based authentication for secure remote access
- Encrypted SSH communications (industry standard)
- Secure backup storage
- Event log monitoring
- Automated alerting

## Troubleshooting

### Common Issues

1. **Template Issues**:
   - Ensure Windows Server 2025 template is properly sysprepped
   - Verify Proxmox guest agent is installed and running
   - Check OpenSSH Server configuration and key authentication

2. **Network Issues**:
   - Verify IP address ranges don't conflict
   - Check DNS resolution
   - Ensure firewall rules allow AD traffic and SSH (port 22)

3. **AD Installation Issues**:
   - Check domain name format
   - Verify DNS settings
   - Review PowerShell execution policy

### SSH Connection Testing

```bash
# Test SSH connection to a deployed DC
ssh -i ~/.ssh/proxmox-testAD Administrator@192.168.1.10

# Test SSH with verbose output for troubleshooting
ssh -i ~/.ssh/proxmox-testAD -v Administrator@192.168.1.10

# Copy files via SCP
scp -i ~/.ssh/proxmox-testAD local-script.ps1 Administrator@192.168.1.10:C:/Scripts/
```

### Logs and Diagnostics

- Ansible logs: Use `-v`, `-vv`, or `-vvv` flags for increasing verbosity
- PowerShell script logs: Check Windows Event Logs
- AD health reports: `C:\Scripts\Reports\`

### Useful Commands

```powershell
# Check AD services
Get-Service -Name NTDS, DNS, Netlogon, KDC

# Test AD replication
Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME

# Check DNS
Resolve-DnsName -Name yourdomain.local -Type A

# Run health check manually
PowerShell.exe -File C:\Scripts\health-check.ps1
```

## Customization

### Adding Custom OUs

Modify the `organizational_units` variable in `ansible/group_vars/all.yml`:

```yaml
organizational_units:
  - "Servers"
  - "Workstations" 
  - "Users"
  - "Groups"
  - "Service Accounts"
  - "Custom OU 1"
  - "Custom OU 2"
```

### Custom PowerShell Scripts

Add your scripts to the `scripts/` directory and reference them in the Ansible roles.

### Environment-Specific Settings

Create different variable files for different environments:

- `ansible/group_vars/development.yml`
- `ansible/group_vars/staging.yml`
- `ansible/group_vars/production.yml`

## Support

For issues and questions:

1. Check the troubleshooting section above
2. Review the logs with increased verbosity
3. Open an issue in the repository
4. Provide full error messages and environment details
