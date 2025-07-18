# Ansible Deployment Guide

This guide provides step-by-step instructions for deploying Windows Server 2025 Active Directory Domain Controllers on Proxmox using Ansible.

## Prerequisites Checklist

### Proxmox Environment

- [ ] Proxmox VE cluster is running and accessible
- [ ] Sufficient resources available:
  - CPU: 4+ cores per DC
  - RAM: 8GB+ per DC
  - Storage: 120GB+ per DC (80GB OS + 40GB data)
- [ ] Network segment configured for domain controllers
- [ ] Windows Server 2025 template created and tested

### Windows Server 2025 Template Requirements

- [ ] Windows Server 2025 installed and updated
- [ ] Proxmox guest agent installed and configured
- [ ] SSH server enabled and configured for key authentication
- [ ] PowerShell execution policy set to RemoteSigned
- [ ] Administrator account configured
- [ ] Template sysprepped and shut down

### Ansible Environment

- [ ] Ansible >= 2.9 installed
- [ ] Required collections installed:
  - community.general
  - community.windows
  - ansible.windows
  - microsoft.ad
- [ ] SSH key pair generated for deployment
- [ ] Network connectivity to Proxmox API

### Network Configuration

- [ ] Static IP range reserved for domain controllers
- [ ] DNS forwarders identified (e.g., 1.1.1.1, 8.8.8.8)
- [ ] Network gateway configured
- [ ] Firewall rules planned for AD traffic

## Step-by-Step Deployment

### Step 1: Prepare the Environment

1. **Clone the repository**:

   ```bash
   git clone https://github.com/qovert/proxmox-dc.git
   cd proxmox-dc
   ```

2. **Set up Ansible environment**:

   ```bash
   ./setup-ansible.sh
   ```

3. **Generate SSH key pair**:

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/proxmox-ad -C "proxmox-ad-deployment"
   ssh-add ~/.ssh/proxmox-ad
   cat ~/.ssh/proxmox-ad.pub  # Copy this for configuration
   ```

### Step 2: Configure Variables

1. **Edit main configuration**:

   ```bash
   nano ansible/group_vars/all.yml
   ```

   Key settings to update:
   ```yaml
   # Proxmox Configuration
   proxmox_api_url: "https://your-proxmox-server:8006/api2/json"
   proxmox_user: "ansible@pve"
   proxmox_node: "proxmox-01"
   
   # Template Configuration
   windows_template_name: "windows-server-2025-template"
   
   # Network Configuration
   dc_ip_prefix: "192.168.1"
   dc_ip_start: 10
   gateway_ip: "192.168.1.1"
   network_bridge: "vmbr0"
   
   # Domain Configuration
   domain_name: "yourdomain.local"
   netbios_name: "YOURDOMAIN"
   ```

2. **Configure sensitive variables**:

   ```bash
   nano ansible/group_vars/vault.yml
   ```

   Add your credentials:
   ```yaml
   # Proxmox Credentials
   vault_proxmox_password: "your-proxmox-password"
   
   # Active Directory Credentials  
   vault_admin_password: "YourStrongPassword123!"
   vault_dsrm_password: "YourDSRMPassword456!"
   
   # SSH Public Key
   vault_ssh_public_key: "ssh-ed25519 AAAAB3NzaC1yc2E... your-key-here"
   ```

3. **Encrypt the vault file**:

   ```bash
   ansible-vault encrypt ansible/group_vars/vault.yml
   ```

### Step 3: Validate Configuration

1. **Test Ansible connectivity**:

   ```bash
   ./deploy.sh dry-run
   ```

2. **Verify template availability**:

   Check that your Windows Server 2025 template is properly configured and accessible.

### Step 4: Deploy Domain Controllers

1. **Full deployment**:

   ```bash
   ./deploy.sh
   ```

   This will:
   - Create VMs from template
   - Configure networking and storage
   - Install and configure Active Directory
   - Set up DNS services
   - Configure monitoring

2. **Alternative: Step-by-step deployment**:

   ```bash
   # Just provision VMs
   ./deploy.sh provision
   
   # Just configure AD (on existing VMs)
   ./deploy.sh configure
   
   # Validate deployment
   ./deploy.sh validate
   ```

### Step 5: Verify the Deployment

1. **Check deployment status**:

   The deployment script will show a summary of each domain controller's status.

2. **Test domain controller functionality**:

   ```bash
   # Test DNS resolution
   nslookup yourdomain.local <DC-IP>
   
   # Test SSH connectivity
   ssh Administrator@<DC-IP>
   ```

3. **Verify AD services**:

   ```powershell
   # Connect to DC via SSH and test
   Get-ADDomain
   Get-ADDomainController
   Test-NetConnection -ComputerName <OTHER-DC-IP> -Port 389
   ```

## Post-Deployment Tasks

### Access Domain Controllers

1. **SSH Access**:
   ```bash
   ssh Administrator@<DC-IP>
   ```

2. **PowerShell Remote Access**:
   ```powershell
   Enter-PSSession -ComputerName <DC-IP> -Credential Administrator
   ```

### Monitoring and Maintenance

1. **View Health Reports**:
   Health check reports are automatically generated at:
   - `C:\Scripts\Reports\` on each DC

2. **Check Scheduled Tasks**:
   - AD Health Check: Daily at 6:00 AM
   - Performance Monitor: Every 15 minutes

3. **View Logs**:
   ```powershell
   # View recent AD events
   Get-WinEvent -LogName "Directory Service" -MaxEvents 10
   
   # View DNS events
   Get-WinEvent -LogName "DNS Server" -MaxEvents 10
   ```

## Troubleshooting

### Common Issues

#### VM Creation Failures

- **Symptom**: Ansible fails to create VMs
- **Solution**: Check Proxmox API credentials and permissions
- **Command**: Verify API token has VM creation privileges

#### SSH Connection Issues

- **Symptom**: Cannot connect to VMs via SSH
- **Solution**: Verify SSH is enabled in Windows template
- **Test**: `ssh Administrator@<DC-IP>`

#### AD Installation Failures

- **Symptom**: AD DS installation fails
- **Solution**: Check DNS settings and domain name format
- **Logs**: Check Windows Event Logs on the DC

#### DNS Resolution Issues

- **Symptom**: DNS queries fail
- **Solution**: Verify DNS forwarders and zone configuration
- **Test**: `nslookup google.com <DC-IP>`

### Getting Help

1. **Check Ansible logs**: Ansible provides detailed execution logs
2. **Review Windows Event Logs**: Check AD and DNS service logs
3. **Validate network connectivity**: Ensure VMs can reach each other
4. **Check role execution**: Use `--tags` to run specific roles

## Cleanup

### Remove All Resources

```bash
./deploy.sh cleanup
```

This will:
1. Stop all domain controller VMs
2. Delete VMs and associated storage
3. Clean up any temporary files

### Selective Cleanup

If you need to remove specific VMs, edit the cleanup playbook:
```bash
nano ansible/cleanup-vms.yml
```

## Best Practices

### Security

- Use strong passwords for all accounts
- Enable Windows Firewall with appropriate rules
- Regular security updates via Windows Update
- Monitor failed login attempts

### Backup

- Regular system state backups
- Export AD database periodically
- Document recovery procedures
- Test restore procedures

### Monitoring

- Review health check reports regularly
- Monitor performance metrics
- Set up alerting for critical services
- Plan capacity based on usage trends

## Support and Documentation

### Additional Resources

- [Microsoft Active Directory Documentation](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/)
- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Ansible Windows Documentation](https://docs.ansible.com/ansible/latest/user_guide/windows.html)

### Getting Help

1. Check the troubleshooting section
2. Review Ansible execution logs
3. Consult Microsoft documentation
4. Open an issue in the repository

Remember to always test changes in a development environment before applying to production systems.
