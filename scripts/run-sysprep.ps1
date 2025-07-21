#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Runs Windows Sysprep to prepare the template for cloning
    
.DESCRIPTION
    This script prepares a Windows Server template for cloning by running sysprep
    with appropriate settings to ensure proper boot and disk detection in cloned VMs.
    
    The script automatically searches for unattend.xml in multiple locations:
    - C:\Scripts\unattend.xml (downloaded by prepare-windows-template.ps1)
    - Same directory as this script
    - Repository configs directory
    - User-specified path via parameter
    
    If no unattend.xml is found, it creates a basic one automatically.
    
.PARAMETER Generalize
    Whether to generalize the installation (default: true)
    
.PARAMETER Shutdown
    Whether to shutdown after sysprep (default: true)
    
.EXAMPLE
    .\run-sysprep.ps1
    Run sysprep with default settings
    
.EXAMPLE
    .\run-sysprep.ps1 -Generalize:$false -Shutdown:$false
    Run sysprep without generalizing and without shutdown
    
.EXAMPLE
    .\run-sysprep.ps1 -UnattendPath "D:\custom-unattend.xml"
    Run sysprep with a custom unattend.xml file
#>

param(
    [Parameter()]
    [bool]$Generalize = $true,
    
    [Parameter()]
    [bool]$Shutdown = $true,
    
    [Parameter()]
    [string]$UnattendPath = "C:\Scripts\unattend.xml"
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "Windows Server 2025 Sysprep Preparation Script" -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green

try {
    # Check if running as administrator
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script must be run as Administrator"
    }

    # Check Windows version
    $osVersion = Get-WmiObject -Class Win32_OperatingSystem
    Write-Host "Operating System: $($osVersion.Caption)" -ForegroundColor Cyan
    Write-Host "Version: $($osVersion.Version)" -ForegroundColor Cyan

    # Locate the unattend.xml template file in multiple possible locations
    $possibleUnattendPaths = @(
        "C:\Scripts\unattend.xml",                          # Downloaded by prepare-windows-template.ps1
        (Join-Path $PSScriptRoot "unattend.xml"),          # Same directory as this script
        (Join-Path (Split-Path -Parent $PSScriptRoot) "configs\unattend.xml"),  # Repository configs directory
        $UnattendPath                                       # User-specified path
    )
    
    $sourceUnattendPath = $null
    foreach ($path in $possibleUnattendPaths) {
        if (Test-Path $path) {
            $sourceUnattendPath = $path
            Write-Host "Found unattend.xml template at: $sourceUnattendPath" -ForegroundColor Cyan
            break
        }
    }
    
    if (-not $sourceUnattendPath) {
        Write-Warning "Unattend.xml template not found in any expected location:"
        foreach ($path in $possibleUnattendPaths) {
            Write-Warning "  - $path"
        }
        Write-Host "Creating basic unattend.xml..." -ForegroundColor Yellow
        
        # Fallback: create a minimal unattend.xml if template is missing
        $basicUnattendXml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <SkipUserOOBE>true</SkipUserOOBE>
                <SkipMachineOOBE>true</SkipMachineOOBE>
            </OOBE>
            <TimeZone>UTC</TimeZone>
        </component>
    </settings>
</unattend>
"@
        $basicUnattendXml | Out-File -FilePath $UnattendPath -Encoding UTF8 -Force
        Write-Host "Created basic unattend.xml at: $UnattendPath" -ForegroundColor Green
    } else {
        Write-Host "Using unattend.xml template from: $sourceUnattendPath" -ForegroundColor Cyan
    }

    # Ensure Scripts directory exists
    $scriptsDir = "C:\Scripts"
    if (-not (Test-Path $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
        Write-Host "Created Scripts directory: $scriptsDir" -ForegroundColor Yellow
    }

    # Stop and disable Windows Search service to prevent issues
    Write-Host "Stopping Windows Search service..." -ForegroundColor Cyan
    try {
        Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
        Set-Service -Name "WSearch" -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Host "Windows Search service stopped and disabled" -ForegroundColor Green
    } catch {
        Write-Warning "Could not stop Windows Search service: $($_.Exception.Message)"
    }

    # Clear event logs
    Write-Host "Clearing event logs..." -ForegroundColor Cyan
    Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            if ($_.RecordCount -gt 0) {
                wevtutil.exe cl $_.LogName
            }
        } catch {
            # Ignore errors for logs that can't be cleared
        }
    }
    Write-Host "Event logs cleared" -ForegroundColor Green

    # Clean up temporary files
    Write-Host "Cleaning temporary files..." -ForegroundColor Cyan
    $tempPaths = @(
        "$env:TEMP\*",
        "$env:WINDIR\Temp\*",
        "$env:WINDIR\Prefetch\*",
        "$env:WINDIR\SoftwareDistribution\Download\*"
    )
    
    foreach ($path in $tempPaths) {
        try {
            Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            # Ignore errors for files in use
        }
    }
    Write-Host "Temporary files cleaned" -ForegroundColor Green

    # Run disk cleanup
    Write-Host "Running disk cleanup..." -ForegroundColor Cyan
    try {
        Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:1" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        Write-Host "Disk cleanup completed" -ForegroundColor Green
    } catch {
        Write-Warning "Disk cleanup failed: $($_.Exception.Message)"
    }

    # Prepare sysprep command
    $sysprepPath = "$env:WINDIR\System32\Sysprep\sysprep.exe"
    if (-not (Test-Path $sysprepPath)) {
        throw "Sysprep not found at: $sysprepPath"
    }

    $sysprepArgs = @("/oobe")
    
    if ($Generalize) {
        $sysprepArgs += "/generalize"
    }
    
    if ($Shutdown) {
        $sysprepArgs += "/shutdown"
    } else {
        $sysprepArgs += "/reboot"
    }
    
    if (Test-Path $UnattendPath) {
        $sysprepArgs += "/unattend:$UnattendPath"
    }

    Write-Host "Sysprep command: $sysprepPath $($sysprepArgs -join ' ')" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "IMPORTANT: After sysprep completes and the VM shuts down:" -ForegroundColor Red
    Write-Host "1. Convert the VM to a template in Proxmox" -ForegroundColor Red
    Write-Host "2. Note the template VM ID for Ansible configuration" -ForegroundColor Red
    Write-Host ""
    
    $confirm = Read-Host "Do you want to continue with sysprep? (y/N)"
    if ($confirm -notmatch '^[Yy]') {
        Write-Host "Sysprep cancelled by user" -ForegroundColor Yellow
        return
    }

    Write-Host "Starting sysprep..." -ForegroundColor Green
    Write-Host "This will take several minutes and the system will shutdown/reboot when complete" -ForegroundColor Yellow
    
    # Start sysprep
    Start-Process -FilePath $sysprepPath -ArgumentList $sysprepArgs -Wait -NoNewWindow

} catch {
    Write-Error "Sysprep preparation failed: $($_.Exception.Message)"
    Write-Host "Check the sysprep logs at: $env:WINDIR\System32\Sysprep\Panther" -ForegroundColor Red
    exit 1
}
