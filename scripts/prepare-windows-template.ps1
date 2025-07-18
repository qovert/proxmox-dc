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

# Function to install MSI packages
function Install-MsiPackage {
    param(
        [string]$InstallerPath,
        [string]$PackageName,
        [string[]]$Arguments = @("/quiet"),
        [int]$WaitSeconds = 5
    )
    
    try {
        Write-Log "Installing $PackageName..."
        $argString = "/i `"$InstallerPath`" " + ($Arguments -join " ")
        Start-Process msiexec.exe -ArgumentList $argString -Wait
        
        if ($WaitSeconds -gt 0) {
            Start-Sleep -Seconds $WaitSeconds
        }
        
        Write-Log "$PackageName installed successfully" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed to install $PackageName`: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# Function to manage PATH environment variable
function Add-ToPath {
    param(
        [string]$PathToAdd,
        [string]$Description = "Path"
    )
    
    try {
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($currentPath -notlike "*$PathToAdd*") {
            $newPath = "$currentPath;$PathToAdd"
            [Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
            Write-Log "$Description added to PATH" "SUCCESS"
            return $true
        } else {
            Write-Log "$Description is already in PATH" "SUCCESS"
            return $true
        }
    } catch {
        Write-Log "Failed to add $Description to PATH: $($_.Exception.Message)" "WARNING"
        return $false
    }
}

# Function to configure and start a service
function Set-ServiceConfiguration {
    param(
        [string]$ServiceName,
        [string]$StartupType = "Automatic",
        [bool]$StartService = $true,
        [string]$Description = ""
    )
    
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            Set-Service -Name $ServiceName -StartupType $StartupType
            if ($StartService -and $service.Status -ne "Running") {
                Start-Service -Name $ServiceName
            }
            $desc = if ($Description) { $Description } else { $ServiceName }
            Write-Log "$desc service configured and started" "SUCCESS"
            return $true
        } else {
            Write-Log "Service '$ServiceName' not found" "WARNING"
            return $false
        }
    } catch {
        Write-Log "Failed to configure service '$ServiceName': $($_.Exception.Message)" "WARNING"
        return $false
    }
}

# Function to manage SSH public keys
function Set-SSHPublicKey {
    param(
        [string]$PublicKey,
        [string]$AuthorizedKeysPath = "C:\ProgramData\ssh\administrators_authorized_keys"
    )
    
    if (-not $PublicKey) {
        return $true
    }
    
    try {
        # Ensure the authorized_keys file exists
        if (-not (Test-Path $AuthorizedKeysPath)) {
            New-Item -ItemType File -Path $AuthorizedKeysPath -Force | Out-Null
            icacls $AuthorizedKeysPath /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
            Write-Log "Created SSH authorized_keys file" "SUCCESS"
        }
        
        # Check if key already exists
        $existingKeys = Get-Content $AuthorizedKeysPath -ErrorAction SilentlyContinue
        if ($existingKeys -notcontains $PublicKey) {
            Add-Content -Path $AuthorizedKeysPath -Value $PublicKey
            Write-Log "SSH public key added to authorized_keys" "SUCCESS"
        } else {
            Write-Log "SSH public key already exists in authorized_keys" "SUCCESS"
        }
        
        return $true
    } catch {
        Write-Log "Failed to configure SSH public key: $($_.Exception.Message)" "WARNING"
        return $false
    }
}

# Function to download files with retry logic
function Get-FileFromUrl {
    param(
        [string]$Url,
        [string]$OutputPath,
        [int]$MaxRetries = 3
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Log "Downloading from $Url (attempt $i/$MaxRetries)..."
            Invoke-WebRequest -Uri $Url -OutFile $OutputPath -UseBasicParsing
            Write-Log "Download completed successfully" "SUCCESS"
            return $true
        } catch {
            if ($i -eq $MaxRetries) {
                Write-Log "Failed to download after $MaxRetries attempts: $($_.Exception.Message)" "ERROR"
                return $false
            }
            Write-Log "Download attempt $i failed, retrying..." "WARNING"
            Start-Sleep -Seconds 5
        }
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
            Set-ServiceConfiguration -ServiceName "QEMU-GA" -Description "QEMU Guest Agent"
        } else {
            # Check if guest agent installer is available on mounted CD-ROM
            $cdDrives = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DriveType -eq 5 }
            $guestAgentInstaller = $null
            
            foreach ($drive in $cdDrives) {
                # Check for virtio-win guest tools as of version 0.1.271
                $virtioWinPath = "$($drive.DeviceID)\virtio-win-guest-tools.exe"
                if (Test-Path $virtioWinPath) {
                    $guestAgentInstaller = $virtioWinPath
                    Write-Log "Found virtio-win guest tools installer: $guestAgentInstaller"
                    break
                }
                
                # Check for legacy Proxmox guest agent path as of version 0.1.271
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
                    Install-MsiPackage -InstallerPath $guestAgentInstaller -PackageName "QEMU Guest Agent" -WaitSeconds 10
                }
                
                # Configure the service
                Set-ServiceConfiguration -ServiceName "QEMU-GA" -Description "QEMU Guest Agent"
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
                Add-ToPath -PathToAdd $pwshPath -Description "PowerShell 7"
            } else {
                Write-Log "PowerShell 7 executable found but not working properly, reinstalling..." "WARNING"
                throw "PowerShell 7 not functional"
            }
        } else {
            Write-Log "PowerShell 7 not found, installing..."
            
            $ps7Url = "https://github.com/PowerShell/PowerShell/releases/download/v7.4.0/PowerShell-7.4.0-win-x64.msi"
            $ps7Installer = "$env:TEMP\PowerShell-7.4.0-win-x64.msi"
            
            if (Get-FileFromUrl -Url $ps7Url -OutputPath $ps7Installer) {
                if (Install-MsiPackage -InstallerPath $ps7Installer -PackageName "PowerShell 7") {
                    Add-ToPath -PathToAdd $pwshPath -Description "PowerShell 7"
                    
                    # Verify installation
                    & $pwshExe -Version
                    Write-Log "PowerShell 7 installed successfully" "SUCCESS"
                }
            }
        }
    } catch {
        Write-Log "Failed to install/verify PowerShell 7: $($_.Exception.Message)" "ERROR"
        throw
    }

    # Step 3: Configure OpenSSH Server
    Write-Log "Checking OpenSSH Server installation..."
    try {
        $sshdConfigPath = "C:\ProgramData\ssh\sshd_config"
        $sshServiceName = "sshd"
        $sshService = Get-Service -Name $sshServiceName -ErrorAction SilentlyContinue
        
        # Check if SSH is already installed and configured
        if ($sshService -and $sshService.Status -eq "Running" -and (Test-Path $sshdConfigPath)) {
            Write-Log "OpenSSH Server is already installed and running" "SUCCESS"
            Write-Log "SSH service status: $($sshService.Status)" "SUCCESS"
            Write-Log "SSH configuration file exists: $sshdConfigPath" "SUCCESS"
            
            # Add SSH public key if provided
            Set-SSHPublicKey -PublicKey $SSHPublicKey
        } elseif ($sshService -and (Test-Path $sshdConfigPath)) {
            Write-Log "OpenSSH Server is installed but not running, starting service..." "INFO"
            Write-Log "SSH service status: $($sshService.Status)" "INFO"
            Write-Log "SSH configuration file exists: $sshdConfigPath" "SUCCESS"
            
            try {
                # Configure and start the SSH service using utility function
                if (Set-ServiceConfiguration -ServiceName $sshServiceName -Description "SSH Server") {
                    # Add SSH public key if provided
                    Set-SSHPublicKey -PublicKey $SSHPublicKey
                    
                    # Verify the service is now running
                    $updatedService = Get-Service -Name $sshServiceName
                    Write-Log "SSH service status after start: $($updatedService.Status)" "SUCCESS"
                } else {
                    throw "Failed to configure SSH service using Set-ServiceConfiguration"
                }
            } catch {
                Write-Log "Failed to start SSH service: $($_.Exception.Message)" "WARNING"
                Write-Log "Will proceed with full OpenSSH installation..." "INFO"
                # Fall through to the full installation logic below
            }
        } else {
            Write-Log "OpenSSH Server not properly installed or configured, proceeding with installation..."
            
            # Install OpenSSH Server
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
            
            # Wait a moment for installation to complete
            Start-Sleep -Seconds 5
            
            # Start and configure SSH service
            # Look for known SSH service names: sshd and ssh-agent
            $knownSSHServices = @("sshd", "ssh-agent")
            $serviceFound = $false
            
            foreach ($serviceName in $knownSSHServices) {
                $testService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                if ($testService) {
                    $sshServiceName = $serviceName
                    Write-Log "Found SSH service: '$serviceName'" "INFO"
                    
                    # For the main SSH server daemon, configure and start it
                    if ($serviceName -eq "sshd") {
                        if (Set-ServiceConfiguration -ServiceName $serviceName -Description "SSH Server") {
                            $serviceFound = $true
                            break
                        }
                    }
                }
            }
            
            # If neither sshd nor ssh-agent found, fall back to generic search
            if (-not $serviceFound) {
                Write-Log "Known SSH services (sshd, ssh-agent) not found, searching for alternatives..." "WARNING"
                
                $sshServices = Get-Service | Where-Object { 
                    $_.Name -like "*ssh*" -or 
                    $_.DisplayName -like "*SSH*" -or 
                    $_.DisplayName -like "*OpenSSH*"
                }
                
                foreach ($sshSvc in $sshServices) {
                    # Prioritize services that look like the main SSH daemon
                    if ($sshSvc.DisplayName -like "*Server*" -or $sshSvc.Name -like "*sshd*") {
                        $sshServiceName = $sshSvc.Name
                        Write-Log "Trying SSH service: Name='$($sshSvc.Name)', DisplayName='$($sshSvc.DisplayName)'" "INFO"
                        
                        if (Set-ServiceConfiguration -ServiceName $sshServiceName -Description "SSH Server ($($sshSvc.DisplayName))") {
                            $serviceFound = $true
                            break
                        }
                    }
                }
                
                if (-not $serviceFound) {
                    Write-Log "SSH service not found after installation. Available SSH-related services:" "WARNING"
                    Get-Service | Where-Object { $_.Name -like "*ssh*" -or $_.DisplayName -like "*SSH*" } | ForEach-Object {
                        Write-Log "  - Name: '$($_.Name)', DisplayName: '$($_.DisplayName)', Status: '$($_.Status)'" "INFO"
                    }
                    throw "SSH service not found after OpenSSH Server installation"
                }
            }
            
            # Verify firewall rule exists
            $firewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
            if (-not $firewallRule) {
                New-NetFirewallRule -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
            }
            
            # Configure SSH for key-based authentication
            Set-SSHPublicKey -PublicKey $SSHPublicKey
            
            # Download and apply SSH configuration from GitHub
            Write-Log "Downloading SSH configuration from GitHub..."
            $sshConfigUrl = "https://raw.githubusercontent.com/qovert/proxmox-dc/main/configs/sshd_config"
            $tempSshConfig = "$env:TEMP\sshd_config"
            
            if (Get-FileFromUrl -Url $sshConfigUrl -OutputPath $tempSshConfig) {
                Copy-Item -Path $tempSshConfig -Destination $sshdConfigPath -Force
                Write-Log "SSH configuration file downloaded and applied" "SUCCESS"
                
                # Test SSH configuration before starting service
                Write-Log "Testing SSH configuration..."
                $sshdExe = "C:\Windows\System32\OpenSSH\sshd.exe"
                if (Test-Path $sshdExe) {
                    try {
                        # Test SSH configuration syntax
                        $configTest = & $sshdExe -t 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            Write-Log "SSH configuration test passed" "SUCCESS"
                        } else {
                            Write-Log "SSH configuration test failed: $configTest" "ERROR"
                            Write-Log "Downloading minimal configuration as fallback..." "INFO"
                            
                            # Download minimal configuration as fallback
                            $minimalConfigUrl = "https://raw.githubusercontent.com/qovert/proxmox-dc/main/configs/sshd_config_minimal"
                            $tempMinimalConfig = "$env:TEMP\sshd_config_minimal"
                            
                            if (Get-FileFromUrl -Url $minimalConfigUrl -OutputPath $tempMinimalConfig) {
                                Copy-Item -Path $tempMinimalConfig -Destination $sshdConfigPath -Force
                                Write-Log "Minimal SSH configuration downloaded and applied" "SUCCESS"
                            } else {
                                Write-Log "Failed to download minimal SSH configuration, creating local fallback..." "WARNING"
                                # Create a minimal working configuration as last resort
                                $minimalConfig = @"
Port 22
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
Match Group administrators
       AuthorizedKeysFile C:/ProgramData/ssh/administrators_authorized_keys
PasswordAuthentication no
LogLevel INFO
Subsystem sftp sftp-server.exe
"@
                                $minimalConfig | Out-File -FilePath $sshdConfigPath -Encoding UTF8 -Force
                                Write-Log "Created local minimal SSH configuration" "SUCCESS"
                            }
                        }
                    } catch {
                        Write-Log "Failed to test SSH configuration: $($_.Exception.Message)" "WARNING"
                    }
                } else {
                    Write-Log "SSH executable not found, configuration applied but cannot test" "WARNING"
                }
            } else {
                Write-Log "Failed to download SSH configuration from GitHub, creating local configuration..." "WARNING"
                # Fallback to local configuration if download fails
                $localSshConfig = @"
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
"@
                $localSshConfig | Out-File -FilePath $sshdConfigPath -Encoding UTF8 -Force
                Write-Log "Created local SSH configuration as fallback" "SUCCESS"
            }
            
            # Configure PowerShell as default shell (using registry method)
            Write-Log "Configuring PowerShell as default SSH shell..."
            try {
                # Ensure the OpenSSH registry key exists
                if (-not (Test-Path "HKLM:\SOFTWARE\OpenSSH")) {
                    New-Item -Path "HKLM:\SOFTWARE\OpenSSH" -Force | Out-Null
                }
                
                # Set PowerShell as default shell
                Set-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Force
                Write-Log "PowerShell configured as default SSH shell" "SUCCESS"
            } catch {
                Write-Log "Failed to configure PowerShell as default shell: $($_.Exception.Message)" "WARNING"
            }
            
            # Restart SSH service to apply new configuration
            if ($serviceFound -and $sshServiceName) {
                try {
                    Restart-Service -Name $sshServiceName
                    Write-Log "SSH service '$sshServiceName' restarted with new configuration" "SUCCESS"
                    
                    # Verify SSH service is running after restart
                    Start-Sleep -Seconds 2
                    $sshServiceStatus = Get-Service -Name $sshServiceName
                    if ($sshServiceStatus.Status -eq "Running") {
                        Write-Log "SSH service is running successfully" "SUCCESS"
                    } else {
                        Write-Log "SSH service status after restart: $($sshServiceStatus.Status)" "WARNING"
                    }
                } catch {
                    Write-Log "Failed to restart SSH service '$sshServiceName': $($_.Exception.Message)" "WARNING"
                    Write-Log "Attempting to stop and start the service instead..." "INFO"
                    try {
                        Stop-Service -Name $sshServiceName -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 2
                        Start-Service -Name $sshServiceName
                        Write-Log "SSH service '$sshServiceName' stopped and started successfully" "SUCCESS"
                    } catch {
                        Write-Log "Failed to stop/start SSH service: $($_.Exception.Message)" "ERROR"
                    }
                }
            } else {
                Write-Log "Cannot restart SSH service - service name not determined" "WARNING"
            }
            
            Write-Log "OpenSSH Server installed and configured successfully" "SUCCESS"
        }
    } catch {
        Write-Log "Failed to configure OpenSSH: $($_.Exception.Message)" "ERROR"
        throw
    }

    # Step 4: Install CloudBase-Init (if not skipped)
    if (-not $SkipCloudbaseInit) {
        Write-Log "Checking CloudBase-Init installation..."
        try {
            $cloudbaseInstallPath = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init"
            $cloudbaseExecutable = "$cloudbaseInstallPath\Python\Scripts\cloudbase-init.exe"
            $cloudbaseConfigPath = "$cloudbaseInstallPath\conf\cloudbase-init.conf"
            
            # Download CloudBase-Init configuration from GitHub
            Write-Log "Downloading CloudBase-Init configuration from GitHub..."
            $cloudbaseConfigUrl = "https://raw.githubusercontent.com/qovert/proxmox-dc/main/configs/cloudbase-init.conf"
            $tempCloudbaseConfig = "$env:TEMP\cloudbase-init.conf"
            
            # Function to create CloudBase-Init configuration
            function Set-CloudbaseConfig {
                param($ConfigPath, $ConfigSource, $IsUrl = $false)
                
                if ($IsUrl) {
                    if (Get-FileFromUrl -Url $ConfigSource -OutputPath $tempCloudbaseConfig) {
                        Copy-Item -Path $tempCloudbaseConfig -Destination $ConfigPath -Force
                        Write-Log "CloudBase-Init configuration downloaded and applied from GitHub" "SUCCESS"
                        return $true
                    } else {
                        Write-Log "Failed to download CloudBase-Init configuration from GitHub" "WARNING"
                        return $false
                    }
                } else {
                    # Local fallback configuration
                    $localConfig = @"
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
                    $localConfig | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force
                    Write-Log "CloudBase-Init configuration created locally as fallback" "SUCCESS"
                    return $true
                }
            }
            
            # Check if CloudBase-Init is already installed
            if (Test-Path $cloudbaseInstallPath) {
                if (Test-Path $cloudbaseExecutable) {
                    Write-Log "CloudBase-Init is already installed" "SUCCESS"
                    
                    # Ensure configuration is properly set up
                    if (-not (Test-Path $cloudbaseConfigPath)) {
                        Write-Log "CloudBase-Init configuration missing, downloading from GitHub..." "WARNING"
                        if (-not (Set-CloudbaseConfig -ConfigPath $cloudbaseConfigPath -ConfigSource $cloudbaseConfigUrl -IsUrl $true)) {
                            # Fallback to local configuration if download fails
                            Set-CloudbaseConfig -ConfigPath $cloudbaseConfigPath -ConfigSource "" -IsUrl $false
                        }
                    } else {
                        Write-Log "CloudBase-Init configuration already exists" "SUCCESS"
                    }
                } else {
                    Write-Log "CloudBase-Init directory found but executable missing, reinstalling..." "WARNING"
                    throw "CloudBase-Init incomplete installation"
                }
            } else {
                Write-Log "CloudBase-Init not found, installing..."
                
                $cloudbaseUrl = "https://cloudbase.it/downloads/CloudbaseInitSetup_1_1_4_x64.msi"
                $cloudbaseInstaller = "$env:TEMP\CloudbaseInit.msi"
                
                if (Get-FileFromUrl -Url $cloudbaseUrl -OutputPath $cloudbaseInstaller) {
                    if (Install-MsiPackage -InstallerPath $cloudbaseInstaller -PackageName "CloudBase-Init" -Arguments @("/quiet", "/qn")) {
                        # Download and configure CloudBase-Init from GitHub
                        if (-not (Set-CloudbaseConfig -ConfigPath $cloudbaseConfigPath -ConfigSource $cloudbaseConfigUrl -IsUrl $true)) {
                            # Fallback to local configuration if download fails
                            Set-CloudbaseConfig -ConfigPath $cloudbaseConfigPath -ConfigSource "" -IsUrl $false
                        }
                        Write-Log "CloudBase-Init installed and configured successfully" "SUCCESS"
                    }
                }
            }
        } catch {
            Write-Log "Failed to install/verify CloudBase-Init: $($_.Exception.Message)" "WARNING"
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
        try {
            powercfg -h off
            Write-Log "Hibernation disabled successfully"
        } catch {
            Write-Log "Failed to disable hibernation: $($_.Exception.Message)" "WARNING"
        }
        
        # Disable automatic managed page file using registry method (more reliable than WMI)
        try {
            Write-Log "Disabling automatic managed page file..."
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "PagingFiles" -Value ""
            Write-Log "Page file configuration updated via registry" "SUCCESS"
        } catch {
            Write-Log "Failed to disable page file via registry, trying WMI method..." "WARNING"
            
            # Fallback to WMI method with better error handling
            try {
                $cs = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
                if ($cs.AutomaticManagedPagefile) {
                    $cs.AutomaticManagedPagefile = $false
                    $result = $cs.Put()
                    if ($result.ReturnValue -eq 0) {
                        Write-Log "Automatic managed page file disabled via WMI" "SUCCESS"
                    } else {
                        Write-Log "WMI Put operation returned error code: $($result.ReturnValue)" "WARNING"
                    }
                } else {
                    Write-Log "Automatic managed page file already disabled" "SUCCESS"
                }
                
                # Remove existing page file settings
                $pf = Get-WmiObject -Class Win32_PageFileSetting -ErrorAction SilentlyContinue
                if ($pf) {
                    foreach ($pageFile in $pf) {
                        try {
                            $pageFile.Delete()
                            Write-Log "Removed page file: $($pageFile.Name)" "SUCCESS"
                        } catch {
                            Write-Log "Failed to remove page file $($pageFile.Name): $($_.Exception.Message)" "WARNING"
                        }
                    }
                }
            } catch {
                Write-Log "Failed to configure page file via WMI: $($_.Exception.Message)" "WARNING"
                Write-Log "Page file configuration will be handled during Sysprep" "INFO"
            }
        }
        
        Write-Log "System cleanup completed successfully" "SUCCESS"
    } catch {
        Write-Log "Failed during system cleanup: $($_.Exception.Message)" "WARNING"
    }

    # Step 8: Sysprep (if not skipped)
    if (-not $SkipSysprep) {
        Write-Log "Running comprehensive Sysprep..." "SUCCESS"
        Write-Log "The system will shut down after Sysprep completes."
        Write-Log "After shutdown, convert the VM to a template in Proxmox."
        
        # Use the comprehensive sysprep script instead of basic command
        $sysprepScript = Join-Path $PSScriptRoot "run-sysprep.ps1"
        if (Test-Path $sysprepScript) {
            Write-Log "Using comprehensive sysprep script: $sysprepScript"
            PowerShell.exe -ExecutionPolicy Bypass -File $sysprepScript
        } else {
            Write-Log "Sysprep script not found, using basic sysprep command" "WARNING"
            Start-Sleep -Seconds 5
            C:\Windows\System32\Sysprep\sysprep.exe /generalize /oobe /shutdown
        }
    } else {
        Write-Log "Skipping Sysprep as requested" "WARNING"
        Write-Log "Template preparation completed successfully!" "SUCCESS"
        Write-Log "Remember to run comprehensive Sysprep using run-sysprep.ps1 before converting to template."
    }

} catch {
    Write-Log "Template preparation failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
