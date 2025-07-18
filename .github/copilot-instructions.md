<!-- Use this file to provide workspace-specific custom instructions to Copilot. For more details, visit https://code.visualstudio.com/docs/copilot/copilot-customization#_use-a-githubcopilotinstructionsmd-file -->

# Proxmox Windows Server 2025 AD DC Pure Ansible Project

This project uses Pure Ansible to deploy Windows Server 2025 Active Directory Domain Controllers on Proxmox VE.

## Key Guidelines for this Project:

1. **Infrastructure as Code**: All infrastructure should be defined in Ansible playbooks
2. **Modular Design**: Use Ansible roles for reusable components
3. **Security First**: Implement proper security configurations and use Ansible Vault
4. **Documentation**: Keep documentation current and comprehensive
5. **Best Practices**: Follow Ansible and PowerShell best practices
6. **Version Control**: Use .gitignore to exclude sensitive files and state files

## Project Structure:
- `ansible/pure-ansible-site.yml` - Main Ansible playbook
- `ansible/group_vars/` - Configuration variables
- `ansible/roles/` - Ansible roles for different components
- `deploy.sh` - Main deployment script
- `ansible/cleanup-vms.yml` - Cleanup playbook
- `scripts/` - PowerShell scripts for post-deployment configuration
- `docs/` - Additional documentation

## PowerShell Scripts:
- Focus on idempotent operations
- Include proper error handling
- Use Write-Host for logging
- Support both domain creation and additional DC promotion
