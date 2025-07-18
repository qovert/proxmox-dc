# Pure Ansible Approach: VM Provisioning + Configuration

## Overview

Replace Terraform entirely with Ansible using the `community.general.proxmox_kvm` module to handle both infrastructure and configuration.

## Ansible Proxmox Modules

### VM Management
- `community.general.proxmox_kvm` - Create/manage VMs
- `community.general.proxmox_template` - Manage templates
- `community.general.proxmox_storage_info` - Query storage info
- `community.general.proxmox_node_info` - Query node information

## Pure Ansible Playbook Structure

```yaml
---
# site.yml - Complete deployment with pure Ansible
- name: Deploy Windows AD Infrastructure with Pure Ansible
  hosts: localhost
  gather_facts: no
  vars:
    proxmox_host: "proxmox.example.com"
    proxmox_user: "ansible@pve"
    proxmox_password: "{{ vault_proxmox_password }}"
    domain_controllers:
      - name: "dc-01" 
        vmid: 201
        ip: "192.168.1.10"
        primary: true
      - name: "dc-02"
        vmid: 202 
        ip: "192.168.1.11"
        primary: false

  tasks:
    # Phase 1: Infrastructure Provisioning
    - name: Create Windows Domain Controllers
      community.general.proxmox_kvm:
        api_host: "{{ proxmox_host }}"
        api_user: "{{ proxmox_user }}" 
        api_password: "{{ proxmox_password }}"
        name: "{{ item.name }}"
        vmid: "{{ item.vmid }}"
        node: "proxmox-01"
        clone: "windows-server-2025-template"
        full: true
        cores: 4
        memory: 8192
        net:
          net0: "virtio,bridge=vmbr0,ip={{ item.ip }}/24,gw=192.168.1.1"
        scsi:
          scsi0: "local-lvm:80"  # OS disk
          scsi1: "local-lvm:40"  # Data disk
        ciuser: "Administrator"
        cipassword: "{{ vault_admin_password }}"
        sshkeys: "{{ ssh_public_key }}"
        state: present
        timeout: 300
      loop: "{{ domain_controllers }}"
      register: vm_creation

    - name: Start Domain Controllers
      community.general.proxmox_kvm:
        api_host: "{{ proxmox_host }}"
        api_user: "{{ proxmox_user }}"
        api_password: "{{ proxmox_password }}"
        vmid: "{{ item.vmid }}"
        state: started
      loop: "{{ domain_controllers }}"

    - name: Wait for VMs to be ready
      wait_for:
        host: "{{ item.ip }}"
        port: 22
        timeout: 300
      loop: "{{ domain_controllers }}"

    # Phase 2: Dynamic Inventory Creation
    - name: Create dynamic inventory for Windows VMs
      add_host:
        name: "{{ item.name }}"
        groups: "domain_controllers"
        ansible_host: "{{ item.ip }}"
        ansible_user: "Administrator"
        ansible_connection: ssh
        ansible_shell_type: powershell
        is_primary_dc: "{{ item.primary }}"
      loop: "{{ domain_controllers }}"

# Phase 3: Configuration Management
- name: Configure Active Directory
  hosts: domain_controllers
  gather_facts: yes
  roles:
    - windows_base
    - active_directory  
    - dns_server
    - monitoring
```

## Advantages of Pure Ansible

### ✅ **Single Tool Stack**
- **Unified workflow**: One tool for everything
- **Consistent syntax**: All YAML, no HCL
- **Single state management**: Ansible's idempotency everywhere
- **Simpler CI/CD**: Only need Ansible in pipelines

### ✅ **Better Integration** 
- **Native SSH integration**: Seamless transition from provisioning to config
- **Unified error handling**: Same retry/rollback mechanisms
- **Shared variables**: Easy to pass data between provisioning and config
- **Dynamic inventory**: Create inventory on-the-fly during provisioning

### ✅ **Operational Benefits**
- **One skill set**: Team only needs to know Ansible
- **Unified documentation**: Everything in Ansible playbooks
- **Simpler dependencies**: No Terraform state files to manage
- **Better secrets management**: Ansible Vault for everything

## Disadvantages to Consider

### ❌ **Proxmox Module Limitations**
- **Less feature coverage**: Terraform provider is more comprehensive
- **Community support**: Terraform Proxmox provider is more mature
- **Advanced features**: Some Proxmox features only in Terraform provider

### ❌ **Infrastructure Tracking**
- **No state file**: Harder to track infrastructure changes
- **Manual cleanup**: Must manually track VMs for deletion
- **Resource drift**: No automatic drift detection like Terraform

## Implementation Comparison

### Current: Terraform + Ansible
```bash
# Two-step process
terraform apply         # Create infrastructure  
# Terraform calls Ansible automatically
```

### Pure Ansible Alternative
```bash  
# Single-step process
ansible-playbook site.yml   # Create infrastructure + configure
```

## When to Choose Pure Ansible

**Choose Pure Ansible if:**
- ✅ Team is primarily Ansible-focused
- ✅ Infrastructure is relatively simple
- ✅ You want unified tooling
- ✅ Proxmox environment is stable/standardized

**Keep Terraform + Ansible if:**
- ✅ Complex infrastructure requirements
- ✅ Need advanced Proxmox features
- ✅ Infrastructure-as-Code best practices are priority
- ✅ Team has strong Terraform skills

## Migration Path

If you want to try pure Ansible:

1. **Create new playbook** with VM provisioning tasks
2. **Test with single VM** to validate approach  
3. **Migrate configuration roles** (already done!)
4. **Update CI/CD pipelines** to use only Ansible
5. **Remove Terraform files** once validated

## Recommendation

Given your setup, **Pure Ansible could work well** because:
- ✅ Your Ansible roles are already well-structured  
- ✅ Configuration is more complex than infrastructure
- ✅ You have 2 VMs (simple infrastructure)
- ✅ Ansible team skills are already developed

The choice depends on your team's preferences and future infrastructure complexity.
