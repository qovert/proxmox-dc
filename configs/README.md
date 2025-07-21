# Configuration Files

This directory contains configuration files used by the Windows Server 2025 template preparation script.

## Files

### `sshd_config`

**Purpose**: Main OpenSSH Server configuration for Windows Server 2025  
**Usage**: Downloaded during SSH server setup in `prepare-windows-template.ps1`  
**Features**:

- Key-based authentication only (no passwords)
- Separate authorized_keys file for administrators
- Secure logging and connection settings
- SFTP subsystem support

### `sshd_config_minimal`

**Purpose**: Minimal fallback SSH configuration  
**Usage**: Used as fallback if main SSH config fails validation  
**Features**:
- Bare minimum settings for SSH functionality
- Used when `sshd -t` test fails on main config

### `cloudbase-init.conf`

**Purpose**: CloudBase-Init configuration for cloud integration  
**Usage**: Downloaded during CloudBase-Init setup in `prepare-windows-template.ps1`  
**Features**:

- Administrator user injection
- Multiple config drive support (CD-ROM, raw HDD, VFAT)
- Comprehensive logging
- Network configuration from DHCP

### `unattend.xml`

**Purpose**: Windows Sysprep unattended answer file for template preparation  
**Usage**: Used by `run-sysprep.ps1` script during template finalization  
**Features**:
- OOBE (Out-of-Box Experience) automation
- Administrator password configuration (encoded)
- Regional settings (en-US locale)
- Storage device policy configurations
- Driver path specifications
- Skips interactive setup screens

**Security Notes**:
- Contains encoded Administrator password: `Reset@123!AdministratorPassword`
- Password can be customized by re-encoding with desired value
- Used during sysprep generalization process

**Customization**:
To change the Administrator password:
1. Encode your password using PowerShell:
   ```powershell
   [System.Text.Encoding]::Unicode.GetBytes("YourNewPassword") | ForEach-Object { [System.Convert]::ToBase64String($_) }
   ```
2. Replace the `<Value>` content in the `<AdministratorPassword>` section

## GitHub Integration

These configuration files are automatically downloaded from the GitHub repository during template preparation:

```powershell
# SSH Configuration
https://raw.githubusercontent.com/qovert/proxmox-dc/main/configs/sshd_config

# Minimal SSH Configuration (fallback)
https://raw.githubusercontent.com/qovert/proxmox-dc/main/configs/sshd_config_minimal

# CloudBase-Init Configuration  
https://raw.githubusercontent.com/qovert/proxmox-dc/main/configs/cloudbase-init.conf
```

## Benefits of External Configuration Files

1. **Maintainability**: Easy to update configurations without modifying the main script
2. **Version Control**: Track configuration changes separately from script logic
3. **Reusability**: Configurations can be used by other automation tools
4. **Validation**: Configurations can be tested independently
5. **Modularity**: Different environment-specific configurations can be maintained

## Fallback Behavior

If GitHub downloads fail (no internet connectivity, repository issues, etc.), the script includes local fallback configurations to ensure the template preparation continues successfully.

## Testing Configurations

### SSH Configuration Testing

```powershell
# Test SSH configuration syntax
C:\Windows\System32\OpenSSH\sshd.exe -t -f sshd_config
```

### CloudBase-Init Configuration Testing

```powershell
# Validate CloudBase-Init configuration
C:\Program Files\Cloudbase Solutions\Cloudbase-Init\Python\Scripts\cloudbase-init.exe --config-file cloudbase-init.conf --check-config
```
