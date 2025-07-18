---
all:
  children:
    domain_controllers:
      hosts:
%{ for dc in domain_controllers ~}
        ${dc.name}:
          ansible_host: ${dc.ip_address}
          ansible_user: ${admin_user}
          ansible_ssh_private_key_file: ~/.ssh/id_ed25519
          ansible_connection: ssh
          ansible_shell_type: powershell
          vm_id: ${dc.vm_id}
          is_primary_dc: ${dc.is_primary}
%{ endfor ~}
      vars:
        domain_name: ${domain_name}
