#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Runs Windows Sysprep to prepare the template for cloning
    
.DESCRIPTION
    This script prepares a Windows Server template for cloning by running sysprep
    with appropriate settings to ensure proper boot and disk detection in cloned VMs.
    
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

    # Create unattend.xml for better cloning behavior
    $unattendXml = @"
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>1</ProtectYourPC>
                <SkipUserOOBE>true</SkipUserOOBE>
                <SkipMachineOOBE>true</SkipMachineOOBE>
            </OOBE>
            <UserAccounts>
                <AdministratorPassword>
                    <Value>UgBlAHMAZQB0AEAAMQAyADMAIQBBAGQAbQBpAG4AaQBzAHQAcgBhAHQAbwByAFAAYQBzAHMAdwBvAHIAZAA=</Value>
                    <PlainText>false</PlainText>
                </AdministratorPassword>
            </UserAccounts>
            <TimeZone>UTC</TimeZone>
        </component>
    </settings>
    <settings pass="specialize">
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <RunSynchronous>
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>cmd.exe /c "reg add HKLM\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies /v WriteProtect /t REG_DWORD /d 0 /f"</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Path>cmd.exe /c "sc config Disk start= boot"</Path>
                </RunSynchronousCommand>
                <RunSynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <Path>cmd.exe /c "sc config Fastfat start= auto"</Path>
                </RunSynchronousCommand>
            </RunSynchronous>
        </component>
        <component name="Microsoft-Windows-PnpCustomizationsNonWinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <DriverPaths>
                <PathAndCredentials wcm:action="add" wcm:keyValue="1">
                    <Path>C:\Windows\System32\DriverStore\FileRepository</Path>
                </PathAndCredentials>
            </DriverPaths>
        </component>
    </settings>
</unattend>
"@

    # Ensure Scripts directory exists
    $scriptsDir = "C:\Scripts"
    if (-not (Test-Path $scriptsDir)) {
        New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
        Write-Host "Created Scripts directory: $scriptsDir" -ForegroundColor Yellow
    }

    # Write unattend.xml
    Write-Host "Creating unattend.xml for sysprep..." -ForegroundColor Cyan
    $unattendXml | Out-File -FilePath $UnattendPath -Encoding UTF8 -Force
    Write-Host "Created: $UnattendPath" -ForegroundColor Green

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
