# AD-HealthCheck.ps1
# Comprehensive health check script for Active Directory Domain Controller
# This script performs regular health checks and reports issues

param(
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "C:\Scripts\Reports\AD-Health-$(Get-Date -Format 'yyyy-MM-dd-HHmm').html"
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

try {
    Write-Log "Starting Active Directory health check..."
    
    # Ensure reports directory exists
    $reportsDir = Split-Path $ReportPath -Parent
    if (!(Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
    }
    
    $results = @()
    $services = @('NTDS', 'DNS', 'Netlogon', 'KDC', 'W32Time')
    
    # Check critical AD services
    foreach ($service in $services) {
        try {
            $svc = Get-Service -Name $service -ErrorAction Stop
            $results += [PSCustomObject]@{
                Test = "Service: $service"
                Status = $svc.Status
                Result = if ($svc.Status -eq 'Running') { 'PASS' } else { 'FAIL' }
            }
        } catch {
            $results += [PSCustomObject]@{
                Test = "Service: $service"
                Status = "Not Found"
                Result = 'FAIL'
            }
        }
    }
    
    # Check AD replication
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        $replStatus = Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME -ErrorAction Stop
        $results += [PSCustomObject]@{
            Test = "AD Replication"
            Status = "Partners: $($replStatus.Count)"
            Result = if ($replStatus.Count -gt 0) { 'PASS' } else { 'WARN' }
        }
    } catch {
        $results += [PSCustomObject]@{
            Test = "AD Replication"
            Status = $_.Exception.Message
            Result = 'FAIL'
        }
    }
    
    # Check DNS resolution
    try {
        $dnsTest = Resolve-DnsName -Name $env:USERDNSDOMAIN -ErrorAction Stop
        $results += [PSCustomObject]@{
            Test = "DNS Resolution"
            Status = "Resolved to: $($dnsTest.IPAddress -join ', ')"
            Result = 'PASS'
        }
    } catch {
        $results += [PSCustomObject]@{
            Test = "DNS Resolution"
            Status = $_.Exception.Message
            Result = 'FAIL'
        }
    }
    
    # Check system resources
    try {
        $memory = Get-CimInstance Win32_OperatingSystem
        $memoryUsage = [math]::Round((($memory.TotalVisibleMemorySize - $memory.FreePhysicalMemory) / $memory.TotalVisibleMemorySize) * 100, 2)
        
        $results += [PSCustomObject]@{
            Test = "Memory Usage"
            Status = "$memoryUsage%"
            Result = if ($memoryUsage -lt 80) { 'PASS' } elseif ($memoryUsage -lt 90) { 'WARN' } else { 'FAIL' }
        }
        
        # Check disk space
        $systemDrive = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DeviceID -eq $env:SystemDrive }
        $freeSpacePercent = [math]::Round(($systemDrive.FreeSpace / $systemDrive.Size) * 100, 2)
        
        $results += [PSCustomObject]@{
            Test = "Disk Space"
            Status = "$freeSpacePercent% free"
            Result = if ($freeSpacePercent -gt 20) { 'PASS' } elseif ($freeSpacePercent -gt 10) { 'WARN' } else { 'FAIL' }
        }
    } catch {
        $results += [PSCustomObject]@{
            Test = "System Resources"
            Status = $_.Exception.Message
            Result = 'FAIL'
        }
    }
    
    # Generate HTML report
    $html = $results | ConvertTo-Html -Title "AD Health Check - $env:COMPUTERNAME" -PreContent "<h1>AD Health Check Report</h1><p>Generated: $(Get-Date)</p><style>body{font-family:Arial,sans-serif;margin:20px;}.pass{color:green;}.warn{color:orange;}.fail{color:red;}table{border-collapse:collapse;width:100%;}th,td{border:1px solid #ddd;padding:8px;text-align:left;}th{background-color:#f2f2f2;}</style>"
    
    # Add CSS classes based on results
    $html = $html -replace '<td>PASS</td>', '<td class="pass">PASS</td>'
    $html = $html -replace '<td>WARN</td>', '<td class="warn">WARN</td>'
    $html = $html -replace '<td>FAIL</td>', '<td class="fail">FAIL</td>'
    
    $html | Out-File -FilePath $ReportPath -Encoding UTF8
    Write-Log "Health check completed. Report saved to: $ReportPath"
    
    # Exit with appropriate code
    $failCount = ($results | Where-Object { $_.Result -eq 'FAIL' }).Count
    $warnCount = ($results | Where-Object { $_.Result -eq 'WARN' }).Count
    
    Write-Log "Summary: $($results.Count) tests, $($results | Where-Object { $_.Result -eq 'PASS' } | Measure-Object | Select-Object -ExpandProperty Count) passed, $warnCount warnings, $failCount failures"
    
    if ($failCount -gt 0) {
        Write-Log "$failCount critical tests failed" "ERROR"
        exit 1
    } elseif ($warnCount -gt 0) {
        Write-Log "$warnCount tests have warnings" "WARNING"
        exit 0
    } else {
        Write-Log "All tests passed" "INFO"
        exit 0
    }
    
} catch {
    Write-Log "Health check script failed: $($_.Exception.Message)" "ERROR"
    exit 1
}
