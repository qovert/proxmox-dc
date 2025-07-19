<#
.SYNOPSIS
    Prepares a Windows Server 2025 template for Proxmox VE virtualization platform.

.DESCRIPTION
    This comprehensive script automates the preparation of a Windows Server 2025 template
    for Proxmox VE. It installs and configures essential components including:
    - Proxmox Guest Agent (QEMU-GA)
    - Windows Updates
    - PowerShell 7
    - OpenSSH Server with secure configuration
    - CloudBase-Init for cloud-init functionality
    - System optimization and hardening
    - Sysprep for template generalization

    The script is designed to run on a fresh Windows Server 2025 Core installation
    and prepare it for conversion to a Proxmox template.

.PARAMETER SSHPublicKey
    Path to SSH public key file to be added to the Administrator's authorized_keys file for
    passwordless SSH authentication. The file should contain a public key in OpenSSH format.
    Example: "C:\Users\admin\.ssh\id_ed25519.pub" or "~/.ssh/id_ed25519.pub" 

.PARAMETER SkipWindowsUpdates
    Skip the Windows Updates installation phase. Use this switch to save time
    during template preparation if updates will be handled separately.

.PARAMETER SkipCloudbaseInit
    Skip the CloudBase-Init installation and configuration. Use this switch
    if you don't need cloud-init functionality in your template.

.PARAMETER SkipSysprep
    Skip the Sysprep generalization process. Use this switch if you want to
    manually run Sysprep later or perform additional customizations first.

.EXAMPLE
    PS C:\> .\prepare-windows-template.ps1
    
    Run the script with default settings, installing all components and running Sysprep.

.EXAMPLE
    PS C:\> .\prepare-windows-template.ps1 -SSHPublicKey "C:\Users\admin\.ssh\id_ed25519.pub"
    
    Run the script with an SSH public key file for passwordless authentication.

.EXAMPLE
    PS C:\> .\prepare-windows-template.ps1 -SkipWindowsUpdates
    
    Run the script but skip Windows Updates installation to save time.

.EXAMPLE
    PS C:\> .\prepare-windows-template.ps1 -SkipCloudbaseInit -SkipSysprep
    
    Run the script without CloudBase-Init and without Sysprep for manual template preparation.

.EXAMPLE
    PS C:\> .\prepare-windows-template.ps1 -SSHPublicKey "~/.ssh/id_rsa.pub" -SkipWindowsUpdates -SkipSysprep
    
    Run the script with SSH key file, skip Windows Updates, and skip Sysprep for faster development testing.

.NOTES
    Author: Proxmox DC Project
    Version: 1.0
    Requires: PowerShell 5.1 or later, Administrator privileges
    
    Prerequisites:
    - Fresh Windows Server 2025 Core installation
    - Administrator privileges
    - Internet connectivity (for downloads)
    - Proxmox VE environment

    Post-execution steps:
    1. Verify SSH connectivity: ssh Administrator@<VM_IP>
    2. If Sysprep was skipped, run: .\run-sysprep.ps1
    3. Shutdown the VM
    4. Convert VM to template in Proxmox VE
    5. Test template by creating new VMs
    
    SSH Key Requirements:
    - Use standard OpenSSH public key format (ssh-rsa, ssh-ed25519, etc.)
    - Common locations: ~/.ssh/id_ed25519.pub, ~/.ssh/id_rsa.pub
    - Windows paths: C:\Users\<username>\.ssh\id_ed25519.pub

.LINK
    https://github.com/qovert/proxmox-dc
    
.LINK
    https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers
    
.LINK
    https://cloudbase.it/cloudbase-init/
#>

[CmdletBinding()]
param(
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Path to SSH public key file for passwordless authentication"
    )]
    [string]$SSHPublicKey = "",
    
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Skip Windows Updates installation to save time"
    )]
    [switch]$SkipWindowsUpdates = $false,
    
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Skip CloudBase-Init installation and configuration"
    )]
    [switch]$SkipCloudbaseInit = $false,
    
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Skip Sysprep generalization process"
    )]
    [switch]$SkipSysprep = $false
)

# Function to write timestamped log messages
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# Function to display script usage and help
function Show-Help {
    Write-Host "`nWindows Server 2025 Template Preparation Script" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "`nThis script prepares a Windows Server 2025 template for Proxmox VE." -ForegroundColor White
    Write-Host "`nUsage Examples:" -ForegroundColor Yellow
    Write-Host "  .\prepare-windows-template.ps1" -ForegroundColor Cyan
    Write-Host "    - Run with default settings (installs all components)" -ForegroundColor Gray
    Write-Host "`n  .\prepare-windows-template.ps1 -SSHPublicKey `"C:\Users\admin\.ssh\id_ed25519.pub`"" -ForegroundColor Cyan
    Write-Host "    - Include SSH public key file for passwordless authentication" -ForegroundColor Gray
    Write-Host "`n  .\prepare-windows-template.ps1 -SkipWindowsUpdates" -ForegroundColor Cyan
    Write-Host "    - Skip Windows Updates to save time" -ForegroundColor Gray
    Write-Host "`n  .\prepare-windows-template.ps1 -SkipCloudbaseInit -SkipSysprep" -ForegroundColor Cyan
    Write-Host "    - Skip CloudBase-Init and Sysprep for manual preparation" -ForegroundColor Gray
    Write-Host "`nFor detailed help, run: Get-Help .\prepare-windows-template.ps1 -Full" -ForegroundColor Yellow
    Write-Host ""
}

function Test-InternetConnection {
    <#
    .SYNOPSIS
        Tests internet connectivity by attempting to reach a reliable endpoint.
    .DESCRIPTION
        Performs a simple HTTP request to Google to verify internet connectivity.
        Used to determine if downloads and updates can be performed.
    .EXAMPLE
        PS C:\> Test-InternetConnection
        Returns $true if internet is available, $false otherwise.
    #>
    try {
        $null = Invoke-WebRequest -Uri "https://www.google.com" -TimeoutSec 10 -UseBasicParsing
        return $true
    } catch {
        return $false
    }
}

function Install-MsiPackage {
    <#
    .SYNOPSIS
        Installs an MSI package using msiexec with proper error handling.
    .DESCRIPTION
        Provides a standardized way to install MSI packages with logging and error handling.
        Supports custom arguments and wait times for installation completion.
    .PARAMETER InstallerPath
        Full path to the MSI installer file.
    .PARAMETER PackageName
        Friendly name of the package for logging purposes.
    .PARAMETER Arguments
        Array of arguments to pass to msiexec. Defaults to "/quiet".
    .PARAMETER WaitSeconds
        Seconds to wait after installation completion. Defaults to 5.
    .EXAMPLE
        PS C:\> Install-MsiPackage -InstallerPath "C:\temp\package.msi" -PackageName "My Package"
        Installs the MSI package with default quiet installation.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,
        
        [Parameter(Mandatory = $true)]
        [string]$PackageName,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Arguments = @("/quiet"),
        
        [Parameter(Mandatory = $false)]
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

function Add-ToPath {
    <#
    .SYNOPSIS
        Adds a directory to the system PATH environment variable.
    .DESCRIPTION
        Safely adds a directory to the machine-level PATH environment variable
        if it's not already present. Prevents PATH duplication.
    .PARAMETER PathToAdd
        Directory path to add to the PATH environment variable.
    .PARAMETER Description
        Friendly description of the path being added for logging.
    .EXAMPLE
        PS C:\> Add-ToPath -PathToAdd "C:\Program Files\MyApp" -Description "My Application"
        Adds the specified path to the system PATH.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathToAdd,
        
        [Parameter(Mandatory = $false)]
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

function Set-ServiceConfiguration {
    <#
    .SYNOPSIS
        Configures and starts a Windows service with proper error handling.
    .DESCRIPTION
        Provides a standardized way to configure service startup type and start
        services with comprehensive logging and error handling.
    .PARAMETER ServiceName
        Name of the Windows service to configure.
    .PARAMETER StartupType
        Service startup type (Automatic, Manual, Disabled). Defaults to "Automatic".
    .PARAMETER StartService
        Whether to start the service after configuration. Defaults to $true.
    .PARAMETER Description
        Friendly description of the service for logging purposes.
    .EXAMPLE
        PS C:\> Set-ServiceConfiguration -ServiceName "sshd" -Description "SSH Server"
        Configures the SSH service to start automatically and starts it.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Automatic", "Manual", "Disabled")]
        [string]$StartupType = "Automatic",
        
        [Parameter(Mandatory = $false)]
        [bool]$StartService = $true,
        
        [Parameter(Mandatory = $false)]
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

function Set-SSHPublicKey {
    <#
    .SYNOPSIS
        Adds an SSH public key from a file to the Administrator's authorized_keys file.
    .DESCRIPTION
        Safely reads an SSH public key from a file and adds it to the authorized_keys file 
        for passwordless SSH authentication. Creates the file if it doesn't exist and sets proper permissions.
    .PARAMETER PublicKeyPath
        Path to the SSH public key file in OpenSSH format (e.g., "C:\Users\admin\.ssh\id_ed25519.pub").
    .PARAMETER AuthorizedKeysPath
        Path to the authorized_keys file. Defaults to the Windows OpenSSH location.
    .EXAMPLE
        PS C:\> Set-SSHPublicKey -PublicKeyPath "C:\Users\admin\.ssh\id_ed25519.pub"
        Reads the SSH public key from the file and adds it to the authorized_keys file.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [string]$PublicKeyPath,
        
        [Parameter(Mandatory = $false)]
        [string]$AuthorizedKeysPath = "C:\ProgramData\ssh\administrators_authorized_keys"
    )
    
    if (-not $PublicKeyPath) {
        return $true
    }
    
    # Expand any environment variables or relative paths
    $PublicKeyPath = [System.Environment]::ExpandEnvironmentVariables($PublicKeyPath)
    if ($PublicKeyPath.StartsWith("~/")) {
        if ($env:USERPROFILE) {
            # Windows
            $PublicKeyPath = $PublicKeyPath.Replace("~/", "$env:USERPROFILE\")
        } elseif ($env:HOME) {
            # Linux/Unix
            $PublicKeyPath = $PublicKeyPath.Replace("~/", "$env:HOME/")
        }
    }
    
    # Check if the public key file exists
    if (-not (Test-Path $PublicKeyPath)) {
        Write-Log "SSH public key file not found: $PublicKeyPath" "ERROR"
        return $false
    }
    
    # Read the public key from the file
    try {
        $publicKeyContent = Get-Content -Path $PublicKeyPath -Raw -ErrorAction Stop
        $publicKeyContent = $publicKeyContent.Trim()
        
        # Validate the key format
        $validKeyTypes = @('ssh-rsa', 'ssh-ed25519', 'ecdsa-sha2-nistp256', 'ecdsa-sha2-nistp384', 'ecdsa-sha2-nistp521')
        $keyValid = $false
        foreach ($keyType in $validKeyTypes) {
            if ($publicKeyContent.StartsWith($keyType)) {
                $keyValid = $true
                break
            }
        }
        
        if (-not $keyValid) {
            Write-Log "Invalid SSH public key format in file: $PublicKeyPath" "ERROR"
            Write-Log "Expected format: 'ssh-rsa AAAAB3...' or 'ssh-ed25519 AAAAB3...'" "ERROR"
            return $false
        }
        
        Write-Log "Successfully read SSH public key from: $PublicKeyPath" "SUCCESS"
        
    } catch {
        Write-Log "Failed to read SSH public key file: $($_.Exception.Message)" "ERROR"
        return $false
    }
    
    try {
        # Ensure the authorized_keys file exists
        if (-not (Test-Path $AuthorizedKeysPath)) {
            # Create the directory if it doesn't exist
            $parentDir = Split-Path -Parent $AuthorizedKeysPath
            if (-not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            
            New-Item -ItemType File -Path $AuthorizedKeysPath -Force | Out-Null
            icacls $AuthorizedKeysPath /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F" | Out-Null
            Write-Log "Created SSH authorized_keys file: $AuthorizedKeysPath" "SUCCESS"
        }
        
        # Check if key already exists
        $existingKeys = Get-Content $AuthorizedKeysPath -ErrorAction SilentlyContinue
        if ($existingKeys -notcontains $publicKeyContent) {
            Add-Content -Path $AuthorizedKeysPath -Value $publicKeyContent
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

function Get-FileFromUrl {
    <#
    .SYNOPSIS
        Downloads a file from a URL with retry logic and error handling.
    .DESCRIPTION
        Provides robust file download functionality with automatic retry on failure.
        Includes proper error handling and logging for download operations.
    .PARAMETER Url
        URL of the file to download.
    .PARAMETER OutputPath
        Local path where the downloaded file should be saved.
    .PARAMETER MaxRetries
        Maximum number of download attempts. Defaults to 3.
    .EXAMPLE
        PS C:\> Get-FileFromUrl -Url "https://example.com/file.msi" -OutputPath "C:\temp\file.msi"
        Downloads the file with default retry logic.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $false)]
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

# Script initialization and validation
Write-Host "`nWindows Server 2025 Template Preparation Script" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green

# Check if running as administrator
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`nERROR: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again.`n" -ForegroundColor Yellow
    Show-Help
    exit 1
}

# Display script parameters
Write-Log "Starting Windows Server 2025 Template Preparation" "SUCCESS"
Write-Log "Script parameters:" "INFO"
Write-Log "  - SSH Public Key File: $(if ($SSHPublicKey) { $SSHPublicKey } else { 'Not provided' })" "INFO"
Write-Log "  - Skip Windows Updates: $SkipWindowsUpdates" "INFO"
Write-Log "  - Skip CloudBase-Init: $SkipCloudbaseInit" "INFO"
Write-Log "  - Skip Sysprep: $SkipSysprep" "INFO"

# Validate SSH public key file if provided
if ($SSHPublicKey) {
    # Expand any environment variables or relative paths
    $expandedPath = [System.Environment]::ExpandEnvironmentVariables($SSHPublicKey)
    if ($expandedPath.StartsWith("~/")) {
        if ($env:USERPROFILE) {
            # Windows
            $expandedPath = $expandedPath.Replace("~/", "$env:USERPROFILE\")
        } elseif ($env:HOME) {
            # Linux/Unix
            $expandedPath = $expandedPath.Replace("~/", "$env:HOME/")
        }
    }
    
    if (-not (Test-Path $expandedPath)) {
        Write-Log "WARNING: SSH public key file not found: $expandedPath" "WARNING"
        Write-Log "The script will continue but SSH key-based authentication will not be configured." "WARNING"
    } else {
        Write-Log "SSH public key file found: $expandedPath" "SUCCESS"
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
            Set-SSHPublicKey -PublicKeyPath $SSHPublicKey
        } elseif ($sshService -and (Test-Path $sshdConfigPath)) {
            Write-Log "OpenSSH Server is installed but not running, starting service..." "INFO"
            Write-Log "SSH service status: $($sshService.Status)" "INFO"
            Write-Log "SSH configuration file exists: $sshdConfigPath" "SUCCESS"
            
            try {
                # Configure and start the SSH service using utility function
                if (Set-ServiceConfiguration -ServiceName $sshServiceName -Description "SSH Server") {
                    # Add SSH public key if provided
                    Set-SSHPublicKey -PublicKeyPath $SSHPublicKey
                    
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
            Set-SSHPublicKey -PublicKeyPath $SSHPublicKey
            
            # Download and apply SSH configuration from GitHub if internet is available
            if (Test-InternetConnection) {
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
                                Write-Log "SSH configuration will need to be manually configured" "INFO"
                            }
                        } catch {
                            Write-Log "Failed to test SSH configuration: $($_.Exception.Message)" "WARNING"
                        }
                    } else {
                        Write-Log "SSH executable not found, configuration applied but cannot test" "WARNING"
                    }
                } else {
                    Write-Log "Failed to download SSH configuration from GitHub" "WARNING"
                    Write-Log "SSH configuration will need to be manually configured" "INFO"
                }
            } else {
                Write-Log "No internet connectivity detected - skipping SSH configuration download" "INFO"
                Write-Log "SSH configuration will need to be manually configured after template deployment" "INFO"
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
            
            # Download CloudBase-Init configuration from GitHub if internet is available
            if (Test-InternetConnection) {
                Write-Log "Downloading CloudBase-Init configuration from GitHub..."
                $cloudbaseConfigUrl = "https://raw.githubusercontent.com/qovert/proxmox-dc/main/configs/cloudbase-init.conf"
                $tempCloudbaseConfig = "$env:TEMP\cloudbase-init.conf"
                
                # Function to download CloudBase-Init configuration
                function Get-CloudbaseConfig {
                    param($ConfigPath, $ConfigUrl)
                    
                    if (Get-FileFromUrl -Url $ConfigUrl -OutputPath $tempCloudbaseConfig) {
                        Copy-Item -Path $tempCloudbaseConfig -Destination $ConfigPath -Force
                        Write-Log "CloudBase-Init configuration downloaded and applied from GitHub" "SUCCESS"
                        return $true
                    } else {
                        Write-Log "Failed to download CloudBase-Init configuration from GitHub" "WARNING"
                        return $false
                    }
                }
            } else {
                Write-Log "No internet connectivity detected - skipping CloudBase-Init configuration download" "INFO"
            }
            
            # Check if CloudBase-Init is already installed
            if (Test-Path $cloudbaseInstallPath) {
                if (Test-Path $cloudbaseExecutable) {
                    Write-Log "CloudBase-Init is already installed" "SUCCESS"
                    
                    # Ensure configuration is properly set up if internet is available
                    if (-not (Test-Path $cloudbaseConfigPath)) {
                        if (Test-InternetConnection) {
                            Write-Log "CloudBase-Init configuration missing, downloading from GitHub..." "WARNING"
                            Get-CloudbaseConfig -ConfigPath $cloudbaseConfigPath -ConfigUrl $cloudbaseConfigUrl
                        } else {
                            Write-Log "CloudBase-Init configuration missing and no internet connectivity" "WARNING"
                            Write-Log "CloudBase-Init configuration will need to be manually configured" "INFO"
                        }
                    } else {
                        Write-Log "CloudBase-Init configuration already exists" "SUCCESS"
                    }
                } else {
                    Write-Log "CloudBase-Init directory found but executable missing, reinstalling..." "WARNING"
                    throw "CloudBase-Init incomplete installation"
                }
            } else {
                if (Test-InternetConnection) {
                    Write-Log "CloudBase-Init not found, installing..."
                    
                    $cloudbaseUrl = "https://cloudbase.it/downloads/CloudbaseInitSetup_1_1_4_x64.msi"
                    $cloudbaseInstaller = "$env:TEMP\CloudbaseInit.msi"
                    
                    if (Get-FileFromUrl -Url $cloudbaseUrl -OutputPath $cloudbaseInstaller) {
                        if (Install-MsiPackage -InstallerPath $cloudbaseInstaller -PackageName "CloudBase-Init" -Arguments @("/quiet", "/qn")) {
                            # Download and configure CloudBase-Init from GitHub
                            Get-CloudbaseConfig -ConfigPath $cloudbaseConfigPath -ConfigUrl $cloudbaseConfigUrl
                            Write-Log "CloudBase-Init installed and configured successfully" "SUCCESS"
                        }
                    }
                } else {
                    Write-Log "No internet connectivity detected - skipping CloudBase-Init installation" "INFO"
                    Write-Log "CloudBase-Init will need to be manually installed and configured" "INFO"
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
        
        # Disable unnecessary services (services that are typically unneeded for server templates)
        $servicesToDisable = @(
            "WSearch",          # Windows Search - not needed for headless servers
            "SysMain",          # Superfetch/Prefetch - not beneficial for VMs
            "Themes",           # Themes service - not needed for Server Core
            "AudioSrv",         # Windows Audio - typically not needed for servers
            "AudioEndpointBuilder", # Audio Endpoint Builder - not needed for servers
            "Audiosrv",         # Windows Audio Service - not needed for servers
            "WbioSrvc",         # Windows Biometric Service - not needed for servers
            "TabletInputService", # Tablet PC Input Service - not needed for servers
            "SCardSvr",         # Smart Card - only needed if using smart cards
            "ScDeviceEnum",     # Smart Card Device Enumeration - not typically needed
            "WerSvc",           # Windows Error Reporting - optional for templates
            "DiagTrack"         # Connected User Experiences and Telemetry - privacy
        )
        
        foreach ($service in $servicesToDisable) {
            try {
                $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
                if ($svc) {
                    Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
                    Write-Log "Disabled service: $service ($($svc.DisplayName))"
                } else {
                    Write-Log "Service $service not found (may not be installed in Server Core)"
                }
            } catch {
                Write-Log "Failed to disable service $service`: $($_.Exception.Message)" "WARNING"
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
        Write-Log "Next steps:" "INFO"
        Write-Log "  1. Test SSH connectivity: ssh Administrator@<VM_IP>" "INFO"
        Write-Log "  2. Run Sysprep manually: .\run-sysprep.ps1" "INFO"
        Write-Log "  3. Shutdown VM after Sysprep completes" "INFO"
        Write-Log "  4. Convert VM to template in Proxmox VE" "INFO"
        Write-Log "  5. Test template by creating new VMs with cloud-init" "INFO"
        Write-Log "Remember to run comprehensive Sysprep using run-sysprep.ps1 before converting to template." "WARNING"
    }

} catch {
    Write-Log "Template preparation failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    Write-Log "For help with this script, run: Get-Help .\prepare-windows-template.ps1 -Full" "INFO"
    Write-Log "Or visit: https://github.com/qovert/proxmox-dc" "INFO"
    exit 1
}
