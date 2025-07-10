# Deployment Guide

This guide provides step-by-step instructions for deploying Windows Server 2025 Active Directory Domain Controllers on Proxmox using Terraform.

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
- [ ] WinRM enabled and configured for HTTPS
- [ ] PowerShell execution policy set to RemoteSigned
- [ ] Administrator account configured
- [ ] Template sysprepped and shut down

### Network Configuration

- [ ] Static IP range reserved for domain controllers
- [ ] DNS forwarders identified (e.g., 1.1.1.1, 8.8.8.8)
- [ ] Network gateway configured
- [ ] Firewall rules planned for AD traffic

### Tools Required

- [ ] Terraform >= 1.0 installed
- [ ] Git for version control
- [ ] Text editor (VS Code recommended)
- [ ] RDP client for Windows management

## Step-by-Step Deployment

### Step 1: Prepare the Environment

1. **Clone the repository**:

   ```bash
   git clone <repository-url>
   cd proxmox-testAD
   ```

2. **Create terraform.tfvars file**:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. **Edit terraform.tfvars** with your specific values:

   ```hcl
   # Proxmox Configuration
   proxmox_api_url      = "https://your-proxmox-server:8006/api2/json"
   proxmox_user         = "terraform@pve"
   proxmox_password     = "your-proxmox-password"
   proxmox_node         = "proxmox-01"
   
   # Template Configuration
   windows_template_name = "windows-server-2025-template"
   
   # Domain Configuration
   domain_name     = "yourdomain.local"
   netbios_name    = "YOURDOMAIN"
   admin_password  = "YourStrongPassword123!"
   dsrm_password   = "YourDSRMPassword123!"
   
   # Network Configuration
   dc_ip_prefix    = "192.168.1"
   dc_ip_start     = 10
   gateway_ip      = "192.168.1.1"
   dns_forwarders  = ["1.1.1.1", "8.8.8.8"]
   ```

### Step 2: Initialize Terraform

1. **Initialize the project**:

   ```bash
   terraform init
   ```

2. **Validate the configuration**:

   ```bash
   terraform validate
   ```

3. **Format the code**:

   ```bash
   terraform fmt
   ```

### Step 3: Plan the Deployment

1. **Create a deployment plan**:

   ```bash
   terraform plan
   ```

2. **Review the plan output** to ensure:
   - Correct number of VMs will be created
   - IP addresses are in the expected ranges
   - Resource allocation is appropriate
   - No unexpected changes

### Step 4: Deploy the Infrastructure

1. **Apply the configuration**:

   ```bash
   terraform apply
   ```

2. **Confirm the deployment** when prompted by typing `yes`

3. **Monitor the deployment progress**:
   - Initial VM creation (5-10 minutes)
   - Windows boot and configuration (10-15 minutes)
   - AD DS installation (15-20 minutes)
   - Post-configuration tasks (10-15 minutes)
   - Total deployment time: 40-60 minutes

### Step 5: Verify the Deployment

1. **Check Terraform outputs**:

   ```bash
   terraform output
   ```

2. **Verify VM status in Proxmox**:
   - VMs are running
   - Network connectivity is working
   - Resource allocation is correct

3. **Test domain controller functionality**:

   ```bash
   # Test DNS resolution
   nslookup yourdomain.local <DC-IP>
   
   # Test RDP connectivity
   rdesktop -u Administrator -p YourPassword <DC-IP>
   ```

## Post-Deployment Tasks

### Domain Controller Configuration

1. **Connect to the primary DC** via RDP
2. **Open PowerShell as Administrator**
3. **Run health check**:

   ```powershell
   PowerShell.exe -File C:\Scripts\health-check.ps1
   ```

### Verify Active Directory Services

1. **Check AD services**:

   ```powershell
   Get-Service -Name NTDS, DNS, Netlogon, KDC | Format-Table Name, Status
   ```

2. **Verify domain functionality**:

   ```powershell
   Get-ADDomain
   Get-ADForest
   Get-ADDomainController
   ```

3. **Test replication** (if multiple DCs):

   ```powershell
   repadmin /showrepl
   ```

### Configure DNS

1. **Verify DNS zones**:

   ```powershell
   Get-DnsServerZone
   ```

2. **Check DNS forwarders**:

   ```powershell
   Get-DnsServerForwarder
   ```

3. **Test external DNS resolution**:

   ```powershell
   Resolve-DnsName google.com
   ```

### Security Configuration

1. **Review Group Policy settings**:
   - Open Group Policy Management Console
   - Verify default domain policy settings
   - Check password policies

2. **Configure audit policies**:

   ```powershell
   auditpol /get /category:*
   ```

3. **Review firewall settings**:

   ```powershell
   Get-NetFirewallRule | Where-Object Enabled -eq True
   ```

## Monitoring and Maintenance

### Automated Monitoring

The deployment includes automated monitoring tasks:

- **AD Health Check**: Runs every 6 hours
- **DNS Health Monitor**: Runs every 30 minutes
- **System State Backup**: Runs daily at 2 AM

### Manual Health Checks

1. **Run comprehensive health check**:

   ```powershell
   C:\Scripts\health-check.ps1
   ```

2. **Check event logs**:

   ```powershell
   Get-EventLog -LogName "Directory Service" -EntryType Error -Newest 10
   ```

3. **Monitor replication**:

   ```powershell
   Get-ADReplicationFailure -Target $env:COMPUTERNAME
   ```

### Backup Verification

1. **Check backup status**:

   ```powershell
   Get-ChildItem D:\Backups | Sort CreationTime -Descending | Select -First 5
   ```

2. **Verify backup integrity**:

   ```powershell
   wbadmin get versions
   ```

## Troubleshooting

### Common Issues

#### VM Creation Failures

- **Symptom**: Terraform fails to create VMs
- **Solution**: Check Proxmox resources and permissions
- **Command**: `terraform apply -target=proxmox_vm_qemu.windows_dc`

#### WinRM Connection Issues

- **Symptom**: Cannot connect to VMs for configuration
- **Solution**: Verify WinRM is enabled in template
- **Test**: `Test-NetConnection <DC-IP> -Port 5986`

#### AD Installation Failures

- **Symptom**: AD DS installation fails
- **Solution**: Check DNS settings and domain name format
- **Logs**: Check Windows Event Logs on the DC

#### DNS Resolution Issues

- **Symptom**: DNS queries fail
- **Solution**: Verify DNS forwarders and zone configuration
- **Test**: `nslookup google.com <DC-IP>`

#### Replication Problems

- **Symptom**: DCs cannot replicate
- **Solution**: Check network connectivity and firewall rules
- **Command**: `repadmin /replsummary`

### Diagnostic Commands

```powershell
# Check AD services
Get-Service -Name NTDS, DNS, Netlogon, KDC

# Verify domain controller roles
netdom query fsmo

# Check DNS configuration
Get-DnsServerSettings

# Test AD connectivity
Test-ComputerSecureChannel -Verbose

# Check replication
Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME

# Review event logs
Get-WinEvent -FilterHashtable @{LogName='Directory Service'; Level=1,2} -MaxEvents 10
```

### Recovery Procedures

#### Restore from Backup

1. Boot from Windows PE or recovery media
2. Run Windows Server Backup
3. Restore system state from backup
4. Reboot and verify functionality

#### Rebuild Secondary DC

1. Demote the failed DC
2. Clean up metadata
3. Deploy new DC using Terraform
4. Verify replication

#### Forest Recovery

1. Identify authoritative DC
2. Restore from backup
3. Mark as authoritative
4. Rebuild other DCs

## Best Practices

### Security

- Use strong passwords for all accounts
- Enable auditing for security events
- Regularly review Group Policy settings
- Keep systems updated with security patches

### Performance

- Monitor resource utilization
- Optimize DNS settings
- Configure appropriate replication schedules
- Use separate disks for AD database and logs

### Backup

- Test backup and restore procedures regularly
- Store backups in multiple locations
- Document recovery procedures
- Automate backup verification

### Monitoring

- Set up automated health checks
- Monitor event logs for errors
- Track replication health
- Monitor system resources

## Support and Documentation

### Additional Resources

- [Microsoft Active Directory Documentation](https://docs.microsoft.com/en-us/windows-server/identity/ad-ds/)
- [Proxmox VE Documentation](https://pve.proxmox.com/wiki/Main_Page)
- [Terraform Proxmox Provider](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs)

### Getting Help

1. Check the troubleshooting section
2. Review system logs
3. Consult Microsoft documentation
4. Contact system administrator

Remember to always test changes in a development environment before applying to production systems.
