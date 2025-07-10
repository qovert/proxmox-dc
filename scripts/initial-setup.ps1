# initial-setup.ps1
# Initial Windows Server 2025 setup and configuration for Active Directory Domain Controller
# This script performs initial system configuration before AD DS installation

param(
    [Parameter(Mandatory=$true)]
    [string]$ComputerName,
    
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    
    [Parameter(Mandatory=$true)]
    [string]$IsPrimary = "false"
)

# Function to log messages
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor Green
}

# Function to handle errors
function Handle-Error {
    param([string]$ErrorMessage)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] ERROR: $ErrorMessage" -ForegroundColor Red
    exit 1
}

try {
    Write-Log "Starting initial setup for $ComputerName..."
    
    # Set execution policy
    Write-Log "Setting PowerShell execution policy..."
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force
    
    # Configure PowerShell for automation
    Write-Log "Configuring PowerShell for automation..."
    Enable-PSRemoting -Force
    Set-Item wsman:\localhost\client\trustedhosts * -Force
    
    # Set timezone to UTC (adjust as needed)
    Write-Log "Setting timezone..."
    Set-TimeZone -Id "UTC"
    
    # Configure Windows Update settings
    Write-Log "Configuring Windows Update..."
    $AutoUpdatePath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    if (-not (Test-Path $AutoUpdatePath)) {
        New-Item -Path $AutoUpdatePath -Force | Out-Null
    }
    Set-ItemProperty -Path $AutoUpdatePath -Name "NoAutoUpdate" -Value 1
    
    # Disable IE Enhanced Security Configuration
    Write-Log "Disabling IE Enhanced Security Configuration..."
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
    Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
    
    # Configure network adapters
    Write-Log "Configuring network adapters..."
    $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
    foreach ($adapter in $adapters) {
        # Disable IPv6 if not needed
        Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6
        
        # Configure DNS settings (will be updated after AD installation)
        Write-Log "Configuring DNS for adapter $($adapter.Name)..."
        if ($IsPrimary -eq "true") {
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses "127.0.0.1"
        }
    }
    
    # Configure Windows Firewall
    Write-Log "Configuring Windows Firewall..."
    # Enable firewall rules for Active Directory
    $ADFirewallRules = @(
        "Active Directory Domain Controller (RPC)",
        "Active Directory Domain Controller (RPC-EPMAP)",
        "Active Directory Domain Controller - LDAP (UDP-In)",
        "Active Directory Domain Controller - LDAP (TCP-In)",
        "Active Directory Domain Controller - Secure LDAP (TCP-In)",
        "Active Directory Domain Controller - SAM/LSA (NP-UDP-In)",
        "Active Directory Domain Controller - SAM/LSA (NP-TCP-In)",
        "Active Directory Domain Controller - NetLogon (NP-In)",
        "Active Directory Domain Controller (RPC Dynamic)",
        "Active Directory Web Services (TCP-In)",
        "DFS Replication (RPC-In)",
        "DNS (UDP, Incoming)",
        "DNS (TCP, Incoming)",
        "Kerberos Key Distribution Center (TCP-In)",
        "Kerberos Key Distribution Center (UDP-In)",
        "RPC Endpoint Mapper (TCP, Incoming)",
        "Windows Time (NTP-UDP-In)"
    )
    
    foreach ($rule in $ADFirewallRules) {
        try {
            Enable-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue
            Write-Log "Enabled firewall rule: $rule"
        } catch {
            Write-Log "Warning: Could not enable firewall rule: $rule"
        }
    }
    
    # Configure Remote Desktop
    Write-Log "Configuring Remote Desktop..."
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0
    Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
    
    # Configure WinRM for HTTPS
    Write-Log "Configuring WinRM for HTTPS..."
    $cert = New-SelfSignedCertificate -DnsName $ComputerName -CertStoreLocation Cert:\LocalMachine\My
    $certThumbprint = $cert.Thumbprint
    New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -CertificateThumbprint $certThumbprint -Force
    New-NetFirewallRule -DisplayName "WinRM HTTPS" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow
    
    # Configure services
    Write-Log "Configuring services..."
    $services = @(
        @{Name="W32Time"; StartupType="Automatic"},
        @{Name="Netlogon"; StartupType="Manual"},
        @{Name="DNS"; StartupType="Manual"},
        @{Name="DHCP"; StartupType="Manual"}
    )
    
    foreach ($service in $services) {
        try {
            Set-Service -Name $service.Name -StartupType $service.StartupType -ErrorAction SilentlyContinue
            Write-Log "Configured service: $($service.Name) - $($service.StartupType)"
        } catch {
            Write-Log "Warning: Could not configure service: $($service.Name)"
        }
    }
    
    # Create directories for AD database and logs
    Write-Log "Creating directories for AD database and logs..."
    $directories = @(
        "C:\Windows\NTDS",
        "C:\Windows\SYSVOL",
        "D:\NTDS",
        "D:\SYSVOL",
        "D:\Logs"
    )
    
    foreach ($dir in $directories) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Log "Created directory: $dir"
        }
    }
    
    # Set system performance options
    Write-Log "Configuring system performance options..."
    # Set to adjust for best performance of background services
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl" -Name "Win32PrioritySeparation" -Value 24
    
    # Configure paging file
    Write-Log "Configuring paging file..."
    $cs = Get-WmiObject -Class Win32_ComputerSystem
    $physicalMemory = [math]::Round($cs.TotalPhysicalMemory / 1GB)
    $pagingFileSize = [math]::Max(2048, $physicalMemory * 1024)  # At least 2GB or 1x RAM
    
    $pagefileset = Get-WmiObject -Class Win32_PageFileSetting
    if ($pagefileset) {
        $pagefileset.Delete()
    }
    $pagefileset = ([WmiClass]'Win32_PageFileSetting').CreateInstance()
    $pagefileset.Name = "C:\pagefile.sys"
    $pagefileset.InitialSize = $pagingFileSize
    $pagefileset.MaximumSize = $pagingFileSize
    $pagefileset.Put() | Out-Null
    
    # Configure registry settings for AD performance
    Write-Log "Configuring registry settings for AD performance..."
    $registrySettings = @(
        @{Path="HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters"; Name="Database log files path"; Value="D:\Logs"},
        @{Path="HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters"; Name="DSA Database file"; Value="D:\NTDS\ntds.dit"},
        @{Path="HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"; Name="RequireSignOrSeal"; Value=1; Type="DWORD"},
        @{Path="HKLM:\SYSTEM\CurrentControlSet\Services\Netlogon\Parameters"; Name="RequireStrongKey"; Value=1; Type="DWORD"}
    )
    
    foreach ($setting in $registrySettings) {
        try {
            if (-not (Test-Path $setting.Path)) {
                New-Item -Path $setting.Path -Force | Out-Null
            }
            $type = if ($setting.Type) { $setting.Type } else { "String" }
            Set-ItemProperty -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $type
            Write-Log "Set registry: $($setting.Path)\$($setting.Name) = $($setting.Value)"
        } catch {
            Write-Log "Warning: Could not set registry setting: $($setting.Path)\$($setting.Name)"
        }
    }
    
    # Configure Windows Event Logs
    Write-Log "Configuring Windows Event Logs..."
    $eventLogs = @(
        @{LogName="Application"; MaxSize=104857600},  # 100MB
        @{LogName="System"; MaxSize=104857600},       # 100MB
        @{LogName="Security"; MaxSize=209715200},     # 200MB
        @{LogName="Directory Service"; MaxSize=104857600},  # 100MB
        @{LogName="DNS Server"; MaxSize=52428800}     # 50MB
    )
    
    foreach ($log in $eventLogs) {
        try {
            Limit-EventLog -LogName $log.LogName -MaximumSize $log.MaxSize -ErrorAction SilentlyContinue
            Write-Log "Configured event log: $($log.LogName) - Max Size: $($log.MaxSize) bytes"
        } catch {
            Write-Log "Warning: Could not configure event log: $($log.LogName)"
        }
    }
    
    # Install Windows features required for AD DS
    Write-Log "Installing Windows features required for AD DS..."
    $features = @(
        "AD-Domain-Services",
        "DNS",
        "RSAT-AD-Tools",
        "RSAT-DNS-Server",
        "RSAT-DFS-Mgmt-Con",
        "RSAT-File-Services",
        "GPMC",
        "PowerShell-ISE"
    )
    
    foreach ($feature in $features) {
        try {
            $result = Install-WindowsFeature -Name $feature -IncludeManagementTools -ErrorAction SilentlyContinue
            if ($result.Success) {
                Write-Log "Installed feature: $feature"
            } else {
                Write-Log "Warning: Could not install feature: $feature"
            }
        } catch {
            Write-Log "Warning: Error installing feature: $feature"
        }
    }
    
    # Configure scheduled tasks for maintenance
    Write-Log "Creating scheduled tasks for maintenance..."
    
    # Create AD health check task
    $healthCheckAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\health-check.ps1"
    $healthCheckTrigger = New-ScheduledTaskTrigger -Daily -At "06:00"
    $healthCheckPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
    $healthCheckSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -RestartCount 3
    
    try {
        Register-ScheduledTask -TaskName "AD Health Check" -Action $healthCheckAction -Trigger $healthCheckTrigger -Principal $healthCheckPrincipal -Settings $healthCheckSettings -Force
        Write-Log "Created scheduled task: AD Health Check"
    } catch {
        Write-Log "Warning: Could not create AD Health Check scheduled task"
    }
    
    # Rename computer if needed
    if ($env:COMPUTERNAME -ne $ComputerName) {
        Write-Log "Renaming computer from $env:COMPUTERNAME to $ComputerName..."
        Rename-Computer -NewName $ComputerName -Force
        Write-Log "Computer renamed. A restart will be required."
    }
    
    # Configure automatic logon temporarily for domain setup
    Write-Log "Configuring automatic logon for domain setup..."
    $AutoLogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $AutoLogonPath -Name "AutoAdminLogon" -Value "1"
    Set-ItemProperty -Path $AutoLogonPath -Name "DefaultUserName" -Value "Administrator"
    Set-ItemProperty -Path $AutoLogonPath -Name "DefaultPassword" -Value (ConvertTo-SecureString -AsPlainText -Force -String $env:ADMIN_PASSWORD)
    Set-ItemProperty -Path $AutoLogonPath -Name "AutoLogonCount" -Value "3"
    
    Write-Log "Initial setup completed successfully for $ComputerName"
    Write-Log "System is ready for Active Directory Domain Services installation"
    
} catch {
    Handle-Error "Initial setup failed: $($_.Exception.Message)"
}
