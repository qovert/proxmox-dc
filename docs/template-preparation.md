# Windows Server 2025 Template Preparation Guide

This guide helps you create a proper Windows Server 2025 template that works reliably with Terraform cloning.

## Prerequisites

- Windows Server 2025 installed on a Proxmox VM
- PowerShell 7 installed
- OpenSSH Server configured
- CloudBase-Init installed

## Step-by-Step Template Preparation

### 1. Run the Template Preparation Script

First, run the main template preparation script:

```powershell
# Run as Administrator
.\scripts\prepare-windows-template.ps1
```

### 2. Verify System Configuration

Ensure these services are properly configured:

```powershell
# Check critical services
Get-Service sshd, cloudbase-init | Format-Table Name, Status, StartType

# Verify PowerShell 7
pwsh --version

# Check Windows Update status
Get-WindowsUpdate -Verbose
```

### 3. Clean System Before Sysprep

Remove any temporary files and reset the system:

```powershell
# Clear temp files
Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:WINDIR\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue

# Stop non-essential services
Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
Set-Service -Name "WSearch" -StartupType Disabled
```

### 4. Run Sysprep

Use the provided sysprep script to properly prepare the template:

```powershell
# Run the sysprep script (this will shutdown the VM)
.\scripts\run-sysprep.ps1
```

The sysprep script will:
- Create an unattend.xml file for proper cloning
- Configure storage device policies
- Clear event logs and temporary files
- Run Windows sysprep with proper parameters

### 5. Convert to Template in Proxmox

After sysprep completes and the VM shuts down:

1. **In Proxmox Web UI:**
   - Right-click the VM
   - Select "Convert to template"
   - Note the VM ID (e.g., 9000)

2. **Update Terraform Configuration:**
   ```hcl
   # In terraform.tfvars
   windows_template_vm_id = 9000  # Use the actual template VM ID
   ```

## Troubleshooting Boot Issues

If cloned VMs fail to boot with "system disk" errors:

### Check Template Disk Configuration

The template should have:
- **BIOS**: SeaBIOS (not UEFI) for better compatibility
- **SCSI Controller**: VirtIO SCSI
- **OS Disk**: On scsi0 interface
- **Boot Order**: scsi0 first

### Verify Terraform Clone Settings

Ensure your Terraform configuration has:

```hcl
resource "proxmox_virtual_environment_vm" "windows_dc" {
  clone {
    vm_id = var.windows_template_vm_id
    full  = true  # Full clone, not linked
  }
  
  bios = "seabios"  # Match template BIOS type
  boot_order = ["scsi0"]
  
  # OS disk - inherit size from template
  disk {
    datastore_id = var.storage_pool
    interface    = "scsi0"
    iothread     = true
    ssd          = true
    cache        = "writeback"
    # No size specified - inherits from template
  }
}
```

### Common Issues and Solutions

1. **"Error system disks found"**
   - Template wasn't properly sysprepped
   - Disk configuration mismatch between template and clone
   - Solution: Re-run sysprep or check BIOS/boot settings

2. **Boot loop or repair dialog**
   - BIOS type mismatch (UEFI vs SeaBIOS)
   - Boot order incorrect
   - Solution: Match template BIOS settings exactly

3. **Cloud-init not working**
   - CloudBase-Init not properly installed
   - Solution: Reinstall CloudBase-Init before sysprep

## Testing the Template

Test your template by manually cloning it in Proxmox:

1. Right-click template → Clone
2. Set a test VM ID and name
3. Start the cloned VM
4. Verify it boots properly and cloud-init works

Only use the template with Terraform after manual cloning works correctly.

## Template Maintenance

Periodically update your template:

1. Clone the template to a new VM
2. Install Windows updates
3. Update applications (PowerShell, OpenSSH, CloudBase-Init)
4. Run sysprep again
5. Convert back to template

This ensures your infrastructure deployments use current, secure base images.
