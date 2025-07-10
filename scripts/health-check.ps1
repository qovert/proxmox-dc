# health-check.ps1
# Comprehensive health check script for Active Directory Domain Controller
# This script performs regular health checks and reports issues

param(
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\Scripts\Reports"
)

# Function to log messages
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logColor = switch ($Level) {
        "ERROR" { "Red" }
        "WARNING" { "Yellow" }
        "INFO" { "Green" }
        default { "White" }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $logColor
}

# Function to create HTML report
function New-HtmlReport {
    param([array]$Results, [string]$Title)
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>$Title</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 10px; border-radius: 5px; }
        .success { color: green; }
        .warning { color: orange; }
        .error { color: red; }
        .info { color: blue; }
        table { border-collapse: collapse; width: 100%; margin-top: 20px; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>$Title</h1>
        <p>Generated on: $(Get-Date)</p>
        <p>Server: $env:COMPUTERNAME</p>
    </div>
    <table>
        <tr><th>Check</th><th>Status</th><th>Details</th></tr>
"@
    
    foreach ($result in $Results) {
        $statusClass = switch ($result.Status) {
            "PASS" { "success" }
            "WARN" { "warning" }
            "FAIL" { "error" }
            default { "info" }
        }
        
        $html += "<tr><td>$($result.Check)</td><td class='$statusClass'>$($result.Status)</td><td>$($result.Details)</td></tr>"
    }
    
    $html += @"
    </table>
</body>
</html>
"@
    
    return $html
}

try {
    Write-Log "Starting Active Directory health check..."
    
    # Create reports directory if it doesn't exist
    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
        Write-Log "Created reports directory: $ReportPath"
    }
    
    # Initialize results array
    $healthResults = @()
    
    # Import required modules
    Write-Log "Importing required modules..."
    try {
        Import-Module ActiveDirectory -Force
        Import-Module DnsServer -Force
        $healthResults += @{Check="Module Import"; Status="PASS"; Details="All required modules imported successfully"}
    } catch {
        $healthResults += @{Check="Module Import"; Status="FAIL"; Details="Failed to import modules: $($_.Exception.Message)"}
    }
    
    # Check AD services
    Write-Log "Checking Active Directory services..."
    $adServices = @("NTDS", "DNS", "Netlogon", "KDC", "W32Time", "DFSR")
    
    foreach ($service in $adServices) {
        try {
            $serviceStatus = Get-Service -Name $service -ErrorAction Stop
            if ($serviceStatus.Status -eq "Running") {
                $healthResults += @{Check="Service: $service"; Status="PASS"; Details="Service is running"}
            } else {
                $healthResults += @{Check="Service: $service"; Status="FAIL"; Details="Service status: $($serviceStatus.Status)"}
            }
        } catch {
            $healthResults += @{Check="Service: $service"; Status="FAIL"; Details="Service not found or error: $($_.Exception.Message)"}
        }
    }
    
    # Check domain controller functionality
    Write-Log "Checking domain controller functionality..."
    try {
        $domain = Get-ADDomain
        $healthResults += @{Check="Domain Access"; Status="PASS"; Details="Domain: $($domain.DNSRoot), NetBIOS: $($domain.NetBIOSName)"}
        
        # Check FSMO roles
        $fsmoRoles = Get-ADDomain | Select-Object InfrastructureMaster, RIDMaster, PDCEmulator
        $forestRoles = Get-ADForest | Select-Object DomainNamingMaster, SchemaMaster
        
        $fsmoDetails = "Domain roles: Infrastructure($($fsmoRoles.InfrastructureMaster)), RID($($fsmoRoles.RIDMaster)), PDC($($fsmoRoles.PDCEmulator))"
        $fsmoDetails += " Forest roles: DomainNaming($($forestRoles.DomainNamingMaster)), Schema($($forestRoles.SchemaMaster))"
        
        $healthResults += @{Check="FSMO Roles"; Status="PASS"; Details=$fsmoDetails}
        
    } catch {
        $healthResults += @{Check="Domain Access"; Status="FAIL"; Details="Cannot access domain: $($_.Exception.Message)"}
    }
    
    # Check AD replication
    Write-Log "Checking Active Directory replication..."
    try {
        $replPartners = Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME
        if ($replPartners) {
            $replDetails = "Replication partners: $($replPartners.Count)"
            $healthResults += @{Check="AD Replication"; Status="PASS"; Details=$replDetails}
        } else {
            $healthResults += @{Check="AD Replication"; Status="WARN"; Details="No replication partners found"}
        }
        
        # Check for replication failures
        $replFailures = Get-ADReplicationFailure -Target $env:COMPUTERNAME -ErrorAction SilentlyContinue
        if ($replFailures) {
            $failureDetails = "Replication failures found: $($replFailures.Count)"
            $healthResults += @{Check="Replication Failures"; Status="FAIL"; Details=$failureDetails}
        } else {
            $healthResults += @{Check="Replication Failures"; Status="PASS"; Details="No replication failures"}
        }
        
    } catch {
        $healthResults += @{Check="AD Replication"; Status="FAIL"; Details="Cannot check replication: $($_.Exception.Message)"}
    }
    
    # Check DNS functionality
    Write-Log "Checking DNS functionality..."
    try {
        # Test local DNS resolution
        $localDnsTest = Resolve-DnsName -Name $env:COMPUTERNAME -Type A -ErrorAction Stop
        if ($localDnsTest) {
            $healthResults += @{Check="Local DNS Resolution"; Status="PASS"; Details="Local DNS resolution working"}
        }
        
        # Test external DNS resolution
        $externalDnsTest = Resolve-DnsName -Name "google.com" -Type A -ErrorAction Stop
        if ($externalDnsTest) {
            $healthResults += @{Check="External DNS Resolution"; Status="PASS"; Details="External DNS resolution working"}
        }
        
        # Check DNS forwarders
        $forwarders = Get-DnsServerForwarder
        if ($forwarders) {
            $forwarderDetails = "Forwarders configured: $($forwarders.IPAddress -join ', ')"
            $healthResults += @{Check="DNS Forwarders"; Status="PASS"; Details=$forwarderDetails}
        } else {
            $healthResults += @{Check="DNS Forwarders"; Status="WARN"; Details="No DNS forwarders configured"}
        }
        
    } catch {
        $healthResults += @{Check="DNS Functionality"; Status="FAIL"; Details="DNS check failed: $($_.Exception.Message)"}
    }
    
    # Check system resources
    Write-Log "Checking system resources..."
    try {
        # Check memory usage
        $memory = Get-WmiObject -Class Win32_OperatingSystem
        $memoryUsage = [math]::Round((($memory.TotalVisibleMemorySize - $memory.FreePhysicalMemory) / $memory.TotalVisibleMemorySize) * 100, 2)
        
        if ($memoryUsage -lt 80) {
            $healthResults += @{Check="Memory Usage"; Status="PASS"; Details="Memory usage: $memoryUsage%"}
        } elseif ($memoryUsage -lt 90) {
            $healthResults += @{Check="Memory Usage"; Status="WARN"; Details="Memory usage: $memoryUsage%"}
        } else {
            $healthResults += @{Check="Memory Usage"; Status="FAIL"; Details="Memory usage: $memoryUsage%"}
        }
        
        # Check disk space
        $disks = Get-WmiObject -Class Win32_LogicalDisk | Where-Object {$_.DriveType -eq 3}
        foreach ($disk in $disks) {
            $freeSpacePercent = [math]::Round(($disk.FreeSpace / $disk.Size) * 100, 2)
            $diskDetails = "Drive $($disk.DeviceID) - Free: $freeSpacePercent%"
            
            if ($freeSpacePercent -gt 20) {
                $healthResults += @{Check="Disk Space $($disk.DeviceID)"; Status="PASS"; Details=$diskDetails}
            } elseif ($freeSpacePercent -gt 10) {
                $healthResults += @{Check="Disk Space $($disk.DeviceID)"; Status="WARN"; Details=$diskDetails}
            } else {
                $healthResults += @{Check="Disk Space $($disk.DeviceID)"; Status="FAIL"; Details=$diskDetails}
            }
        }
        
        # Check CPU usage
        $cpuUsage = Get-WmiObject -Class Win32_Processor | Measure-Object -Property LoadPercentage -Average
        $avgCpuUsage = [math]::Round($cpuUsage.Average, 2)
        
        if ($avgCpuUsage -lt 70) {
            $healthResults += @{Check="CPU Usage"; Status="PASS"; Details="CPU usage: $avgCpuUsage%"}
        } elseif ($avgCpuUsage -lt 85) {
            $healthResults += @{Check="CPU Usage"; Status="WARN"; Details="CPU usage: $avgCpuUsage%"}
        } else {
            $healthResults += @{Check="CPU Usage"; Status="FAIL"; Details="CPU usage: $avgCpuUsage%"}
        }
        
    } catch {
        $healthResults += @{Check="System Resources"; Status="FAIL"; Details="Resource check failed: $($_.Exception.Message)"}
    }
    
    # Check event logs for errors
    Write-Log "Checking event logs for errors..."
    try {
        $eventLogs = @("System", "Application", "Directory Service", "DNS Server")
        
        foreach ($logName in $eventLogs) {
            try {
                $errorEvents = Get-WinEvent -FilterHashtable @{LogName=$logName; Level=1,2} -MaxEvents 5 -ErrorAction SilentlyContinue
                if ($errorEvents) {
                    $errorDetails = "Recent errors found: $($errorEvents.Count)"
                    $healthResults += @{Check="Event Log: $logName"; Status="WARN"; Details=$errorDetails}
                } else {
                    $healthResults += @{Check="Event Log: $logName"; Status="PASS"; Details="No recent errors"}
                }
            } catch {
                $healthResults += @{Check="Event Log: $logName"; Status="WARN"; Details="Cannot access log"}
            }
        }
        
    } catch {
        $healthResults += @{Check="Event Logs"; Status="FAIL"; Details="Event log check failed: $($_.Exception.Message)"}
    }
    
    # Check network connectivity
    Write-Log "Checking network connectivity..."
    try {
        # Test connectivity to other DCs
        $domain = Get-ADDomain
        $domainControllers = Get-ADDomainController -Filter * | Where-Object {$_.Name -ne $env:COMPUTERNAME}
        
        if ($domainControllers) {
            foreach ($dc in $domainControllers) {
                $pingResult = Test-Connection -ComputerName $dc.HostName -Count 1 -Quiet
                if ($pingResult) {
                    $healthResults += @{Check="DC Connectivity: $($dc.Name)"; Status="PASS"; Details="Connectivity successful"}
                } else {
                    $healthResults += @{Check="DC Connectivity: $($dc.Name)"; Status="FAIL"; Details="Cannot reach DC"}
                }
            }
        } else {
            $healthResults += @{Check="Domain Controllers"; Status="WARN"; Details="No other domain controllers found"}
        }
        
    } catch {
        $healthResults += @{Check="Network Connectivity"; Status="FAIL"; Details="Network check failed: $($_.Exception.Message)"}
    }
    
    # Check time synchronization
    Write-Log "Checking time synchronization..."
    try {
        $timeSync = w32tm /query /status
        if ($LASTEXITCODE -eq 0) {
            $healthResults += @{Check="Time Synchronization"; Status="PASS"; Details="Time sync is working"}
        } else {
            $healthResults += @{Check="Time Synchronization"; Status="FAIL"; Details="Time sync issues detected"}
        }
        
    } catch {
        $healthResults += @{Check="Time Synchronization"; Status="FAIL"; Details="Time sync check failed: $($_.Exception.Message)"}
    }
    
    # Check backup status
    Write-Log "Checking backup status..."
    try {
        $backupPath = "D:\Backups"
        if (Test-Path $backupPath) {
            $latestBackup = Get-ChildItem -Path $backupPath -Directory | Sort-Object CreationTime -Descending | Select-Object -First 1
            if ($latestBackup) {
                $backupAge = (Get-Date) - $latestBackup.CreationTime
                if ($backupAge.Days -lt 1) {
                    $healthResults += @{Check="Backup Status"; Status="PASS"; Details="Recent backup found: $($latestBackup.Name)"}
                } elseif ($backupAge.Days -lt 7) {
                    $healthResults += @{Check="Backup Status"; Status="WARN"; Details="Backup is $($backupAge.Days) days old"}
                } else {
                    $healthResults += @{Check="Backup Status"; Status="FAIL"; Details="Backup is $($backupAge.Days) days old"}
                }
            } else {
                $healthResults += @{Check="Backup Status"; Status="FAIL"; Details="No backups found"}
            }
        } else {
            $healthResults += @{Check="Backup Status"; Status="WARN"; Details="Backup directory not found"}
        }
        
    } catch {
        $healthResults += @{Check="Backup Status"; Status="FAIL"; Details="Backup check failed: $($_.Exception.Message)"}
    }
    
    # Generate summary
    $passCount = ($healthResults | Where-Object {$_.Status -eq "PASS"}).Count
    $warnCount = ($healthResults | Where-Object {$_.Status -eq "WARN"}).Count
    $failCount = ($healthResults | Where-Object {$_.Status -eq "FAIL"}).Count
    $totalCount = $healthResults.Count
    
    Write-Log "Health check completed: $passCount PASS, $warnCount WARN, $failCount FAIL (Total: $totalCount)"
    
    # Generate HTML report
    $reportTitle = "Active Directory Health Check Report - $env:COMPUTERNAME"
    $htmlReport = New-HtmlReport -Results $healthResults -Title $reportTitle
    
    $reportFileName = "AD_Health_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $reportFilePath = Join-Path $ReportPath $reportFileName
    
    $htmlReport | Out-File -FilePath $reportFilePath -Encoding UTF8
    Write-Log "HTML report generated: $reportFilePath"
    
    # Generate CSV report
    $csvFileName = "AD_Health_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $csvFilePath = Join-Path $ReportPath $csvFileName
    
    $healthResults | Export-Csv -Path $csvFilePath -NoTypeInformation
    Write-Log "CSV report generated: $csvFilePath"
    
    # Clean up old reports (keep last 30 days)
    $cutoffDate = (Get-Date).AddDays(-30)
    $oldReports = Get-ChildItem -Path $ReportPath -File | Where-Object {$_.CreationTime -lt $cutoffDate}
    
    if ($oldReports) {
        $oldReports | Remove-Item -Force
        Write-Log "Cleaned up $($oldReports.Count) old reports"
    }
    
    # Log to Windows Event Log
    try {
        $eventMessage = "AD Health Check completed: $passCount PASS, $warnCount WARN, $failCount FAIL"
        if ($failCount -gt 0) {
            Write-EventLog -LogName Application -Source "AD Health Check" -EntryType Error -EventId 3001 -Message $eventMessage
        } elseif ($warnCount -gt 0) {
            Write-EventLog -LogName Application -Source "AD Health Check" -EntryType Warning -EventId 3002 -Message $eventMessage
        } else {
            Write-EventLog -LogName Application -Source "AD Health Check" -EntryType Information -EventId 3003 -Message $eventMessage
        }
    } catch {
        Write-Log "Could not write to event log: $($_.Exception.Message)" -Level "WARNING"
    }
    
    Write-Log "Active Directory health check completed successfully"
    
} catch {
    Write-Log "Health check failed: $($_.Exception.Message)" -Level "ERROR"
    exit 1
}
