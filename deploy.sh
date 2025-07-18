#!/bin/bash
# Ansible Windows AD Deployment Script
# Single tool deployment for VM provisioning and configuration

set -euo pipefail

echo "🚀 Ansible Windows AD Deployment"
echo "================================"

# Configuration
ANSIBLE_DIR="ansible"
VAULT_FILE="${ANSIBLE_DIR}/group_vars/vault.yml"
INVENTORY_FILE="${ANSIBLE_DIR}/inventory.ini"
PLAYBOOK="${ANSIBLE_DIR}/site.yml"

# Function to check prerequisites
check_prerequisites() {
    echo "🔍 Checking prerequisites..."
    
    # Check if ansible is installed
    if ! command -v ansible-playbook &> /dev/null; then
        echo "❌ Ansible not found. Please install Ansible first."
        echo "Run: ./setup-ansible.sh"
        exit 1
    fi
    
    # Check if required collections are installed
    if ! ansible-galaxy collection list | grep -q "community.general"; then
        echo "❌ Required Ansible collections not found."
        echo "Run: ./setup-ansible.sh"
        exit 1
    fi
    
    # Check if vault file exists
    if [[ ! -f "$VAULT_FILE" ]]; then
        echo "❌ Vault file not found: $VAULT_FILE"
        echo "Please create and encrypt the vault file with sensitive variables."
        exit 1
    fi
    
    echo "✅ Prerequisites check passed"
}

# Function to validate configuration
validate_config() {
    echo "🔧 Validating configuration..."
    
    # Check if group_vars/all.yml exists
    if [[ ! -f "${ANSIBLE_DIR}/group_vars/all.yml" ]]; then
        echo "❌ Configuration file not found: ${ANSIBLE_DIR}/group_vars/all.yml"
        exit 1
    fi
    
    # Validate Ansible syntax
    if ! ansible-playbook --syntax-check "$PLAYBOOK" &> /dev/null; then
        echo "❌ Ansible playbook syntax check failed"
        ansible-playbook --syntax-check "$PLAYBOOK"
        exit 1
    fi
    
    echo "✅ Configuration validation passed"
}

# Function to create simple inventory
create_inventory() {
    echo "📝 Creating inventory file..."
    
    cat > "$INVENTORY_FILE" << EOF
[localhost]
localhost ansible_connection=local

[domain_controllers]
# VMs will be added dynamically during playbook execution

[primary_dc]
# Primary DC will be added dynamically

[additional_dc]
# Additional DCs will be added dynamically
EOF
    
    echo "✅ Inventory file created: $INVENTORY_FILE"
}

# Function to run the deployment
deploy() {
    local action="${1:-deploy}"
    
    echo "🚀 Starting deployment with action: $action"
    
    case "$action" in
        "provision")
            echo "📦 Provisioning VMs only..."
            ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK" \
                --ask-vault-pass \
                --tags "provision" \
                -v
            ;;
        "configure")
            echo "⚙️  Configuring existing VMs only..."
            ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK" \
                --ask-vault-pass \
                --tags "configure" \
                -v
            ;;
        "deploy")
            echo "🏗️  Full deployment (provision + configure)..."
            ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK" \
                --ask-vault-pass \
                -v
            ;;
        "validate")
            echo "✅ Validation only..."
            ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK" \
                --ask-vault-pass \
                --tags "validate" \
                -v
            ;;
        "dry-run")
            echo "🧪 Dry run (check mode)..."
            ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK" \
                --ask-vault-pass \
                --check \
                --diff \
                -v
            ;;
        *)
            echo "❌ Unknown action: $action"
            echo "Valid actions: provision, configure, deploy, validate, dry-run"
            exit 1
            ;;
    esac
}

# Function to cleanup VMs
cleanup() {
    echo "🧹 Cleaning up VMs..."
    echo "⚠️  This will destroy all domain controller VMs!"
    read -p "Are you sure? (yes/no): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        ansible-playbook -i "$INVENTORY_FILE" \
            "${ANSIBLE_DIR}/cleanup-vms.yml" \
            --ask-vault-pass \
            -v
    else
        echo "Cleanup cancelled."
    fi
}

# Function to show help
show_help() {
    cat << EOF
    echo "Ansible Windows AD Deployment"

Usage: $0 [COMMAND] [OPTIONS]

Commands:
  deploy      Full deployment (provision VMs + configure AD) [default]
  provision   Provision VMs only
  configure   Configure existing VMs only  
  validate    Validate deployment
  dry-run     Show what would be changed without making changes
  cleanup     Destroy all VMs (interactive)
  help        Show this help

Examples:
  $0                    # Full deployment
  $0 deploy             # Full deployment  
  $0 provision          # Just create VMs
  $0 configure          # Just configure existing VMs
  $0 dry-run            # Test without changes
  $0 cleanup            # Remove all VMs

Requirements:
  - Ansible installed with required collections
  - Proxmox environment accessible
  - Windows Server 2025 template prepared
  - group_vars/vault.yml encrypted with credentials

Files:
  - ansible/group_vars/all.yml    # Main configuration
  - ansible/group_vars/vault.yml  # Encrypted credentials
  - ansible/site.yml # Main playbook
EOF
}

# Main script logic
main() {
    local command="${1:-deploy}"
    
    case "$command" in
        "help"|"-h"|"--help")
            show_help
            exit 0
            ;;
        "cleanup")
            check_prerequisites
            cleanup
            ;;
        *)
            check_prerequisites
            validate_config
            create_inventory
            deploy "$command"
            ;;
    esac
    
    echo ""
    echo "✅ Operation completed successfully!"
    echo "📚 Check the documentation for next steps."
}

# Run main function with all arguments
main "$@"
