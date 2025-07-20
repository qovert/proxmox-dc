# Windows Server 2025 Active Directory Domain Controller on Proxmox

An **Ansible-based infrastructure-as-code solution** for deploying and managing enterprise-grade Windows Server 2025 Active Directory Domain Controllers on Proxmox VE.

## 🎯 Project Goals

This project solves the challenge of **consistent, repeatable Active Directory deployments** in virtualized environments by providing:

- **Single-tool automation** using pure Ansible (no multi-tool complexity)
- **Production-ready security** with SSH key-based authentication and encrypted secrets
- **Enterprise-grade monitoring** with automated health checks and reporting
- **Scalable architecture** supporting multiple domain controllers with proper redundancy
- **Template-based efficiency** for rapid deployment across environments

## 🏗️ Architecture Overview

### Design Philosophy

- **Infrastructure as Code**: All infrastructure and configuration defined in version control
- **Modular Design**: Reusable Ansible roles for different components and environments
- **Security First**: Modern SSH-based authentication, encrypted secrets, security hardening
- **Production Focus**: Comprehensive monitoring, backup strategies, and operational excellence
- **Single Tool**: Pure Ansible approach eliminates tool complexity and state management issues

### Technology Stack

```text
🔧 Automation:     Ansible (infrastructure + configuration)
🖥️  Virtualization: Proxmox VE
💾 Operating System: Windows Server 2025 (Server Core)
🌐 Networking:     OpenSSH + SSH keys (no WinRM)
🔐 Security:       Ansible Vault + SSH authentication
📊 Monitoring:     PowerShell-based health checks
```

### Deployment Flow

```text
1. Environment Setup (setup-ansible.sh)
   ├── Install Ansible and required collections
   ├── Create directory structure
   └── Validate role dependencies

2. Infrastructure Provisioning (deploy.sh)
   ├── Create VMs from Windows Server 2025 template
   ├── Configure networking and storage
   └── Initialize SSH connectivity

3. Configuration Management (Ansible Roles)
   ├── windows_base: System hardening and optimization
   ├── active_directory: AD DS installation and forest setup
   ├── dns_server: DNS configuration with external forwarders
   └── monitoring: Health checks and performance monitoring

4. Operational Excellence
   ├── Automated health monitoring and reporting
   ├── Backup configuration and scheduling
   └── Security policies and compliance
```

## 📁 Repository Structure

```text
proxmox-dc/
├── 🎯 ENTRY POINTS
│   ├── setup-ansible.sh       # One-time environment setup
│   ├── deploy.sh              # Deployment orchestration
│   └── README.md              # This file - project overview
│
├── 🎭 ANSIBLE AUTOMATION
│   └── ansible/
│       ├── site.yml           # Main deployment playbook
│       ├── cleanup-vms.yml    # Infrastructure teardown
│       ├── ansible.cfg        # Ansible configuration
│       ├── group_vars/        # Configuration management
│       │   ├── all.yml        # Main configuration variables
│       │   └── vault.yml      # Encrypted secrets (create this)
│       └── roles/             # Modular configuration roles
│           ├── windows_base/  # Base system configuration
│           ├── active_directory/ # AD DS installation
│           ├── dns_server/    # DNS setup with external scripts
│           └── monitoring/    # Health checks and reporting
│
├── 📜 POWERSHELL SCRIPTS
│   └── scripts/
│       ├── prepare-windows-template.ps1  # Template automation
│       ├── configure-adds.ps1            # AD DS installation
│       ├── initial-setup.ps1             # System preparation
│       ├── post-config.ps1               # Post-deployment tasks
│       └── SCRIPT_DOCUMENTATION.md       # Script reference
│
├── ⚙️ CONFIGURATIONS
│   └── configs/
│       ├── sshd_config           # OpenSSH server configuration
│       ├── sshd_config_minimal   # SSH fallback configuration
│       └── cloudbase-init.conf   # Cloud-init configuration
│
└── 📚 DOCUMENTATION
    └── docs/
        ├── README.md                 # Documentation navigation
        ├── usage-guide.md            # Complete deployment guide
        └── template-preparation.md   # Template setup instructions
```

## 🚀 Key Features & Benefits

### Why This Approach?

#### Single Tool Simplicity

- Pure Ansible approach eliminates multi-tool complexity
- No Terraform state management or tool integration issues
- Consistent debugging and troubleshooting experience

#### Modern Security

- SSH key-based authentication (industry standard)
- No legacy WinRM dependencies or password management
- Encrypted secrets with Ansible Vault
- Security hardening built into all roles

#### Production Ready

- Comprehensive error handling and retry mechanisms
- Automated health monitoring and alerting
- Backup strategies and disaster recovery procedures
- Ansible-lint compliance and code quality standards

#### Operational Excellence

- Idempotent operations (safe to re-run)
- Dynamic inventory management
- Multiple deployment modes (provision, configure, validate)
- Comprehensive logging and diagnostics

### Enterprise-Grade Features

- **Professional Development**: Full PowerShell IDE support with IntelliSense
- **Maintainable Code**: External PowerShell scripts can be unit tested independently
- **Scalable Architecture**: Modular role-based design for different environments
- **Secure Communications**: Modern SSH-based authentication instead of legacy WinRM
- **Comprehensive Monitoring**: Automated health checks with CSV/HTML reporting

## 🏃 Quick Start

```bash
# 1. Clone and setup
git clone https://github.com/qovert/proxmox-dc.git
cd proxmox-dc
./setup-ansible.sh

# 2. Configure (edit these files)
nano ansible/group_vars/all.yml     # Main settings
nano ansible/group_vars/vault.yml   # Secrets (then encrypt)

# 3. Deploy
./deploy.sh                         # Full deployment
```

📖 **For detailed usage instructions, see [docs/usage-guide.md](docs/usage-guide.md)**

## 📋 Prerequisites

### Quick Checklist

- [ ] **Proxmox VE** cluster with sufficient resources
- [ ] **Windows Server 2025 template** properly prepared ([guide](docs/template-preparation.md))
- [ ] **Ansible >= 2.9** with required collections
- [ ] **SSH key pair** for authentication
- [ ] **Network planning** (static IPs, DNS forwarders, firewall rules)

### Template Requirements

Your Windows Server 2025 template must have:

- [ ] Server Core installation (recommended)
- [ ] OpenSSH Server with key-based authentication
- [ ] PowerShell 7 installed
- [ ] CloudBase-Init configured
- [ ] Proxmox Guest Agent running
- [ ] System properly sysprepped

## 🎚️ Deployment Options

The `deploy.sh` script supports multiple deployment modes:

```bash
./deploy.sh              # Full deployment (provision + configure)
./deploy.sh provision    # Create VMs only
./deploy.sh configure    # Configure existing VMs only  
./deploy.sh validate     # Test and validate deployment
./deploy.sh dry-run      # Preview changes without applying
./deploy.sh cleanup      # Remove all VMs (with confirmation)
```

## 🔍 What Makes This Different?

### vs. Manual Deployment

- **Consistency**: Eliminates human error and configuration drift
- **Speed**: Deploy multiple DCs in minutes instead of hours
- **Documentation**: Infrastructure and configuration are self-documenting

### vs. Other Automation Tools

- **Simplicity**: Single tool (Ansible) for everything
- **Security**: Modern SSH authentication vs. legacy protocols
- **Maintainability**: Modular roles and external scripts
- **Reliability**: Built-in error handling and retry mechanisms

### vs. GUI-Based Solutions

- **Reproducibility**: Version-controlled infrastructure as code
- **Scalability**: Deploy 1 or 10 DCs with same effort
- **Integration**: Easy to integrate with CI/CD pipelines
- **Auditability**: All changes tracked in version control

## 🤝 Contributing

This project follows infrastructure-as-code best practices:

1. **Fork** the repository
2. **Create** a feature branch
3. **Test** changes thoroughly in a lab environment
4. **Document** any new features or changes
5. **Submit** a pull request with detailed description

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- **Proxmox VE** community for virtualization platform
- **Ansible** community for Windows automation modules
- **Windows Server** team for PowerShell and OpenSSH integration
- **Active Directory** best practices and security guidelines

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:

1. Check the troubleshooting section
2. Review the logs
3. Open an issue in the repository
4. Provide full error messages and environment details

## Acknowledgments

- Proxmox VE community
- Ansible community for Windows modules
- Proxmox development team
- Windows Server documentation
- Active Directory best practices guides
