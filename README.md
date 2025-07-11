# Windows Server 2025 Active Directory Domain Controller on Proxmox

This project uses Terraform to deploy Windows Server 2025 Active Directory Domain Controllers on Proxmox VE with comprehensive post-installation configuration.

## Features

- **Infrastructure as Code**: Complete Terraform configuration for repeatable deployments
- **Multiple Domain Controllers**: Support for deploying multiple DCs for redundancy
- **Comprehensive Configuration**: Automated AD DS installation and configuration
- **Security Hardening**: Built-in security configurations and policies
- **Monitoring & Health Checks**: Automated health monitoring and reporting
- **Backup Strategy**: Automated backup configuration for AD data
- **DNS Configuration**: Complete DNS setup with forwarders and zones
- **Modular Design**: Reusable Terraform modules for different environments

## Prerequisites

### Proxmox Environment

- Proxmox VE cluster with sufficient resources
- Windows Server 2025 template properly configured (see Template Preparation below)
- Storage pool with adequate space (120GB+ per DC)
- Network bridge configured for domain controllers

### Terraform Setup

- Terraform >= 1.0
- Proxmox provider configured
- Network connectivity to Proxmox API

### Network Requirements

- Dedicated network segment for domain controllers
- Static IP addresses reserved for DCs
- DNS forwarders configured
- Firewall rules for AD traffic

## Windows Server 2025 Template Preparation

Creating a proper Windows Server 2025 template is crucial for successful deployment. Follow these steps:

### Step 1: Create Base VM

1. **Create a new VM in Proxmox**:
   - VM ID: Use a high number (e.g., 9000) to avoid conflicts
   - Name: `windows-server-2025-template`
   - OS Type: Microsoft Windows
   - ISO: Windows Server 2025 installation media
   - ISO: Current version of [virtio drivers](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/?C=M;O=D)

2. **Configure VM Resources**:

   ```shell
   CPU: 2 cores (minimum for installation)
   Memory: 4GB (minimum for installation)
   Disk: virtio block 32GB (will be resized during deployment)
   Network: virtio (for better performance)
   ```

### Step 2: Install Windows Server 2025

1. **Boot from ISO** and perform a standard Windows Server 2025 installation
2. **Choose Windows Server 2025 Standard (Server Core)** - Recommended for better security, performance, and reduced resource usage
3. **Set initial Administrator password**: Use a temporary password (will be changed via cloud-init)
4. **Complete Windows Setup** and boot to command prompt
5. **Install virtio drivers from ISO**

   > **Note**: Server Core provides a minimal installation without GUI, offering better security and performance for domain controllers. All configuration will be done via PowerShell and remote management tools.

### Step 3: Automated Template Preparation

For convenience, we've created an automated script that performs the remaining template preparation steps. You can either use this automated approach or follow the manual steps below.

#### Option A: Automated Script (Recommended)

1. **Download and run the preparation script**:

   ```powershell
   # Download the template preparation script
   Invoke-WebRequest -Uri "https://raw.githubusercontent.com/qovert/proxmox-dc/main/scripts/prepare-windows-template.ps1" -OutFile "C:\prepare-template.ps1"
   
   # Run the script (basic usage)
   PowerShell.exe -ExecutionPolicy Bypass -File "C:\prepare-template.ps1"
   
   # Or run with your SSH public key for immediate key-based authentication
   PowerShell.exe -ExecutionPolicy Bypass -File "C:\prepare-template.ps1" -SSHPublicKey "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... your-public-key"
   ```

2. **Script parameters** (optional):
   - `-SSHPublicKey`: Your SSH public key for immediate setup
   - `-SkipWindowsUpdates`: Skip Windows Updates installation
   - `-SkipCloudbaseInit`: Skip CloudBase-Init installation  
   - `-SkipSysprep`: Skip automatic Sysprep (run manually later)

3. **What the script does**:
   - Installs critical Windows updates
   - Downloads and installs PowerShell 7 (adds to PATH)
   - Configures OpenSSH Server with key-based authentication
   - Installs and configures CloudBase-Init
   - Performs system optimization and security hardening
   - Creates required directories and sets permissions
   - Cleans up temporary files and logs
   - Runs Sysprep and shuts down the VM

4. **After script completion**:
   - The VM will automatically shut down after Sysprep
   - Convert the VM to a template in Proxmox Web UI
   - The template is ready for deployment

#### Option B: Manual Steps

If you prefer to run each step manually or need to customize the process, follow these detailed steps:

### Step 3: Install Required Components

1. **Install Proxmox Guest Agent**:

   ```powershell
   # Download from Proxmox VE ISO (already mounted as CD-ROM)
   # Or download from: https://github.com/proxmox/pve-qemu-guest-agent
   # Run the installer: proxmox-ve-guest-agent.exe
   ```

2. **Configure Windows Updates**:

   ```powershell
   # Install critical updates
   Install-Module PSWindowsUpdate -Force
   Get-WUInstall -AcceptAll -AutoReboot
   ```

3. **Install PowerShell 7** (recommended):

   ```powershell
   # Download and install PowerShell 7
   Invoke-WebRequest -Uri "https://github.com/PowerShell/PowerShell/releases/download/v7.4.0/PowerShell-7.4.0-win-x64.msi" -OutFile "PowerShell-7.4.0-win-x64.msi"
   Start-Process msiexec.exe -ArgumentList "/i PowerShell-7.4.0-win-x64.msi /quiet" -Wait
   
   # Add PowerShell 7 to PATH
   $pwshPath = "C:\Program Files\PowerShell\7"
   $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
   if ($currentPath -notlike "*$pwshPath*") {
       $newPath = "$currentPath;$pwshPath"
       [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
       Write-Host "PowerShell 7 added to PATH"
   }
   
   # Verify PowerShell 7 installation
   & "C:\Program Files\PowerShell\7\pwsh.exe" -Version
   ```

### Step 4: Configure OpenSSH Server

1. **Install OpenSSH Server**:

   ```powershell
   # Add OpenSSH Server capability
   Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
   
   # Start and configure SSH service
   Start-Service sshd
   Set-Service -Name sshd -StartupType 'Automatic'
   
   # Confirm the Firewall rule is configured (should be created automatically)
   Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP"
   ```

2. **Configure SSH for Key-Based Authentication**:

   ```powershell
   # Create administrators_authorized_keys file
   $authorizedKeysPath = "C:\ProgramData\ssh\administrators_authorized_keys"
   New-Item -ItemType File -Path $authorizedKeysPath -Force
   
   # Set proper permissions (only System and Administrators)
   icacls $authorizedKeysPath /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
   
   # Configure SSH daemon
   $sshdConfigPath = "C:\ProgramData\ssh\sshd_config"
   @"
   # Windows Server 2025 SSH Configuration
   Port 22
   
   # Authentication
   PubkeyAuthentication yes
   AuthorizedKeysFile .ssh/authorized_keys
   
   # For administrators, use the administrators_authorized_keys file
   Match Group administrators
          AuthorizedKeysFile C:/ProgramData/ssh/administrators_authorized_keys
   
   # Security settings
   PasswordAuthentication no
   PermitEmptyPasswords no
   ChallengeResponseAuthentication no
   
   # Logging
   LogLevel INFO
   
   # Connection settings
   ClientAliveInterval 300
   ClientAliveCountMax 2
   MaxAuthTries 3
   MaxSessions 10
   
   # Subsystem for SFTP
   Subsystem sftp sftp-server.exe
   "@ | Out-File -FilePath $sshdConfigPath -Encoding UTF8 -Force
   
   # Test SSH configuration before starting service
   $sshdExe = "C:\Windows\System32\OpenSSH\sshd.exe"
   if (Test-Path $sshdExe) {
       $configTest = & $sshdExe -t 2>&1
       if ($LASTEXITCODE -ne 0) {
           Write-Host "SSH configuration test failed: $configTest" -ForegroundColor Red
       } else {
           Write-Host "SSH configuration test passed" -ForegroundColor Green
       }
   }
   
   # Restart SSH service
   Restart-Service sshd
   ```

3. **Configure PowerShell for SSH**:

   ```powershell
   # Set PowerShell as default shell for SSH
   New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
   
   # Configure PowerShell execution policy
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force
   
   # Enable PowerShell remoting for local use
   Enable-PSRemoting -Force -SkipNetworkProfileCheck
   ```

### Step 5: Install CloudBase-Init (Optional but Recommended)

1. **Download and Install CloudBase-Init**:

   ```powershell
   # Download CloudBase-Init
   Invoke-WebRequest -Uri "https://cloudbase.it/downloads/CloudbaseInitSetup_1_1_4_x64.msi" -OutFile "CloudbaseInit.msi"
   
   # Install silently
   Start-Process msiexec.exe -ArgumentList "/i CloudbaseInit.msi /quiet /qn" -Wait
   ```

2. **Configure CloudBase-Init** (`C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf`):

   ```ini
   [DEFAULT]
   username=Administrator
   groups=Administrators
   inject_user_password=true
   config_drive_raw_hhd=true
   config_drive_cdrom=true
   config_drive_vfat=true
   bsdtar_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\bsdtar.exe
   mtools_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\bin\
   verbose=true
   debug=true
   logdir=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\
   logfile=cloudbase-init.log
   default_log_levels=comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN
   logging_serial_port_settings=COM1,115200,N,8
   mtu_use_dhcp_config=true
   ntp_use_dhcp_config=true
   local_scripts_path=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\LocalScripts\
   ```

### Step 6: System Optimization and Hardening

1. **Optimize for Server Role**:

   ```powershell
   # Set performance options for background services
   Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 24
   
   # Disable unnecessary services
   $servicesToDisable = @("Fax", "XblGameSave", "XblAuthManager", "XboxNetApiSvc")
   foreach ($service in $servicesToDisable) {
       try {
           Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
       } catch {
           Write-Host "Service $service not found or already disabled"
       }
   }
   ```

2. **Configure Windows Defender**:

   ```powershell
   # Configure Windows Defender for server environment
   Set-MpPreference -DisableRealtimeMonitoring $false
   Set-MpPreference -DisableIOAVProtection $false
   Set-MpPreference -DisableBehaviorMonitoring $false
   Set-MpPreference -DisableBlockAtFirstSeen $false
   ```

3. **Configure Registry Settings**:

   ```powershell
   # Disable Server Manager auto-start
   New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -Value 1 -PropertyType DWORD -Force
   
   # Configure RDP settings
   Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
   Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1
   ```

### Step 7: Create Scripts Directory

1. **Create Scripts Directory**:

   ```powershell
   # Create directory for automation scripts
   New-Item -ItemType Directory -Path "C:\Scripts" -Force
   New-Item -ItemType Directory -Path "C:\Scripts\Reports" -Force
   
   # Set appropriate permissions
   icacls "C:\Scripts" /grant "Administrators:(OI)(CI)F" /T
   ```

### Step 8: Final System Preparation

1. **Clean up System**:

   ```powershell
   # Clean temporary files
   Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
   Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
   
   # Clear event logs
   Get-EventLog -LogName * | ForEach-Object { Clear-EventLog $_.Log }
   
   # Clean up Windows Update cache
   Stop-Service wuauserv -Force
   Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
   Start-Service wuauserv
   ```

2. **Disable Hibernate and Page File** (optional for template):

   ```powershell
   # Disable hibernate
   powercfg -h off
   
   # Disable page file (will be recreated during deployment)
   $cs = Get-WmiObject -Class Win32_ComputerSystem
   $cs.AutomaticManagedPagefile = $false
   $cs.Put()
   $pf = Get-WmiObject -Class Win32_PageFileSetting
   $pf.Delete()
   ```

### Step 9: Sysprep the Template

1. **Run Sysprep**:

   ```powershell
   # Sysprep with OOBE and generalize
   C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown /unattend:C:\Windows\System32\Sysprep\unattend.xml
   ```

2. **Wait for Shutdown**: The VM will automatically shut down after sysprep completes

### Step 10: Convert to Template

1. **In Proxmox Web UI**:
   - Right-click the VM
   - Select "Convert to template"
   - Wait for conversion to complete

2. **Verify Template Settings**:

   ```bash
   # In Proxmox shell, verify template exists
   qm list | grep template
   ```

### Template Validation

Before using the template, verify these components are properly configured:

**If you used the automated script:**

- [ ] Script completed without critical errors
- [ ] VM shut down automatically after Sysprep
- [ ] SSH key authentication is configured (if key was provided)

**Manual verification steps:**

- [ ] Proxmox Guest Agent service is running
- [ ] OpenSSH Server service is running (port 22)
- [ ] SSH key-based authentication is configured
- [ ] CloudBase-Init is installed and configured
- [ ] PowerShell execution policy is set to RemoteSigned
- [ ] Windows Firewall allows SSH traffic
- [ ] Template is properly sysprepped and generalized

### Testing the Template

1. **Create a test VM from template**:

   ```bash
   # Clone template to test VM
   qm clone 9000 999 --name test-template
   qm set 999 --memory 4096 --cores 2
   qm start 999
   ```

2. **Verify functionality**:
   - VM boots properly
   - Network configuration works
   - SSH is accessible with key authentication
   - CloudBase-Init processes user data

### Quick SSH Test

If you provided an SSH key during template preparation:

```bash
# Test SSH connection (replace with your actual IP and key path)
ssh -i ~/.ssh/your-key Administrator@192.168.1.100

# You should be able to connect without password
# Once connected, test PowerShell 7
pwsh -Version
```

## Quick Start

1. **Generate SSH key pair**:

   ```bash
   # Generate SSH key pair for the project
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/proxmox-testAD -C "proxmox-testAD-deployment"
   
   # Add to SSH agent
   ssh-add ~/.ssh/proxmox-testAD
   
   # Copy public key content for terraform.tfvars
   cat ~/.ssh/proxmox-testAD.pub
   ```

1. **Clone the repository**:

   ```bash
   git clone https://github.com/qovert/proxmox-dc.git
   cd proxmox-dc
   ```

2. **Create terraform.tfvars**:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. **Configure variables**:

   Edit `terraform.tfvars` with your environment-specific values:

   ```hcl
   proxmox_api_url = "https://your-proxmox-server:8006/api2/json"
   proxmox_user    = "terraform@pve"
   proxmox_password = "your-password"
   domain_name     = "yourdomain.local"
   admin_password  = "YourStrongPassword123!"
   
   # SSH Configuration
   ssh_private_key_path = "~/.ssh/proxmox-testAD"
   ssh_public_key       = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC... your-public-key-here"
   ```

4. **Initialize Terraform**:

   ```bash
   terraform init
   ```

5. **Plan deployment**:

   ```bash
   terraform plan
   ```

6. **Deploy infrastructure**:

   ```bash
   terraform apply
   ```

## Key Features of This Implementation

This project has been specifically designed to use **OpenSSH instead of WinRM** for secure remote management. This modern approach provides several advantages:

### Why OpenSSH Over WinRM?

- **Enhanced Security**: SSH key-based authentication is more secure than password-based WinRM
- **Industry Standard**: OpenSSH is the universal standard for secure remote access
- **Better Tooling**: Extensive ecosystem of SSH tools and libraries
- **Simplified Firewall**: Only requires port 22 (SSH) vs. port 5986 (WinRM HTTPS)
- **Cross-Platform**: Same tools work on Linux, macOS, and Windows
- **Better Debugging**: Standard SSH debugging tools and techniques

### Authentication Method

The project uses **SSH key-based authentication** for all remote operations:

- No passwords transmitted over the network
- Cryptographically secure authentication
- Easy to manage and rotate keys
- Supports automation and CI/CD pipelines

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

- Terraform logs: `terraform apply -verbose`
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

Modify the `organizational_units` variable:

```hcl
organizational_units = [
  "Servers",
  "Workstations",
  "Users",
  "Groups",
  "Service Accounts",
  "Custom OU 1",
  "Custom OU 2"
]
```

### Custom PowerShell Scripts

Add your scripts to the `scripts/` directory and reference them in the Terraform configuration.

### Environment-Specific Settings

Use different `.tfvars` files for different environments:

- `development.tfvars`
- `staging.tfvars`
- `production.tfvars`

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:

1. Check the troubleshooting section
2. Review the logs
3. Open an issue in the repository
4. Provide full error messages and environment details

## Acknowledgments

- Proxmox VE community
- Terraform Proxmox provider maintainers
- Windows Server documentation
- Active Directory best practices guides
