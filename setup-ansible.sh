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

# Install Windows collections
echo "Installing Ansible Windows collections..."
ansible-galaxy collection install ansible.windows --force
ansible-galaxy collection install community.windows --force
ansible-galaxy collection install microsoft.ad --force

# Create required directories
echo "Creating Ansible directory structure..."
mkdir -p ansible/group_vars
mkdir -p ansible/host_vars
mkdir -p ansible/roles/dns_server/tasks
mkdir -p ansible/roles/monitoring/tasks

# Create missing role files
echo "Creating placeholder role files..."

# DNS Server role
cat > ansible/roles/dns_server/tasks/main.yml << 'EOF'
---
# DNS Server Configuration Role
- name: Configure DNS forwarders
  win_powershell:
    script: |
      $forwarders = @({{ dns_forwarders | map('quote') | join(', ') }})
      Set-DnsServerForwarder -IPAddress $forwarders
  when: is_primary_dc | default(false)

- name: Configure DNS scavenging
  win_powershell:
    script: |
      Set-DnsServerScavenging -ScavengingState $true -ScavengingInterval 7.00:00:00
      Set-DnsServerZoneAging -Name "{{ domain_name }}" -Aging $true -ScavengeServers "{{ ansible_host }}"
  when: is_primary_dc | default(false)

- name: Create reverse lookup zones
  win_powershell:
    script: |
      $network = "{{ ansible_host.split('.')[0:3] | join('.') }}"
      $reverseZone = "$($network.Split('.')[2]).$($network.Split('.')[1]).$($network.Split('.')[0]).in-addr.arpa"
      Add-DnsServerPrimaryZone -Name $reverseZone -ReplicationScope Domain -DynamicUpdate Secure
  when: is_primary_dc | default(false)
  ignore_errors: yes
EOF

# Monitoring role
cat > ansible/roles/monitoring/tasks/main.yml << 'EOF'
---
# Monitoring and Health Check Role
- name: Create monitoring scripts directory
  win_file:
    path: "C:\\Scripts\\Monitoring"
    state: directory

- name: Deploy health check script
  win_copy:
    content: |
      # AD Health Check Script
      $results = @()
      
      # Check AD services
      $services = @('NTDS', 'DNS', 'Netlogon', 'KDC')
      foreach ($service in $services) {
          $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
          $results += [PSCustomObject]@{
              Check = "Service_$service"
              Status = if ($svc) { $svc.Status } else { "NotFound" }
              Result = if ($svc -and $svc.Status -eq "Running") { "PASS" } else { "FAIL" }
          }
      }
      
      # Check AD replication
      try {
          $replInfo = Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME
          $results += [PSCustomObject]@{
              Check = "AD_Replication"
              Status = "Partners: $($replInfo.Count)"
              Result = if ($replInfo.Count -gt 0) { "PASS" } else { "WARN" }
          }
      } catch {
          $results += [PSCustomObject]@{
              Check = "AD_Replication"
              Status = "Error: $($_.Exception.Message)"
              Result = "FAIL"
          }
      }
      
      # Output results
      $results | Format-Table -AutoSize
      $results | Export-Csv -Path "C:\Scripts\Monitoring\health-$(Get-Date -Format 'yyyyMMdd-HHmm').csv" -NoTypeInformation
    dest: "C:\\Scripts\\Monitoring\\health-check.ps1"

- name: Create scheduled task for health monitoring
  win_scheduled_task:
    name: "AD Health Check"
    description: "Daily Active Directory health check"
    actions:
      - path: "powershell.exe"
        arguments: "-ExecutionPolicy Bypass -File C:\\Scripts\\Monitoring\\health-check.ps1"
    triggers:
      - type: daily
        start_time: "06:00"
    username: SYSTEM
    state: present
    enabled: yes
EOF

# Create vault password file if it doesn't exist
if [ ! -f ansible/vault_pass ]; then
    echo "Creating vault password file..."
    echo "changeme123" > ansible/vault_pass
    chmod 600 ansible/vault_pass
    echo "⚠️  IMPORTANT: Change the password in ansible/vault_pass before deployment!"
fi

echo "✅ Ansible setup complete!"
echo ""
echo "Next steps:"
echo "1. Update ansible/vault_pass with a secure password"
echo "2. Run 'terraform init && terraform plan' to see the deployment plan"
echo "3. Run 'terraform apply' to deploy infrastructure with Ansible configuration"
echo ""
echo "To run only Ansible configuration (after VMs are deployed):"
echo "  cd ansible && ansible-playbook -i inventory.yml site.yml"
