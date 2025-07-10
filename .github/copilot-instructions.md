<!-- Use this file to provide workspace-specific custom instructions to Copilot. For more details, visit https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructionsmd-file -->

# Proxmox Windows Server 2025 AD DC Terraform Project

This project uses Terraform to deploy Windows Server 2025 Active Directory Domain Controllers on Proxmox VE.

## Key Guidelines for this Project:

1. **Infrastructure as Code**: All infrastructure should be defined in Terraform files
2. **Modular Design**: Use Terraform modules for reusable components
3. **Security First**: Never hardcode sensitive values, use variables and tfvars files
4. **Documentation**: All resources should be well-documented with comments
5. **Best Practices**: Follow Terraform and PowerShell best practices
6. **Version Control**: Use .gitignore to exclude sensitive files and state files

## Project Structure:
- `main.tf` - Main Terraform configuration
- `variables.tf` - Input variables definition
- `outputs.tf` - Output values
- `terraform.tfvars.example` - Example variable values
- `modules/` - Reusable Terraform modules
- `scripts/` - PowerShell scripts for post-deployment configuration
- `docs/` - Additional documentation

## PowerShell Scripts:
- Focus on idempotent operations
- Include proper error handling
- Use Write-Host for logging
- Support both domain creation and additional DC promotion
