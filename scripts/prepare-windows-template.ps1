# Windows Server 2025 Template Preparation Script
# This script automates the preparation of a Windows Server 2025 template for Proxmox
# Run this script on a fresh Windows Server 2025 Core installation

param(
    [string]$SSHPublicKey = "",
    [switch]$SkipWindowsUpdates = $false,
    [switch]$SkipCloudbaseInit = $false,
    [switch]$SkipSysprep = $false
)

# Function to write timestamped log messages
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# Function to test internet connectivity
function Test-InternetConnection {
    try {
        $null = Invoke-WebRequest -Uri "https://www.google.com" -TimeoutSec 10 -UseBasicParsing
        return $true
    } catch {
        return $false
    }
}

Write-Log "Starting Windows Server 2025 Template Preparation" "SUCCESS"
Write-Log "Script parameters: SkipWindowsUpdates=$SkipWindowsUpdates, SkipCloudbaseInit=$SkipCloudbaseInit, SkipSysprep=$SkipSysprep"

# Test internet connectivity
Write-Log "Testing internet connectivity..."
if (-not (Test-InternetConnection)) {
    Write-Log "No internet connectivity detected. Some steps may fail." "WARNING"
}

try {
    # Step 0: Install Proxmox Guest Agent
    Write-Log "Installing Proxmox Guest Agent..."
    try {
        # Check if QEMU Guest Agent is already installed
        $qemuGAService = Get-Service -Name "QEMU-GA" -ErrorAction SilentlyContinue
        $qemuGAPath = "C:\Program Files\Qemu-ga"
        
        if ($qemuGAService -or (Test-Path $qemuGAPath)) {
            Write-Log "QEMU Guest Agent is already installed" "SUCCESS"
            
            # Ensure service is running and set to automatic
            if ($qemuGAService) {
                Set-Service -Name "QEMU-GA" -StartupType Automatic
                if ($qemuGAService.Status -ne "Running") {
                    Start-Service -Name "QEMU-GA"
                    Write-Log "QEMU Guest Agent service started" "SUCCESS"
                }
            }
        } else {
            # Check if guest agent installer is available on mounted CD-ROM
            $cdDrives = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DriveType -eq 5 }
            $guestAgentInstaller = $null
            
            foreach ($drive in $cdDrives) {
                # Check for virtio-win guest tools (newer format)
                $virtioWinPath = "$($drive.DeviceID)\virtio-win-guest-tools.exe"
                if (Test-Path $virtioWinPath) {
                    $guestAgentInstaller = $virtioWinPath
                    Write-Log "Found virtio-win guest tools installer: $guestAgentInstaller"
                    break
                }
                
                # Check for legacy Proxmox guest agent path
                $proxmoxGAPath = "$($drive.DeviceID)\guest-agent\qemu-ga-x86_64.msi"
                if (Test-Path $proxmoxGAPath) {
                    $guestAgentInstaller = $proxmoxGAPath
                    Write-Log "Found legacy Proxmox guest agent installer: $guestAgentInstaller"
                    break
                }
            }
            
            if ($guestAgentInstaller) {
                if ($guestAgentInstaller.EndsWith('.exe')) {
                    # Install virtio-win guest tools
                    Write-Log "Installing virtio-win guest tools..."
                    Start-Process -FilePath $guestAgentInstaller -ArgumentList "/S" -Wait
                } else {
                    # Install legacy MSI
                    Write-Log "Installing legacy QEMU guest agent..."
                    Start-Process msiexec.exe -ArgumentList "/i `"$guestAgentInstaller`" /quiet" -Wait
                }
                
                # Wait a moment for installation to complete
                Start-Sleep -Seconds 10
                
                # Start the service
                $qemuGAService = Get-Service -Name "QEMU-GA" -ErrorAction SilentlyContinue
                if ($qemuGAService) {
                    Set-Service -Name "QEMU-GA" -StartupType Automatic
                    Start-Service -Name "QEMU-GA"
                    Write-Log "QEMU Guest Agent installed and started successfully" "SUCCESS"
                } else {
                    Write-Log "QEMU Guest Agent service not found after installation" "WARNING"
                }
            } else {
                Write-Log "Guest agent installer not found on any mounted CD-ROM" "WARNING"
                Write-Log "Please ensure virtio-win ISO or Proxmox VE ISO is mounted" "WARNING"
                Write-Log "Looking for: virtio-win-guest-tools.exe or guest-agent/qemu-ga-x86_64.msi" "WARNING"
            }
        }
    } catch {
        Write-Log "Failed to install Proxmox Guest Agent: $($_.Exception.Message)" "WARNING"
    }

    # Step 1: Configure Windows Updates (if not skipped)
    if (-not $SkipWindowsUpdates) {
        Write-Log "Installing PSWindowsUpdate module and applying critical updates..."
        try {
            Install-Module PSWindowsUpdate -Force -Confirm:$false
            Import-Module PSWindowsUpdate
            Get-WUInstall -AcceptAll -AutoReboot:$false -Confirm:$false
            Write-Log "Windows updates installed successfully" "SUCCESS"
        } catch {
            Write-Log "Failed to install Windows updates: $($_.Exception.Message)" "WARNING"
        }
    } else {
        Write-Log "Skipping Windows Updates as requested" "WARNING"
    }

    # Step 2: Install PowerShell 7
    Write-Log "Checking PowerShell 7 installation..."
    try {
        $pwshPath = "C:\Program Files\PowerShell\7"
        $pwshExe = "$pwshPath\pwsh.exe"
        
        # Check if PowerShell 7 is already installed
        if (Test-Path $pwshExe) {
            # Get the version to verify it's working
            $version = & $pwshExe -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
            if ($version) {
                Write-Log "PowerShell 7 is already installed (version: $version)" "SUCCESS"
                
                # Ensure it's in PATH
                $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
                if ($currentPath -notlike "*$pwshPath*") {
                    $newPath = "$currentPath;$pwshPath"
                    [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
                    Write-Log "PowerShell 7 added to PATH" "SUCCESS"
                } else {
                    Write-Log "PowerShell 7 is already in PATH" "SUCCESS"
                }
            } else {
                Write-Log "PowerShell 7 executable found but not working properly, reinstalling..." "WARNING"
                throw "PowerShell 7 not functional"
            }
        } else {
            Write-Log "PowerShell 7 not found, installing..."
            
            $ps7Url = "https://github.com/PowerShell/PowerShell/releases/download/v7.4.0/PowerShell-7.4.0-win-x64.msi"
            $ps7Installer = "$env:TEMP\PowerShell-7.4.0-win-x64.msi"
            
            Invoke-WebRequest -Uri $ps7Url -OutFile $ps7Installer
            Start-Process msiexec.exe -ArgumentList "/i `"$ps7Installer`" /quiet" -Wait
            
            # Add PowerShell 7 to PATH
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
            if ($currentPath -notlike "*$pwshPath*") {
                $newPath = "$currentPath;$pwshPath"
                [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
                Write-Log "PowerShell 7 added to PATH" "SUCCESS"
            }
            
            # Verify installation
            & $pwshExe -Version
            Write-Log "PowerShell 7 installed successfully" "SUCCESS"
        }
    } catch {
        Write-Log "Failed to install/verify PowerShell 7: $($_.Exception.Message)" "ERROR"
        throw
    }

    # Step 3: Configure OpenSSH Server
    Write-Log "Installing and configuring OpenSSH Server..."
    try {
        # Install OpenSSH Server
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        
        # Start and configure SSH service
        Start-Service sshd
        Set-Service -Name sshd -StartupType 'Automatic'
        
        # Verify firewall rule exists
        $firewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
        if (-not $firewallRule) {
            New-NetFirewallRule -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
        }
        
        # Configure SSH for key-based authentication
        $authorizedKeysPath = "C:\ProgramData\ssh\administrators_authorized_keys"
        New-Item -ItemType File -Path $authorizedKeysPath -Force
        
        # Set proper permissions
        icacls $authorizedKeysPath /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
        
        # Add SSH public key if provided
        if ($SSHPublicKey) {
            Add-Content -Path $authorizedKeysPath -Value $SSHPublicKey
            Write-Log "SSH public key added to authorized_keys" "SUCCESS"
        }
        
        # Configure SSH daemon
        $sshdConfigPath = "C:\ProgramData\ssh\sshd_config"
        $sshdConfig = @"
# Enhanced SSH configuration for Windows Server
Port 22
Protocol 2

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
UsePAM no

# Logging
SyslogFacility AUTH
LogLevel INFO

# Connection settings
ClientAliveInterval 300
ClientAliveCountMax 2
MaxAuthTries 3
MaxSessions 10

# Subsystem for SFTP
Subsystem sftp sftp-server.exe

# PowerShell as default shell
ForceCommand powershell.exe
"@
        $sshdConfig | Out-File -FilePath $sshdConfigPath -Encoding UTF8 -Force
        
        # Configure PowerShell for SSH
        New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
        
        # Restart SSH service
        Restart-Service sshd
        
        Write-Log "OpenSSH Server configured successfully" "SUCCESS"
    } catch {
        Write-Log "Failed to configure OpenSSH: $($_.Exception.Message)" "ERROR"
        throw
    }

    # Step 4: Install CloudBase-Init (if not skipped)
    if (-not $SkipCloudbaseInit) {
        Write-Log "Installing CloudBase-Init..."
        try {
            $cloudbaseUrl = "https://cloudbase.it/downloads/CloudbaseInitSetup_1_1_4_x64.msi"
            $cloudbaseInstaller = "$env:TEMP\CloudbaseInit.msi"
            
            Invoke-WebRequest -Uri $cloudbaseUrl -OutFile $cloudbaseInstaller
            Start-Process msiexec.exe -ArgumentList "/i `"$cloudbaseInstaller`" /quiet /qn" -Wait
            
            # Configure CloudBase-Init
            $cloudbaseConfigPath = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf"
            $cloudbaseConfig = @"
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
"@
            $cloudbaseConfig | Out-File -FilePath $cloudbaseConfigPath -Encoding UTF8 -Force
            
            Write-Log "CloudBase-Init installed and configured successfully" "SUCCESS"
        } catch {
            Write-Log "Failed to install CloudBase-Init: $($_.Exception.Message)" "WARNING"
        }
    } else {
        Write-Log "Skipping CloudBase-Init installation as requested" "WARNING"
    }

    # Step 5: System Optimization and Hardening
    Write-Log "Performing system optimization and hardening..."
    try {
        # Set performance options for background services
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 24
        
        # Disable unnecessary services
        $servicesToDisable = @("Fax", "XblGameSave", "XblAuthManager", "XboxNetApiSvc")
        foreach ($service in $servicesToDisable) {
            try {
                Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Log "Disabled service: $service"
            } catch {
                Write-Log "Service $service not found or already disabled"
            }
        }
        
        # Configure Windows Defender
        Set-MpPreference -DisableRealtimeMonitoring $false
        Set-MpPreference -DisableIOAVProtection $false
        Set-MpPreference -DisableBehaviorMonitoring $false
        Set-MpPreference -DisableBlockAtFirstSeen $false
        
        # Configure registry settings
        New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -Value 1 -PropertyType DWORD -Force
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1
        
        # Set PowerShell execution policy
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force
        
        # Enable PowerShell remoting
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        
        Write-Log "System optimization and hardening completed" "SUCCESS"
    } catch {
        Write-Log "Failed during system optimization: $($_.Exception.Message)" "WARNING"
    }

    # Step 6: Create Scripts Directory
    Write-Log "Creating scripts directory..."
    try {
        New-Item -ItemType Directory -Path "C:\Scripts" -Force
        New-Item -ItemType Directory -Path "C:\Scripts\Reports" -Force
        icacls "C:\Scripts" /grant "Administrators:(OI)(CI)F" /T
        Write-Log "Scripts directory created successfully" "SUCCESS"
    } catch {
        Write-Log "Failed to create scripts directory: $($_.Exception.Message)" "WARNING"
    }

    # Step 7: Final System Preparation
    Write-Log "Performing final system cleanup..."
    try {
        # Clean temporary files
        Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Clear event logs
        Get-EventLog -LogName * | ForEach-Object { 
            try {
                Clear-EventLog $_.Log
            } catch {
                Write-Log "Could not clear log: $($_.Log)"
            }
        }
        
        # Clean up Windows Update cache
        Stop-Service wuauserv -Force
        Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Recurse -Force -ErrorAction SilentlyContinue
        Start-Service wuauserv
        
        # Disable hibernate and page file
        powercfg -h off
        
        $cs = Get-WmiObject -Class Win32_ComputerSystem
        $cs.AutomaticManagedPagefile = $false
        $cs.Put()
        
        $pf = Get-WmiObject -Class Win32_PageFileSetting -ErrorAction SilentlyContinue
        if ($pf) {
            $pf.Delete()
        }
        
        Write-Log "System cleanup completed successfully" "SUCCESS"
    } catch {
        Write-Log "Failed during system cleanup: $($_.Exception.Message)" "WARNING"
    }

    # Step 8: Sysprep (if not skipped)
    if (-not $SkipSysprep) {
        Write-Log "Running Sysprep..." "SUCCESS"
        Write-Log "The system will shut down after Sysprep completes."
        Write-Log "After shutdown, convert the VM to a template in Proxmox."
        
        Start-Sleep -Seconds 5
        
        # Run Sysprep
        C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
    } else {
        Write-Log "Skipping Sysprep as requested" "WARNING"
        Write-Log "Template preparation completed successfully!" "SUCCESS"
        Write-Log "Remember to run Sysprep before converting to template."
    }

} catch {
    Write-Log "Template preparation failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
