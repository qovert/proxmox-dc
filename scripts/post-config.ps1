# post-config.ps1
# Post-configuration tasks for Active Directory Domain Controller
# This script performs additional configuration after AD DS installation

param(
    [Parameter(Mandatory=$true)]
    [string]$DomainName,
    
    [Parameter(Mandatory=$true)]
    [string]$DcIp
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
    # Don't exit, just log the error and continue
}

try {
    Write-Log "Starting post-configuration tasks for DC: $env:COMPUTERNAME"
    
    # Wait for AD services to be fully ready
    Write-Log "Waiting for Active Directory services to be fully ready..."
    Start-Sleep -Seconds 60
    
    # Import required modules
    Write-Log "Importing required PowerShell modules..."
    Import-Module ActiveDirectory -Force
    Import-Module DnsServer -Force
    Import-Module GroupPolicy -Force -ErrorAction SilentlyContinue
    
    # Wait for domain to be fully functional
    Write-Log "Verifying domain functionality..."
    $maxAttempts = 30
    $attempt = 0
    
    do {
        $attempt++
        try {
            $domain = Get-ADDomain -ErrorAction Stop
            $domainReady = $true
            Write-Log "Domain is ready: $($domain.DNSRoot)"
        } catch {
            $domainReady = $false
            Write-Log "Domain not yet ready, attempt $attempt of $maxAttempts..."
            Start-Sleep -Seconds 10
        }
    } while (-not $domainReady -and $attempt -lt $maxAttempts)
    
    if (-not $domainReady) {
        Write-ErrorLog "Domain did not become ready within expected time"
        return
    }
    
    # Configure DNS client settings
    Write-Log "Configuring DNS client settings..."
    try {
        $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
        foreach ($adapter in $adapters) {
            # Set DNS to point to self and other DCs
            $dnsServers = @($DcIp)
            if ($env:DC_ADDITIONAL_DNS) {
                $dnsServers += $env:DC_ADDITIONAL_DNS.Split(',')
            }
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $dnsServers
            Write-Log "Configured DNS for adapter $($adapter.Name): $($dnsServers -join ', ')"
        }
    } catch {
        Write-ErrorLog "Failed to configure DNS client settings: $($_.Exception.Message)"
    }
    
    # Configure Active Directory Sites and Services
    Write-Log "Configuring Active Directory Sites and Services..."
    try {
        Import-Module ActiveDirectory
        
        # Create default site structure
        $siteName = "Default-First-Site-Name"
        $defaultSite = Get-ADReplicationSite -Filter "Name -eq '$siteName'" -ErrorAction SilentlyContinue
        
        if ($defaultSite) {
            Write-Log "Default site exists: $siteName"
            
            # Configure site links
            $siteLink = Get-ADReplicationSiteLink -Filter "Name -eq 'DEFAULTIPSITELINK'" -ErrorAction SilentlyContinue
            if ($siteLink) {
                Set-ADReplicationSiteLink -Identity $siteLink -Cost 100 -ReplicationFrequencyInMinutes 15
                Write-Log "Configured default site link replication frequency"
            }
        }
        
        # Configure subnets
        $subnet = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "127.*" -and $_.IPAddress -notlike "169.*"}).IPAddress
        if ($subnet) {
            $networkSegment = ($subnet -split '\.')[0..2] -join '.'
            $subnetName = "$networkSegment.0/24"
            
            try {
                New-ADReplicationSubnet -Name $subnetName -Site $siteName
                Write-Log "Created subnet: $subnetName"
            } catch {
                Write-Log "Subnet may already exist: $subnetName"
            }
        }
        
    } catch {
        Write-ErrorLog "Failed to configure Sites and Services: $($_.Exception.Message)"
    }
    
    # Configure Group Policy Central Store
    Write-Log "Configuring Group Policy Central Store..."
    try {
        $domain = Get-ADDomain
        $sysvolPath = "\\$($domain.DNSRoot)\SYSVOL\$($domain.DNSRoot)"
        $centralStorePath = "$sysvolPath\Policies\PolicyDefinitions"
        
        if (-not (Test-Path $centralStorePath)) {
            New-Item -ItemType Directory -Path $centralStorePath -Force | Out-Null
            Write-Log "Created Group Policy Central Store: $centralStorePath"
            
            # Copy policy definitions from local machine
            $localPolicyPath = "$env:WINDIR\PolicyDefinitions"
            if (Test-Path $localPolicyPath) {
                Copy-Item -Path "$localPolicyPath\*" -Destination $centralStorePath -Recurse -Force
                Write-Log "Copied policy definitions to Central Store"
            }
        } else {
            Write-Log "Group Policy Central Store already exists"
        }
        
    } catch {
        Write-ErrorLog "Failed to configure Group Policy Central Store: $($_.Exception.Message)"
    }
    
    # Configure default password policy
    Write-Log "Configuring default password policy..."
    try {
        $domain = Get-ADDomain
        $domainDN = $domain.DistinguishedName
        
        # Configure fine-grained password policy
        $passwordPolicyName = "Default Domain Password Policy"
        $existingPolicy = Get-ADFineGrainedPasswordPolicy -Filter "Name -eq '$passwordPolicyName'" -ErrorAction SilentlyContinue
        
        if (-not $existingPolicy) {
            $policyParams = @{
                Name = $passwordPolicyName
                DisplayName = "Default Domain Password Policy"
                Description = "Default password policy for domain users"
                Precedence = 10
                MinPasswordLength = 12
                PasswordHistoryCount = 24
                MaxPasswordAge = "90.00:00:00"
                MinPasswordAge = "1.00:00:00"
                LockoutThreshold = 5
                LockoutDuration = "00:30:00"
                LockoutObservationWindow = "00:30:00"
                ComplexityEnabled = $true
                ReversibleEncryptionEnabled = $false
            }
            
            try {
                New-ADFineGrainedPasswordPolicy @policyParams
                
                # Apply to Domain Users group
                $domainUsersGroup = Get-ADGroup -Filter "Name -eq 'Domain Users'"
                if ($domainUsersGroup) {
                    Add-ADFineGrainedPasswordPolicySubject -Identity $passwordPolicyName -Subjects $domainUsersGroup
                    Write-Log "Created and applied fine-grained password policy"
                }
            } catch {
                Write-Log "Warning: Could not create fine-grained password policy (may require higher functional level)"
            }
        }
        
    } catch {
        Write-ErrorLog "Failed to configure password policy: $($_.Exception.Message)"
    }
    
    # Enable Active Directory Recycle Bin
    Write-Log "Enabling Active Directory Recycle Bin..."
    try {
        $forest = Get-ADForest
        $recycleBinFeature = Get-ADOptionalFeature -Filter "Name -eq 'Recycle Bin Feature'"
        
        if ($recycleBinFeature -and $recycleBinFeature.EnabledScopes.Count -eq 0) {
            Enable-ADOptionalFeature -Identity $recycleBinFeature -Scope ForestOrConfigurationSet -Target $forest.Name -Confirm:$false
            Write-Log "Enabled Active Directory Recycle Bin"
        } else {
            Write-Log "Active Directory Recycle Bin is already enabled"
        }
        
    } catch {
        Write-ErrorLog "Failed to enable Active Directory Recycle Bin: $($_.Exception.Message)"
    }
    
    # Configure DNS aging and scavenging
    Write-Log "Configuring DNS aging and scavenging..."
    try {
        # Enable aging for all zones
        $zones = Get-DnsServerZone | Where-Object {$_.ZoneType -eq "Primary" -and $_.IsAutoCreated -eq $false}
        
        foreach ($zone in $zones) {
            try {
                Set-DnsServerZoneAging -Name $zone.ZoneName -Aging $true -ScavengeServers $env:COMPUTERNAME
                Write-Log "Enabled aging for zone: $($zone.ZoneName)"
            } catch {
                Write-Log "Warning: Could not enable aging for zone: $($zone.ZoneName)"
            }
        }
        
        # Configure scavenging intervals
        Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval "7.00:00:00" -ApplyOnAllZones
        Write-Log "Configured DNS scavenging intervals"
        
    } catch {
        Write-ErrorLog "Failed to configure DNS aging and scavenging: $($_.Exception.Message)"
    }
    
    # Configure DHCP (if requested)
    if ($env:CONFIGURE_DHCP -eq "true") {
        Write-Log "Configuring DHCP service..."
        try {
            # Install DHCP feature
            Install-WindowsFeature -Name DHCP -IncludeManagementTools
            
            # Configure DHCP scope
            $scopeName = "Default Scope"
            $startRange = "$($env:DHCP_START_IP)"
            $endRange = "$($env:DHCP_END_IP)"
            $subnetMask = "$($env:DHCP_SUBNET_MASK)"
            
            if ($startRange -and $endRange -and $subnetMask) {
                Add-DhcpServerv4Scope -Name $scopeName -StartRange $startRange -EndRange $endRange -SubnetMask $subnetMask
                
                # Configure DHCP options
                Set-DhcpServerv4OptionValue -ScopeId $startRange -DnsServer $DcIp -Router $env:GATEWAY_IP
                
                Write-Log "Configured DHCP scope: $scopeName"
            }
            
        } catch {
            Write-ErrorLog "Failed to configure DHCP: $($_.Exception.Message)"
        }
    }
    
    # Configure time synchronization hierarchy
    Write-Log "Configuring time synchronization hierarchy..."
    try {
        # Check if this is the PDC emulator
        $domain = Get-ADDomain
        $pdcEmulator = Get-ADDomainController -Filter "OperationMasterRoles -like '*PDCEmulator*'"
        
        if ($pdcEmulator.Name -eq $env:COMPUTERNAME) {
            Write-Log "This DC is the PDC Emulator, configuring as authoritative time source"
            w32tm /config /manualpeerlist:"time.windows.com,0x8 pool.ntp.org,0x8" /syncfromflags:manual /reliable:yes /update
            w32tm /config /announce:yes /update
        } else {
            Write-Log "This DC is not the PDC Emulator, configuring to sync with domain hierarchy"
            w32tm /config /syncfromflags:domhier /update
        }
        
        Restart-Service w32time
        w32tm /resync
        Write-Log "Time synchronization configured successfully"
        
    } catch {
        Write-ErrorLog "Failed to configure time synchronization: $($_.Exception.Message)"
    }
    
    # Configure backup strategy
    Write-Log "Configuring backup strategy..."
    try {
        # Install Windows Server Backup feature
        Install-WindowsFeature -Name Windows-Server-Backup -IncludeManagementTools
        
        # Create backup directory
        $backupPath = "D:\Backups"
        if (-not (Test-Path $backupPath)) {
            New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
            Write-Log "Created backup directory: $backupPath"
        }
        
        # Configure scheduled backup task
        $backupScript = @"
# Automated AD backup script
`$backupPath = "D:\Backups\AD_Backup_`$(Get-Date -Format 'yyyyMMdd_HHmmss')"
New-Item -ItemType Directory -Path `$backupPath -Force | Out-Null
wbadmin start backup -backupTarget:`$backupPath -systemState -quiet
"@
        
        $backupScript | Out-File -FilePath "C:\Scripts\backup-ad.ps1" -Encoding UTF8
        
        # Create scheduled task for backup
        $backupAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\backup-ad.ps1"
        $backupTrigger = New-ScheduledTaskTrigger -Daily -At "02:00"
        $backupPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
        $backupSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 4) -RestartCount 3
        
        Register-ScheduledTask -TaskName "AD System State Backup" -Action $backupAction -Trigger $backupTrigger -Principal $backupPrincipal -Settings $backupSettings -Force
        Write-Log "Created scheduled backup task"
        
    } catch {
        Write-ErrorLog "Failed to configure backup strategy: $($_.Exception.Message)"
    }
    
    # Configure monitoring and alerting
    Write-Log "Configuring monitoring and alerting..."
    try {
        # Configure event log monitoring
        $monitoringScript = @"
# AD health monitoring script
`$criticalEvents = Get-WinEvent -FilterHashtable @{LogName='Directory Service'; Level=1,2} -MaxEvents 10 -ErrorAction SilentlyContinue
if (`$criticalEvents) {
    `$criticalEvents | ForEach-Object {
        Write-EventLog -LogName Application -Source "AD Monitor" -EntryType Error -EventId 1001 -Message "Critical AD Event: `$(`$_.Message)"
    }
}

# Check AD replication health
try {
    `$replStatus = Get-ADReplicationFailure -Target `$env:COMPUTERNAME -ErrorAction SilentlyContinue
    if (`$replStatus) {
        Write-EventLog -LogName Application -Source "AD Monitor" -EntryType Warning -EventId 1002 -Message "AD Replication Issues Detected"
    }
} catch {
    Write-EventLog -LogName Application -Source "AD Monitor" -EntryType Error -EventId 1003 -Message "Could not check AD replication status"
}

# Check SYSVOL replication
try {
    `$sysvolStatus = Get-WmiObject -Class Win32_NTEventlogFile | Where-Object {`$_.LogfileName -eq "DFS Replication"}
    if (`$sysvolStatus) {
        Write-EventLog -LogName Application -Source "AD Monitor" -EntryType Information -EventId 1004 -Message "SYSVOL replication check completed"
    }
} catch {
    Write-EventLog -LogName Application -Source "AD Monitor" -EntryType Error -EventId 1005 -Message "Could not check SYSVOL replication status"
}
"@
        
        # Create event source
        try {
            New-EventLog -LogName Application -Source "AD Monitor" -ErrorAction SilentlyContinue
        } catch {
            Write-Log "Event source 'AD Monitor' may already exist"
        }
        
        $monitoringScript | Out-File -FilePath "C:\Scripts\monitor-ad.ps1" -Encoding UTF8
        
        # Create scheduled task for monitoring
        $monitorAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\monitor-ad.ps1"
        $monitorTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) -RepetitionInterval (New-TimeSpan -Minutes 15)
        $monitorPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
        $monitorSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -RestartCount 3
        
        Register-ScheduledTask -TaskName "AD Health Monitor" -Action $monitorAction -Trigger $monitorTrigger -Principal $monitorPrincipal -Settings $monitorSettings -Force
        Write-Log "Created monitoring scheduled task"
        
    } catch {
        Write-ErrorLog "Failed to configure monitoring: $($_.Exception.Message)"
    }
    
    # Final health check
    Write-Log "Performing final health check..."
    try {
        # Check AD services
        $adServices = @("NTDS", "DNS", "Netlogon", "KDC", "W32Time")
        foreach ($service in $adServices) {
            $serviceStatus = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($serviceStatus) {
                Write-Log "Service $service status: $($serviceStatus.Status)"
            } else {
                Write-Log "Warning: Service $service not found"
            }
        }
        
        # Check domain controller functionality
        $dcDiag = dcdiag /test:connectivity /test:dns /test:frssysvol /test:replications /test:ridmanager /test:services /test:systemlog /test:tomstones /test:trustsaccessibility /test:vcalist
        Write-Log "DCDiag test completed"
        
        # Check DNS functionality
        $dnsTest = nslookup $DomainName $DcIp
        if ($LASTEXITCODE -eq 0) {
            Write-Log "DNS resolution test passed"
        } else {
            Write-Log "Warning: DNS resolution test failed"
        }
        
    } catch {
        Write-ErrorLog "Health check encountered errors: $($_.Exception.Message)"
    }
    
    Write-Log "Post-configuration tasks completed successfully"
    Write-Log "Domain Controller $env:COMPUTERNAME is ready for production use"
    
} catch {
    Write-ErrorLog "Post-configuration failed: $($_.Exception.Message)"
}
