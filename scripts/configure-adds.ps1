# configure-adds.ps1
# Configure Active Directory Domain Services
# This script installs and configures AD DS for Windows Server 2025

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    
    [Parameter(Mandatory=$true)]
    [SecureString]$SafeModePassword,
    
    [Parameter(Mandatory=$true)]
    [string]$IsPrimary = "false",
    
    [Parameter(Mandatory=$false)]
    [string]$PrimaryDcIp = ""
)

# Function to log messages
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message" -ForegroundColor Green
}

# Function to handle errors
function Write-ErrorLog {
    param([string]$ErrorMessage)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] ERROR: $ErrorMessage" -ForegroundColor Red
    exit 1
}

try {
    Write-Log "Starting Active Directory Domain Services configuration..."
    Write-Log "Domain: $DomainName"
    Write-Log "Is Primary DC: $IsPrimary"
    
    # Use the already secure password
    $securePassword = $SafeModePassword
    
    # Import required modules
    Write-Log "Importing required PowerShell modules..."
    Import-Module ADDSDeployment
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue
    
    if ($IsPrimary -eq "true") {
        Write-Log "Configuring as Primary Domain Controller (First DC in forest)..."
        
        # Install AD DS Forest
        Write-Log "Installing Active Directory Forest..."
        $forestParams = @{
            DomainName                    = $DomainName
            DomainNetbiosName            = $DomainName.Split('.')[0].ToUpper()
            SafeModeAdministratorPassword = $securePassword
            InstallDns                   = $true
            CreateDnsDelegation          = $false
            DatabasePath                 = "D:\NTDS"
            LogPath                      = "D:\Logs"
            SysvolPath                   = "D:\SYSVOL"
            DomainMode                   = "WinThreshold"
            ForestMode                   = "WinThreshold"
            NoRebootOnCompletion         = $true
            Force                        = $true
            Confirm                      = $false
        }
        
        Install-ADDSForest @forestParams
        
        Write-Log "Primary Domain Controller installation completed"
        
    } else {
        Write-Log "Configuring as Additional Domain Controller..."
        
        # Wait for primary DC to be available
        Write-Log "Waiting for primary DC ($PrimaryDcIp) to be available..."
        do {
            Start-Sleep -Seconds 30
            $ping = Test-Connection -ComputerName $PrimaryDcIp -Count 1 -Quiet
            if (-not $ping) {
                Write-Log "Primary DC not yet available, waiting..."
            }
        } while (-not $ping)
        
        # Test LDAP connectivity to primary DC
        Write-Log "Testing LDAP connectivity to primary DC..."
        do {
            Start-Sleep -Seconds 10
            try {
                $ldapTest = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$PrimaryDcIp")
                $ldapTest.RefreshCache()
                $ldapAvailable = $true
                Write-Log "LDAP connectivity confirmed"
            } catch {
                $ldapAvailable = $false
                Write-Log "LDAP not yet available, waiting..."
            }
        } while (-not $ldapAvailable)
        
        # Get domain administrator credentials
        Write-Log "Configuring domain administrator credentials..."
        $domainAdmin = "$($DomainName.Split('.')[0].ToUpper())\Administrator"
        $domainPassword = ConvertTo-SecureString -String $env:ADMIN_PASSWORD -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($domainAdmin, $domainPassword)
        
        # Install additional domain controller
        Write-Log "Installing Additional Domain Controller..."
        $dcParams = @{
            DomainName                    = $DomainName
            SafeModeAdministratorPassword = $securePassword
            Credential                   = $credential
            InstallDns                   = $true
            DatabasePath                 = "D:\NTDS"
            LogPath                      = "D:\Logs"
            SysvolPath                   = "D:\SYSVOL"
            NoRebootOnCompletion         = $true
            Force                        = $true
            Confirm                      = $false
        }
        
        Install-ADDSDomainController @dcParams
        
        Write-Log "Additional Domain Controller installation completed"
    }
    
    # Configure DNS settings
    Write-Log "Configuring DNS settings..."
    $dnsServerSettings = @{
        ComputerName = $env:COMPUTERNAME
        ForwardingTimeout = 5
        EnableDnsSec = $true
        EnableDnsSecValidation = $true
    }
    
    try {
        # Configure DNS forwarders (will be set by configure-dns.ps1)
        Write-Log "DNS forwarders will be configured by separate script"
        
        # Configure DNS zones
        Write-Log "Configuring DNS zones..."
        
        # Enable DNS scavenging
        Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval 7.00:00:00 -RefreshInterval 7.00:00:00 -NoRefreshInterval 7.00:00:00
        
        # Configure reverse lookup zones
        $networkId = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*"}).IPAddress
        if ($networkId) {
            $networkSegment = ($networkId -split '\.')[0..2] -join '.'
            $reverseLookupZone = "$($networkSegment.Split('.')[2]).$($networkSegment.Split('.')[1]).$($networkSegment.Split('.')[0]).in-addr.arpa"
            
            try {
                Add-DnsServerPrimaryZone -Name $reverseLookupZone -ReplicationScope "Forest" -DynamicUpdate "Secure"
                Write-Log "Created reverse lookup zone: $reverseLookupZone"
            } catch {
                Write-Log "Warning: Could not create reverse lookup zone: $reverseLookupZone"
            }
        }
        
    } catch {
        Write-Log "Warning: Some DNS configuration steps failed: $($_.Exception.Message)"
    }
    
    # Configure time synchronization
    Write-Log "Configuring time synchronization..."
    if ($IsPrimary -eq "true") {
        # Configure primary DC as time source
        w32tm /config /manualpeerlist:"time.windows.com,0x8 pool.ntp.org,0x8" /syncfromflags:manual /reliable:yes /update
        w32tm /config /update
        Restart-Service w32time
        w32tm /resync
        Write-Log "Configured primary DC as authoritative time source"
    } else {
        # Configure additional DC to sync with primary
        w32tm /config /syncfromflags:domhier /update
        Restart-Service w32time
        w32tm /resync
        Write-Log "Configured additional DC to sync with domain hierarchy"
    }
    
    # Configure Group Policy
    Write-Log "Configuring Group Policy settings..."
    try {
        if ($IsPrimary -eq "true") {
            # Import default Group Policy templates
            Write-Log "Importing Group Policy templates..."
            
            # Create custom GPO for server hardening
            $gpoName = "Domain Controllers Security Policy"
            try {
                Import-Module GroupPolicy
                $gpo = New-GPO -Name $gpoName -Comment "Security policy for domain controllers"
                $gpo | New-GPLink -Target "OU=Domain Controllers,$((Get-ADDomain).DistinguishedName)"
                Write-Log "Created GPO: $gpoName"
            } catch {
                Write-Log "Warning: Could not create custom GPO: $($_.Exception.Message)"
            }
        }
    } catch {
        Write-Log "Warning: Group Policy configuration failed: $($_.Exception.Message)"
    }
    
    # Configure audit policies
    Write-Log "Configuring audit policies..."
    $auditPolicies = @(
        "auditpol /set /category:`"Account Logon`" /success:enable /failure:enable",
        "auditpol /set /category:`"Account Management`" /success:enable /failure:enable",
        "auditpol /set /category:`"Directory Service Access`" /success:enable /failure:enable",
        "auditpol /set /category:`"Logon/Logoff`" /success:enable /failure:enable",
        "auditpol /set /category:`"Object Access`" /success:enable /failure:enable",
        "auditpol /set /category:`"Policy Change`" /success:enable /failure:enable",
        "auditpol /set /category:`"Privilege Use`" /success:enable /failure:enable",
        "auditpol /set /category:`"System`" /success:enable /failure:enable"
    )
    
    foreach ($policy in $auditPolicies) {
        try {
            Invoke-Expression $policy
            Write-Log "Applied audit policy: $policy"
        } catch {
            Write-Log "Warning: Could not apply audit policy: $policy"
        }
    }
    
    # Configure security settings
    Write-Log "Configuring security settings..."
    try {
        # Configure Kerberos settings
        $kerberosSettings = @{
            "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\Kerberos\Parameters" = @{
                "MaxTokenSize" = 65535
                "MaxPacketSize" = 65535
            }
        }
        
        foreach ($regPath in $kerberosSettings.Keys) {
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            foreach ($setting in $kerberosSettings[$regPath].GetEnumerator()) {
                Set-ItemProperty -Path $regPath -Name $setting.Key -Value $setting.Value -Type DWORD
                Write-Log "Set Kerberos setting: $($setting.Key) = $($setting.Value)"
            }
        }
        
        # Configure LDAP settings
        $ldapSettings = @{
            "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" = @{
                "LDAPServerIntegrity" = 2  # Require signing
                "RequireSSLForADSI" = 1    # Require SSL for ADSI
            }
        }
        
        foreach ($regPath in $ldapSettings.Keys) {
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            foreach ($setting in $ldapSettings[$regPath].GetEnumerator()) {
                Set-ItemProperty -Path $regPath -Name $setting.Key -Value $setting.Value -Type DWORD
                Write-Log "Set LDAP setting: $($setting.Key) = $($setting.Value)"
            }
        }
        
    } catch {
        Write-Log "Warning: Some security settings could not be applied: $($_.Exception.Message)"
    }
    
    # Configure event log settings for AD
    Write-Log "Configuring Active Directory event logs..."
    $adEventLogs = @(
        "Directory Service",
        "DFS Replication",
        "DNS Server"
    )
    
    foreach ($logName in $adEventLogs) {
        try {
            $log = Get-EventLog -List | Where-Object {$_.Log -eq $logName}
            if ($log) {
                Limit-EventLog -LogName $logName -MaximumSize 104857600 -OverflowAction OverwriteAsNeeded
                Write-Log "Configured event log: $logName"
            }
        } catch {
            Write-Log "Warning: Could not configure event log: $logName"
        }
    }
    
    # Create service accounts OU structure (if primary DC)
    if ($IsPrimary -eq "true") {
        Write-Log "Creating organizational unit structure..."
        Start-Sleep -Seconds 30  # Wait for AD to be fully ready
        
        try {
            $domain = Get-ADDomain
            $domainDN = $domain.DistinguishedName
            
            $organizationalUnits = @(
                "Servers",
                "Workstations", 
                "Users",
                "Groups",
                "Service Accounts"
            )
            
            foreach ($ou in $organizationalUnits) {
                try {
                    $ouDN = "OU=$ou,$domainDN"
                    New-ADOrganizationalUnit -Name $ou -Path $domainDN -ProtectedFromAccidentalDeletion $true
                    Write-Log "Created OU: $ou"
                } catch {
                    Write-Log "Warning: Could not create OU: $ou - $($_.Exception.Message)"
                }
            }
            
        } catch {
            Write-Log "Warning: Could not create OU structure: $($_.Exception.Message)"
        }
    }
    
    # Configure automatic services startup
    Write-Log "Configuring service startup types..."
    $services = @(
        @{Name="NTDS"; StartupType="Automatic"},
        @{Name="DNS"; StartupType="Automatic"},
        @{Name="Netlogon"; StartupType="Automatic"},
        @{Name="KDC"; StartupType="Automatic"},
        @{Name="ISFMP"; StartupType="Automatic"},
        @{Name="W32Time"; StartupType="Automatic"}
    )
    
    foreach ($service in $services) {
        try {
            Set-Service -Name $service.Name -StartupType $service.StartupType
            Start-Service -Name $service.Name -ErrorAction SilentlyContinue
            Write-Log "Configured service: $($service.Name) - $($service.StartupType)"
        } catch {
            Write-Log "Warning: Could not configure service: $($service.Name)"
        }
    }
    
    # Disable automatic logon
    Write-Log "Disabling automatic logon..."
    $AutoLogonPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
    Set-ItemProperty -Path $AutoLogonPath -Name "AutoAdminLogon" -Value "0"
    Remove-ItemProperty -Path $AutoLogonPath -Name "DefaultPassword" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $AutoLogonPath -Name "AutoLogonCount" -ErrorAction SilentlyContinue
    
    Write-Log "Active Directory Domain Services configuration completed successfully"
    Write-Log "System will reboot to complete the configuration"
    
    # Schedule reboot
    shutdown /r /t 60 /c "Rebooting to complete Active Directory configuration"
    
} catch {
    Write-ErrorLog "AD DS configuration failed: $($_.Exception.Message)"
}
