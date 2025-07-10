# configure-dns.ps1
# Configure DNS settings for Active Directory Domain Controller
# This script configures DNS forwarders and additional DNS settings

param(
    [Parameter(Mandatory=$true)]
    [string]$ForwarderIPs,
    
    [Parameter(Mandatory=$true)]
    [string]$DomainName
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
}

try {
    Write-Log "Starting DNS configuration for domain: $DomainName"
    
    # Import DNS module
    Write-Log "Importing DNS Server module..."
    Import-Module DnsServer -Force
    
    # Wait for DNS service to be ready
    Write-Log "Waiting for DNS service to be ready..."
    $maxAttempts = 30
    $attempt = 0
    
    do {
        $attempt++
        try {
            $dnsService = Get-Service -Name DNS -ErrorAction Stop
            if ($dnsService.Status -eq "Running") {
                Write-Log "DNS service is running"
                break
            } else {
                Start-Service -Name DNS -ErrorAction Stop
                Start-Sleep -Seconds 5
            }
        } catch {
            Write-Log "DNS service not ready, attempt $attempt of $maxAttempts..."
            Start-Sleep -Seconds 10
        }
    } while ($attempt -lt $maxAttempts)
    
    # Configure DNS forwarders
    Write-Log "Configuring DNS forwarders..."
    try {
        # Parse forwarder IPs
        $forwarders = $ForwarderIPs.Split(',') | ForEach-Object { $_.Trim() }
        
        # Remove existing forwarders
        $existingForwarders = Get-DnsServerForwarder
        if ($existingForwarders) {
            Remove-DnsServerForwarder -IPAddress $existingForwarders.IPAddress -Force
            Write-Log "Removed existing DNS forwarders"
        }
        
        # Add new forwarders
        foreach ($forwarder in $forwarders) {
            if ($forwarder -match "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$") {
                Add-DnsServerForwarder -IPAddress $forwarder
                Write-Log "Added DNS forwarder: $forwarder"
            } else {
                Write-Log "Warning: Invalid IP address format: $forwarder"
            }
        }
        
        # Configure forwarder settings
        Set-DnsServerForwarder -UseRootHint $false -Timeout 5 -EnableReordering $true
        Write-Log "Configured DNS forwarder settings"
        
    } catch {
        Write-ErrorLog "Failed to configure DNS forwarders: $($_.Exception.Message)"
    }
    
    # Configure DNS server settings
    Write-Log "Configuring DNS server settings..."
    try {
        # Enable DNS recursion
        Set-DnsServerRecursion -Enable $true
        
        # Configure DNS cache settings
        Set-DnsServerCache -MaxTtl 86400 -MaxNegativeTtl 3600 -LockingPercent 100
        
        # Configure DNS logging
        Set-DnsServerDiagnostics -All $true -SaveLogsToPersistentStorage $true
        
        # Configure DNS security
        Set-DnsServerResponseRateLimiting -ResponsesPerSec 10 -ErrorsPerSec 5 -WindowInSec 5
        
        Write-Log "Configured DNS server settings"
        
    } catch {
        Write-ErrorLog "Failed to configure DNS server settings: $($_.Exception.Message)"
    }
    
    # Configure DNS zones
    Write-Log "Configuring DNS zones..."
    try {
        # Get all zones
        $zones = Get-DnsServerZone | Where-Object {$_.ZoneType -eq "Primary"}
        
        foreach ($zone in $zones) {
            # Configure zone transfer settings
            Set-DnsServerZoneTransfer -Name $zone.ZoneName -TransferPolicy ZoneTransferToAnyServer
            
            # Configure zone aging
            Set-DnsServerZoneAging -Name $zone.ZoneName -Aging $true -ScavengeServers $env:COMPUTERNAME
            
            # Configure zone dynamic updates
            Set-DnsServerPrimaryZone -Name $zone.ZoneName -DynamicUpdate Secure
            
            Write-Log "Configured zone: $($zone.ZoneName)"
        }
        
    } catch {
        Write-ErrorLog "Failed to configure DNS zones: $($_.Exception.Message)"
    }
    
    # Configure conditional forwarders for common domains
    Write-Log "Configuring conditional forwarders..."
    try {
        $conditionalForwarders = @(
            @{Domain="google.com"; Forwarders=@("8.8.8.8", "8.8.4.4")},
            @{Domain="microsoft.com"; Forwarders=@("1.1.1.1", "1.0.0.1")},
            @{Domain="office.com"; Forwarders=@("1.1.1.1", "1.0.0.1")}
        )
        
        foreach ($cf in $conditionalForwarders) {
            try {
                Add-DnsServerConditionalForwarderZone -Name $cf.Domain -MasterServers $cf.Forwarders
                Write-Log "Added conditional forwarder for: $($cf.Domain)"
            } catch {
                Write-Log "Warning: Could not add conditional forwarder for: $($cf.Domain)"
            }
        }
        
    } catch {
        Write-ErrorLog "Failed to configure conditional forwarders: $($_.Exception.Message)"
    }
    
    # Configure DNS scavenging
    Write-Log "Configuring DNS scavenging..."
    try {
        # Configure scavenging intervals
        Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval "7.00:00:00" -RefreshInterval "7.00:00:00" -NoRefreshInterval "7.00:00:00"
        
        # Enable aging for all zones
        $zones = Get-DnsServerZone | Where-Object {$_.ZoneType -eq "Primary" -and $_.IsAutoCreated -eq $false}
        foreach ($zone in $zones) {
            Set-DnsServerZoneAging -Name $zone.ZoneName -Aging $true -ScavengeServers $env:COMPUTERNAME
        }
        
        Write-Log "Configured DNS scavenging"
        
    } catch {
        Write-ErrorLog "Failed to configure DNS scavenging: $($_.Exception.Message)"
    }
    
    # Configure DNS monitoring
    Write-Log "Configuring DNS monitoring..."
    try {
        # Create DNS monitoring script
        $monitoringScript = @"
# DNS monitoring script
`$dnsService = Get-Service -Name DNS
if (`$dnsService.Status -ne "Running") {
    Write-EventLog -LogName Application -Source "DNS Monitor" -EntryType Error -EventId 2001 -Message "DNS service is not running"
    Start-Service -Name DNS
}

# Check DNS resolution
try {
    `$resolveTest = Resolve-DnsName -Name "$DomainName" -Type A -ErrorAction Stop
    if (`$resolveTest) {
        Write-EventLog -LogName Application -Source "DNS Monitor" -EntryType Information -EventId 2002 -Message "DNS resolution test passed"
    }
} catch {
    Write-EventLog -LogName Application -Source "DNS Monitor" -EntryType Error -EventId 2003 -Message "DNS resolution test failed: `$(`$_.Exception.Message)"
}

# Check forwarder connectivity
`$forwarders = Get-DnsServerForwarder
foreach (`$forwarder in `$forwarders) {
    try {
        `$pingResult = Test-NetConnection -ComputerName `$forwarder.IPAddress -Port 53 -InformationLevel Quiet
        if (`$pingResult) {
            Write-EventLog -LogName Application -Source "DNS Monitor" -EntryType Information -EventId 2004 -Message "Forwarder connectivity test passed: `$(`$forwarder.IPAddress)"
        } else {
            Write-EventLog -LogName Application -Source "DNS Monitor" -EntryType Warning -EventId 2005 -Message "Forwarder connectivity test failed: `$(`$forwarder.IPAddress)"
        }
    } catch {
        Write-EventLog -LogName Application -Source "DNS Monitor" -EntryType Error -EventId 2006 -Message "Could not test forwarder connectivity: `$(`$forwarder.IPAddress)"
    }
}
"@
        
        # Create event source
        try {
            New-EventLog -LogName Application -Source "DNS Monitor" -ErrorAction SilentlyContinue
        } catch {
            Write-Log "Event source 'DNS Monitor' may already exist"
        }
        
        $monitoringScript | Out-File -FilePath "C:\Scripts\monitor-dns.ps1" -Encoding UTF8
        
        # Create scheduled task for DNS monitoring
        $dnsMonitorAction = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument "-File C:\Scripts\monitor-dns.ps1"
        $dnsMonitorTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(10) -RepetitionInterval (New-TimeSpan -Minutes 30)
        $dnsMonitorPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount
        $dnsMonitorSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -RestartCount 3
        
        Register-ScheduledTask -TaskName "DNS Health Monitor" -Action $dnsMonitorAction -Trigger $dnsMonitorTrigger -Principal $dnsMonitorPrincipal -Settings $dnsMonitorSettings -Force
        Write-Log "Created DNS monitoring scheduled task"
        
    } catch {
        Write-ErrorLog "Failed to configure DNS monitoring: $($_.Exception.Message)"
    }
    
    # Test DNS configuration
    Write-Log "Testing DNS configuration..."
    try {
        # Test local DNS resolution
        $localTest = Resolve-DnsName -Name $DomainName -Type A
        if ($localTest) {
            Write-Log "Local DNS resolution test passed"
        }
        
        # Test forwarder resolution
        $externalTest = Resolve-DnsName -Name "google.com" -Type A
        if ($externalTest) {
            Write-Log "External DNS resolution test passed"
        }
        
        # Test reverse DNS resolution
        $reverseTest = Resolve-DnsName -Name "127.0.0.1" -Type PTR -ErrorAction SilentlyContinue
        if ($reverseTest) {
            Write-Log "Reverse DNS resolution test passed"
        }
        
    } catch {
        Write-ErrorLog "DNS configuration tests failed: $($_.Exception.Message)"
    }
    
    # Configure DNS client settings on the server
    Write-Log "Configuring DNS client settings..."
    try {
        $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}
        foreach ($adapter in $adapters) {
            # Set DNS to point to localhost first, then other DCs
            $dnsServers = @("127.0.0.1")
            
            # Add other DC IPs if provided
            if ($env:OTHER_DC_IPS) {
                $otherDCs = $env:OTHER_DC_IPS.Split(',') | ForEach-Object { $_.Trim() }
                $dnsServers += $otherDCs
            }
            
            Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $dnsServers
            Write-Log "Configured DNS client for adapter $($adapter.Name): $($dnsServers -join ', ')"
        }
        
    } catch {
        Write-ErrorLog "Failed to configure DNS client settings: $($_.Exception.Message)"
    }
    
    # Restart DNS service to apply all changes
    Write-Log "Restarting DNS service..."
    try {
        Restart-Service -Name DNS -Force
        Start-Sleep -Seconds 10
        
        # Verify DNS service is running
        $dnsService = Get-Service -Name DNS
        if ($dnsService.Status -eq "Running") {
            Write-Log "DNS service restarted successfully"
        } else {
            Write-ErrorLog "DNS service failed to restart"
        }
        
    } catch {
        Write-ErrorLog "Failed to restart DNS service: $($_.Exception.Message)"
    }
    
    # Final DNS health check
    Write-Log "Performing final DNS health check..."
    try {
        # Check DNS server statistics
        $dnsStats = Get-DnsServerStatistics
        Write-Log "DNS server statistics: Queries received: $($dnsStats.QueryReceived), Responses sent: $($dnsStats.ResponseSent)"
        
        # Check DNS server forwarders
        $configuredForwarders = Get-DnsServerForwarder
        Write-Log "Configured DNS forwarders: $($configuredForwarders.IPAddress -join ', ')"
        
        # Check DNS zones
        $dnsZones = Get-DnsServerZone | Where-Object {$_.ZoneType -eq "Primary"}
        Write-Log "DNS zones configured: $($dnsZones.ZoneName -join ', ')"
        
    } catch {
        Write-ErrorLog "Final DNS health check failed: $($_.Exception.Message)"
    }
    
    Write-Log "DNS configuration completed successfully"
    
} catch {
    Write-ErrorLog "DNS configuration failed: $($_.Exception.Message)"
}
