# Windows Template Preparation Script Documentation

## Overview

The `prepare-windows-template.ps1` script has been enhanced with comprehensive PowerShell advanced function help documentation. This script automates the preparation of Windows Server 2025 templates for Proxmox VE.

## Getting Help

### Basic Help
```powershell
Get-Help .\prepare-windows-template.ps1
```

### Detailed Help with Examples
```powershell
Get-Help .\prepare-windows-template.ps1 -Full
```

### View Examples Only
```powershell
Get-Help .\prepare-windows-template.ps1 -Examples
```

### Parameter-Specific Help
```powershell
Get-Help .\prepare-windows-template.ps1 -Parameter SSHPublicKey
```

## Usage Examples

### Basic Usage

```powershell
# Run with all default settings
.\prepare-windows-template.ps1

# Run with SSH public key file
.\prepare-windows-template.ps1 -SSHPublicKey "C:\Users\admin\.ssh\id_ed25519.pub"

# Skip Windows Updates to save time
.\prepare-windows-template.ps1 -SkipWindowsUpdates

# Skip CloudBase-Init and Sysprep for manual preparation
.\prepare-windows-template.ps1 -SkipCloudbaseInit -SkipSysprep

# Development/testing mode (fastest)
.\prepare-windows-template.ps1 -SkipWindowsUpdates -SkipSysprep
```

## Script Features

### Enhanced Documentation
- ✅ Comprehensive synopsis and description
- ✅ Detailed parameter documentation with validation
- ✅ Multiple usage examples
- ✅ Links to related resources
- ✅ Version and author information
- ✅ SSH key file path support with cross-platform compatibility

### Improved Functions
- ✅ All internal functions now have proper help documentation
- ✅ Parameter validation and type checking
- ✅ Enhanced error handling and logging
- ✅ SSH key file validation with cross-platform support
- ✅ Administrator privilege checking

### Better User Experience
- ✅ Colored output with timestamps
- ✅ Parameter validation feedback
- ✅ Clear progress indicators
- ✅ Helpful error messages with guidance
- ✅ Post-completion instructions

## Prerequisites

- Windows Server 2025 Core installation
- PowerShell 5.1 or later
- Administrator privileges
- Internet connectivity

## Post-Execution Steps

1. **Test SSH connectivity**: `ssh Administrator@<VM_IP>`
2. **Run Sysprep** (if skipped): `.\run-sysprep.ps1`
3. **Shutdown VM**
4. **Convert to template** in Proxmox VE
5. **Test template** by creating new VMs

## Error Handling

The script now includes comprehensive error handling:
- Clear error messages with context
- Helpful guidance for common issues
- Links to documentation and support
- Proper exit codes for automation

## Function Documentation

All internal functions now include proper PowerShell help:
- `Write-Log` - Enhanced logging with levels
- `Test-InternetConnection` - Connectivity testing
- `Install-MsiPackage` - MSI installation helper
- `Add-ToPath` - PATH environment management
- `Set-ServiceConfiguration` - Service management
- `Set-SSHPublicKey` - SSH key management
- `Get-FileFromUrl` - Download with retry logic
- `Show-Help` - Interactive help display
