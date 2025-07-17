# Manual Sysprep Script
# This script allows manual execution of sysprep with proper monitoring

param(
    [switch]$Force = $false,
    [switch]$NoShutdown = $false,
    [string]$Answer = ""
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

Write-Log "Manual Sysprep Execution Script" "SUCCESS"

# Check if sysprep is already running
$existingProcess = Get-Process -Name "sysprep" -ErrorAction SilentlyContinue
if ($existingProcess -and -not $Force) {
    Write-Log "Sysprep is already running (PID: $($existingProcess.Id))" "WARNING"
    Write-Log "Use -Force parameter to proceed anyway (not recommended)" "WARNING"
    exit 1
}

# Verify sysprep executable exists
$sysprepPath = "C:\Windows\System32\Sysprep\sysprep.exe"
if (-not (Test-Path $sysprepPath)) {
    Write-Log "Sysprep executable not found at $sysprepPath" "ERROR"
    exit 1
}

Write-Log "Sysprep executable found: $sysprepPath" "SUCCESS"

# Show current system state
Write-Log "Current system information:" "INFO"
try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    Write-Log "  OS: $($os.Caption)" "INFO"
    Write-Log "  Version: $($os.Version)" "INFO"
    Write-Log "  Install Date: $($os.InstallDate)" "INFO"
    
    $lastBootTime = $os.LastBootUpTime
    $uptime = (Get-Date) - $lastBootTime
    Write-Log "  Uptime: $([math]::Round($uptime.TotalHours, 1)) hours" "INFO"
} catch {
    Write-Log "Could not retrieve system information" "WARNING"
}

# Warning about sysprep
Write-Log "WARNING: Sysprep will generalize this system and prepare it for imaging" "WARNING"
Write-Log "This will:" "WARNING"
Write-Log "  - Remove unique system identifiers" "WARNING"
Write-Log "  - Reset Windows activation" "WARNING"
Write-Log "  - Clear user profiles and data" "WARNING"
if (-not $NoShutdown) {
    Write-Log "  - Shutdown the system when complete" "WARNING"
}

# Get user confirmation
if (-not $Force -and $Answer -ne "yes") {
    Write-Host ""
    Write-Host "Do you want to proceed with sysprep? (yes/no): " -NoNewline -ForegroundColor Yellow
    $response = Read-Host
    if ($response -ne "yes") {
        Write-Log "Sysprep cancelled by user" "INFO"
        exit 0
    }
}

Write-Log "Starting sysprep process..." "INFO"

try {
    # Build sysprep arguments
    $arguments = @("/generalize", "/quiet")
    
    if ($NoShutdown) {
        $arguments += "/quit"
        Write-Log "NoShutdown specified - system will not shutdown after sysprep" "INFO"
    } else {
        $arguments += "/shutdown"
        Write-Log "System will shutdown after sysprep completes" "INFO"
    }
    
    $argumentString = $arguments -join " "
    Write-Log "Executing: sysprep.exe $argumentString" "INFO"
    
    # Start the sysprep process
    $sysprepProcess = Start-Process -FilePath $sysprepPath -ArgumentList $arguments -PassThru -NoNewWindow
    
    Write-Log "Sysprep process started with PID: $($sysprepProcess.Id)" "SUCCESS"
    Write-Log "Monitoring sysprep process..." "INFO"
    
    # Monitor the process
    $startTime = Get-Date
    $processRunning = $true
    $lastStatusTime = $startTime
    
    while ($processRunning) {
        Start-Sleep -Seconds 5
        $currentTime = Get-Date
        $elapsed = ($currentTime - $startTime).TotalMinutes
        
        try {
            # Check if process is still running
            $currentProcess = Get-Process -Id $sysprepProcess.Id -ErrorAction SilentlyContinue
            if (-not $currentProcess) {
                $processRunning = $false
                Write-Log "Sysprep process has completed" "SUCCESS"
                break
            } else {
                # Show status every 30 seconds
                if (($currentTime - $lastStatusTime).TotalSeconds -ge 30) {
                    Write-Log "Sysprep is running... (elapsed: $([math]::Round($elapsed, 1)) minutes)" "INFO"
                    $lastStatusTime = $currentTime
                }
            }
            
            # Check for very long running process (over 30 minutes)
            if ($elapsed -gt 30) {
                Write-Log "Sysprep has been running for over 30 minutes" "WARNING"
                Write-Log "This may indicate an issue. Check sysprep logs for details." "WARNING"
                Write-Log "You can run: .\check-sysprep-status.ps1 -ShowFullLogs" "INFO"
                break
            }
            
        } catch {
            $processRunning = $false
            Write-Log "Sysprep process monitoring ended" "INFO"
            break
        }
    }
    
    $totalTime = ((Get-Date) - $startTime).TotalMinutes
    Write-Log "Sysprep process completed in $([math]::Round($totalTime, 1)) minutes" "SUCCESS"
    
    if (-not $NoShutdown) {
        Write-Log "System should shutdown automatically" "INFO"
        Write-Log "If system doesn't shutdown within 5 minutes, check sysprep logs" "INFO"
    }
    
} catch {
    Write-Log "Failed to execute sysprep: $($_.Exception.Message)" "ERROR"
    Write-Log "Check sysprep logs for more details:" "ERROR"
    Write-Log "  C:\Windows\System32\Sysprep\Panther\setupact.log" "ERROR"
    Write-Log "  C:\Windows\System32\Sysprep\Panther\setuperr.log" "ERROR"
    exit 1
}

Write-Log "Sysprep execution completed successfully" "SUCCESS"
