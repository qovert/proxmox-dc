#!/bin/bash
set -e

echo "Setting up Ansible for Windows AD deployment..."

# Check if Ansible is installed
if ! command -v ansible &> /dev/null; then
    echo "Installing Ansible..."
    pip3 install ansible pywinrm requests-kerberos
else
    echo "Ansible is already installed: $(ansible --version | head -1)"
fi

# Install required collections
echo "Installing Ansible collections..."
ansible-galaxy collection install ansible.windows --force
ansible-galaxy collection install community.windows --force
ansible-galaxy collection install microsoft.ad --force
# Note: proxmox_kvm module moved from community.general to community.proxmox in 2024
ansible-galaxy collection install community.proxmox --force

# Create required directories
echo "Creating Ansible directory structure..."
mkdir -p ansible/group_vars
mkdir -p ansible/host_vars

# Verify roles exist
echo "Verifying Ansible roles..."
required_roles=("windows_base" "active_directory" "dns_server" "monitoring")
for role in "${required_roles[@]}"; do
    if [ -d "ansible/roles/$role" ]; then
        echo "✅ Role '$role' found"
    else
        echo "⚠️  Role '$role' missing - this may cause deployment issues"
    fi
done

# Create vault password file if it doesn't exist
if [ ! -f ansible/vault_pass ]; then
    echo "Creating vault password file..."
    echo "changeme123" > ansible/vault_pass
    chmod 600 ansible/vault_pass
    echo "⚠️  IMPORTANT: Change the password in ansible/vault_pass before deployment!"
fi

# Create vault.yml if it doesn't exist
if [ ! -f ansible/group_vars/vault.yml ]; then
    echo "Creating vault template file..."
    cat > ansible/group_vars/vault.yml << 'EOF'
---
# Ansible Vault file for sensitive variables
# This file will be encrypted after you update the passwords

# Proxmox Credentials
vault_proxmox_password: "CHANGE-ME-proxmox-api-password"

# Active Directory Credentials  
vault_admin_password: "CHANGE-ME-windows-admin-password"
vault_dsrm_password: "CHANGE-ME-dsrm-password"

# SSH Key (replace with your actual public key)
vault_ssh_public_key: "CHANGE-ME-ssh-ed25519-AAAAB3NzaC1yc2E..."
EOF
    echo "📝 Created ansible/group_vars/vault.yml template"
    echo "⚠️  IMPORTANT: Update passwords in vault.yml, then encrypt it!"
elif ! grep -q '^\$ANSIBLE_VAULT' ansible/group_vars/vault.yml; then
    echo "⚠️  Found unencrypted vault.yml file"
    echo "📝 Please update passwords and encrypt with: ansible-vault encrypt ansible/group_vars/vault.yml --vault-password-file ansible/vault_pass"
else
    echo "✅ Encrypted vault.yml found"
fi

echo "✅ Ansible setup complete!"
echo ""
echo "Next steps:"
echo "1. Update ansible/vault_pass with a secure password"
echo "2. Create inventory file: cp ansible/inventory-minimal.yml.example ansible/inventory.yml"
echo "3. Configure ansible/group_vars/all.yml with your environment settings"
echo "4. Update passwords in ansible/group_vars/vault.yml"
echo "5. Encrypt the vault: ansible-vault encrypt ansible/group_vars/vault.yml --vault-password-file ansible/vault_pass"
echo "6. Run './deploy.sh' to deploy infrastructure and configuration"
echo ""
echo "Alternative deployment commands:"
echo "  ./deploy.sh provision  # Create VMs only"
echo "  ./deploy.sh configure  # Configure AD on existing VMs"
echo "  ./deploy.sh validate   # Test deployment"
echo ""
echo "Vault management commands:"
echo "  ansible-vault edit ansible/group_vars/vault.yml --vault-password-file ansible/vault_pass    # Edit encrypted vault"
echo "  ansible-vault view ansible/group_vars/vault.yml --vault-password-file ansible/vault_pass    # View encrypted vault"
echo "  ansible-vault encrypt ansible/group_vars/vault.yml --vault-password-file ansible/vault_pass # Encrypt vault file"
