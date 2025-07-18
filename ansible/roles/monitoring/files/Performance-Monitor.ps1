# Performance-Monitor.ps1
# Performance monitoring script for Active Directory Domain Controller
# Collects and logs performance metrics

param(
    [Parameter(Mandatory=$false)]
    [string]$LogPath = "C:\Scripts\Reports\Performance-$(Get-Date -Format 'yyyy-MM-dd').csv"
)

try {
    # Ensure reports directory exists
    $reportsDir = Split-Path $LogPath -Parent
    if (!(Test-Path $reportsDir)) {
        New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
    }
    
    # Define performance counters
    $perfCounters = @(
        '\Processor(_Total)\% Processor Time',
        '\Memory\Available MBytes',
        '\NTDS\LDAP Searches/sec',
        '\NTDS\LDAP Binds/sec',
        '\NTDS\LDAP Client Sessions',
        '\LogicalDisk(C:)\% Free Space',
        '\System\Processor Queue Length'
    )
    
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    
    # Collect performance data
    $perfData = Get-Counter -Counter $perfCounters -MaxSamples 1 -ErrorAction Stop | ForEach-Object {
        $_.CounterSamples | ForEach-Object {
            [PSCustomObject]@{
                Timestamp = $timestamp
                Computer = $env:COMPUTERNAME
                Counter = $_.Path
                Value = [math]::Round($_.CookedValue, 2)
                Unit = switch -Wildcard ($_.Path) {
                    "*% *" { "Percent" }
                    "*MBytes*" { "MB" }
                    "*sec" { "Per Second" }
                    "*Sessions*" { "Count" }
                    "*Queue*" { "Count" }
                    default { "Value" }
                }
            }
        }
    }
    
    # Write to CSV
    if (Test-Path $LogPath) {
        $perfData | Export-Csv -Path $LogPath -Append -NoTypeInformation
    } else {
        $perfData | Export-Csv -Path $LogPath -NoTypeInformation
    }
    
    # Log summary
    $cpuUsage = ($perfData | Where-Object { $_.Counter -like "*Processor*% Processor Time*" }).Value
    $memoryMB = ($perfData | Where-Object { $_.Counter -like "*Available MBytes*" }).Value
    $ldapSearches = ($perfData | Where-Object { $_.Counter -like "*LDAP Searches*" }).Value
    
    Write-Output "Performance data logged: CPU: $cpuUsage%, Memory: $memoryMB MB available, LDAP Searches: $ldapSearches/sec"
    Write-Output "Log file: $LogPath"
    
    # Check for performance thresholds and alert if needed
    $alerts = @()
    if ($cpuUsage -gt 90) {
        $alerts += "HIGH CPU: $cpuUsage%"
    }
    if ($memoryMB -lt 500) {
        $alerts += "LOW MEMORY: $memoryMB MB available"
    }
    
    if ($alerts.Count -gt 0) {
        $alertMessage = "Performance Alert: " + ($alerts -join ", ")
        Write-Warning $alertMessage
        
        # Log to Windows Event Log
        try {
            Write-EventLog -LogName Application -Source "AD Performance Monitor" -EntryType Warning -EventId 2001 -Message $alertMessage
        } catch {
            # Event source might not exist, create it
            try {
                New-EventLog -LogName Application -Source "AD Performance Monitor"
                Write-EventLog -LogName Application -Source "AD Performance Monitor" -EntryType Warning -EventId 2001 -Message $alertMessage
            } catch {
                # Ignore if we can't create event log entry
            }
        }
    }
    
    exit 0
    
} catch {
    $errorMessage = "Performance monitoring failed: $($_.Exception.Message)"
    Write-Error $errorMessage
    
    # Try to log error to event log
    try {
        Write-EventLog -LogName Application -Source "AD Performance Monitor" -EntryType Error -EventId 2002 -Message $errorMessage
    } catch {
        # Ignore if we can't create event log entry
    }
    
    exit 1
}
