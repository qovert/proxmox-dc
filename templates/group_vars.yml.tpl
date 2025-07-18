---
# Domain Configuration
domain_name: "${domain_name}"
netbios_name: "${netbios_name}"
domain_functional_level: "${domain_functional_level}"
forest_functional_level: "${forest_functional_level}"

# Authentication
admin_username: "${admin_username}"
admin_password: "${admin_password}"
dsrm_password: "${dsrm_password}"

# Network Configuration
gateway_ip: "${gateway_ip}"
network_cidr_bits: ${network_cidr_bits}
dns_servers: "${dns_servers}"

# DNS Forwarders
dns_forwarders:
%{ for forwarder in dns_forwarders ~}
  - "${forwarder}"
%{ endfor ~}

# Organizational Units
organizational_units:
%{ for ou in organizational_units ~}
  - "${ou}"
%{ endfor ~}

# Password Policy
password_policy:
  min_length: ${password_policy.min_length}
  complexity_enabled: ${password_policy.complexity_enabled}
  max_password_age_days: ${password_policy.max_password_age_days}
  min_password_age_days: ${password_policy.min_password_age_days}
  password_history_count: ${password_policy.password_history_count}
  lockout_threshold: ${password_policy.lockout_threshold}
  lockout_duration_minutes: ${password_policy.lockout_duration_minutes}
  lockout_reset_minutes: ${password_policy.lockout_reset_minutes}

# Features
enable_recycle_bin: ${enable_recycle_bin}
enable_backup: ${enable_backup}
enable_monitoring: ${enable_monitoring}
