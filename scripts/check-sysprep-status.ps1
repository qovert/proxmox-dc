# Check Sysprep Status Script
# This script helps troubleshoot sysprep issues by checking process status and logs

param(
    [switch]$ShowFullLogs = $false
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

Write-Log "Checking Sysprep Status..." "SUCCESS"

# Check if sysprep is currently running
Write-Log "Checking for running sysprep processes..." "INFO"
$sysprepProcesses = Get-Process -Name "sysprep" -ErrorAction SilentlyContinue
if ($sysprepProcesses) {
    foreach ($proc in $sysprepProcesses) {
        Write-Log "Sysprep process found - PID: $($proc.Id), CPU Time: $($proc.TotalProcessorTime), Start Time: $($proc.StartTime)" "SUCCESS"
    }
} else {
    Write-Log "No sysprep process currently running" "WARNING"
}

# Check for any processes that might indicate sysprep activity
$relatedProcesses = Get-Process | Where-Object { 
    $_.ProcessName -like "*sysprep*" -or 
    $_.ProcessName -like "*setupcl*" -or 
    $_.ProcessName -like "*msiexec*" -or
    $_.ProcessName -like "*dism*"
}

if ($relatedProcesses) {
    Write-Log "Found potentially related processes:" "INFO"
    foreach ($proc in $relatedProcesses) {
        Write-Log "  $($proc.ProcessName) (PID: $($proc.Id))" "INFO"
    }
}

# Check sysprep log files
Write-Log "Checking sysprep log files..." "INFO"
$sysprepLogPaths = @(
    "C:\Windows\System32\Sysprep\Panther\setupact.log",
    "C:\Windows\System32\Sysprep\Panther\setuperr.log",
    "C:\Windows\Panther\setupact.log",
    "C:\Windows\Panther\setuperr.log"
)

$foundLogs = $false
foreach ($logPath in $sysprepLogPaths) {
    if (Test-Path $logPath) {
        $foundLogs = $true
        $logInfo = Get-Item $logPath
        $logSize = $logInfo.Length
        $lastWrite = $logInfo.LastWriteTime
        $ageMinutes = [math]::Round(((Get-Date) - $lastWrite).TotalMinutes, 1)
        
        Write-Log "Found log: $logPath" "SUCCESS"
        Write-Log "  Size: $([math]::Round($logSize/1KB, 1)) KB" "INFO"
        Write-Log "  Last Modified: $lastWrite ($ageMinutes minutes ago)" "INFO"
        
        # Show last few lines of the log
        try {
            if ($ShowFullLogs) {
                $lines = Get-Content $logPath -ErrorAction SilentlyContinue
                $lineCount = if ($lines) { $lines.Count } else { 0 }
                Write-Log "  Total lines: $lineCount" "INFO"
                if ($lines) {
                    Write-Log "Full log content:" "INFO"
                    foreach ($line in $lines) {
                        Write-Host "    $line" -ForegroundColor Gray
                    }
                }
            } else {
                $lastLines = Get-Content $logPath -Tail 10 -ErrorAction SilentlyContinue
                if ($lastLines) {
                    Write-Log "  Last 10 lines:" "INFO"
                    foreach ($line in $lastLines) {
                        Write-Host "    $line" -ForegroundColor Gray
                    }
                } else {
                    Write-Log "  Log file is empty or unreadable" "WARNING"
                }
            }
        } catch {
            Write-Log "  Could not read log file: $($_.Exception.Message)" "WARNING"
        }
        Write-Log "" # Empty line for readability
    }
}

if (-not $foundLogs) {
    Write-Log "No sysprep log files found" "WARNING"
    Write-Log "This could mean sysprep hasn't run yet or logs were cleared" "INFO"
}

# Check system shutdown/restart status
Write-Log "Checking system status..." "INFO"
try {
    $lastBootTime = (Get-CimInstance -ClassName Win32_OperatingSystem).LastBootUpTime
    $uptime = (Get-Date) - $lastBootTime
    Write-Log "System uptime: $([math]::Round($uptime.TotalHours, 1)) hours" "INFO"
    Write-Log "Last boot time: $lastBootTime" "INFO"
} catch {
    Write-Log "Could not determine system uptime" "WARNING"
}

# Check Windows Update service status (sysprep may interact with it)
try {
    $wuService = Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    if ($wuService) {
        Write-Log "Windows Update service status: $($wuService.Status)" "INFO"
    }
} catch {
    Write-Log "Could not check Windows Update service status" "WARNING"
}

# Check for pending reboot
Write-Log "Checking for pending reboot indicators..." "INFO"
$pendingReboot = $false

# Check registry for pending reboot
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
    "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\PendingFileRenameOperations"
)

foreach ($regPath in $regPaths) {
    if (Test-Path $regPath) {
        $pendingReboot = $true
        Write-Log "Pending reboot indicator found: $regPath" "WARNING"
    }
}

if (-not $pendingReboot) {
    Write-Log "No pending reboot indicators found" "SUCCESS"
}

Write-Log "Sysprep status check completed" "SUCCESS"

if ($sysprepProcesses) {
    Write-Log "SUMMARY: Sysprep appears to be running. Wait for it to complete and shutdown the system." "SUCCESS"
} elseif ($foundLogs) {
    Write-Log "SUMMARY: Sysprep may have completed. Check the logs above for any errors." "INFO"
    Write-Log "If no errors and the system hasn't shutdown, sysprep may have completed successfully." "INFO"
} else {
    Write-Log "SUMMARY: No evidence of sysprep activity found. It may not have started yet." "WARNING"
}

Write-Log "Use -ShowFullLogs parameter to see complete log contents" "INFO"
