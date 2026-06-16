---
layout: default
title: Ansible Roles Structure
parent: Reference
nav_order: 4
---


**ADR:** [0024](adrs/0024-ansible-roles-collections-architecture.md)  
**Status:** In Progress  
**Date:** 2026-06-03

## Overview

This project uses Ansible roles to provide atomic, reusable infrastructure components. Each role manages the complete lifecycle of a component (provision → configure → install → verify → cleanup).

## Quick Start

### Deploy Registry (replaces 4 separate playbooks)

```bash
# Deploy
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-registry.yml

# Delete
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-registry.yml -e vm_state=absent
```

### Before vs After

**❌ Old Way (4 separate playbooks):**
```bash
ansible-playbook playbooks/provision-registry-vm.yml
ansible-playbook playbooks/configure-vm-static-ip.yml -e ansible_host=<dhcp-ip>
ansible-playbook playbooks/setup-mirror-registry.yml
ansible-playbook playbooks/setup-registry-authentication.yml
```

**✅ New Way (1 atomic playbook):**
```bash
ansible-playbook playbooks/deploy-registry.yml
```

## Available Roles

### `common_vm`
Reusable VM provisioning base for all infrastructure VMs.

**Features:**
- VM provisioning with `community.libvirt`
- Cloud-init configuration (user-data, meta-data, network-config)
- Post-boot static IP configuration (fixes CentOS Stream 9 cloud-init issue)
- Cleanup on failure
- Idempotent operations

**Variables:**
```yaml
vm_name: "my-vm"
vm_memory: 8192        # MB
vm_cpus: 4
vm_disk_size: 100      # GB
vm_use_static_ip: true
vm_static_ip: "192.168.122.24"
vm_user: "admin"
```

**Usage:**
```yaml
- hosts: myhost
  roles:
    - role: common_vm
      vars:
        vm_state: present
        vm_static_ip: "192.168.122.50"
```

### `registry_vm`
Complete registry VM lifecycle management.

**Features:**
- Inherits `common_vm` for VM provisioning
- Installs Red Hat mirror-registry (Quay)
- Configures authentication
- Health verification
- Rollback on failure

**Variables:**
```yaml
registry_hostname: "registry.example.com"
registry_port: 8443
registry_admin_password: "auto-generated"
registry_type: "mirror-registry"  # or harbor, quay, jfrog
```

**Usage:**
```yaml
- hosts: registry
  roles:
    - role: registry_vm
      vars:
        vm_state: present
        vm_static_ip: "{{ quay_vm_ip }}"
```

## Role Structure

```
roles/
  common_vm/
    tasks/
      main.yml                    # Orchestrator
      provision.yml               # VM creation
      configure_static_ip.yml     # Network configuration
      delete.yml                  # Cleanup
    templates/
      cloud-init/
        user-data.yml.j2
        meta-data.yml.j2
        network-config.yml.j2
      libvirt/
        domain.xml.j2
    defaults/main.yml             # Default variables
    handlers/main.yml             # Cleanup handlers
    meta/main.yml                 # Role metadata
  
  registry_vm/
    tasks/
      main.yml                    # Orchestrator
      install_mirror_registry.yml # Quay installation
      setup_auth.yml              # Authentication
      verify.yml                  # Health checks
    defaults/main.yml
    meta/main.yml                 # Depends on: common_vm
```

## Benefits

### Atomic Operations
- Deploy or destroy entire stack with one command
- All steps succeed or automatic rollback
- No manual intervention for failures

### Reusability
- `common_vm` used by all VM roles
- Consistent interface across infrastructure
- Easy to extend with new roles

### Testability
- Each role testable with Molecule
- Idempotency guaranteed
- Dry-run support with `--check`

### Maintainability
- Clear separation of concerns
- Self-documenting through role structure
- Easy onboarding for new team members

## Troubleshooting

### Role Not Found
```
ERROR! the role 'registry_vm' was not found
```

**Solution:** Ensure `ansible.cfg` has roles path:
```ini
[defaults]
roles_path = ./roles
```

### Variable Undefined
```
'vm_static_ip' is undefined
```

**Solution:** Pass required variables:
```bash
ansible-playbook playbooks/deploy-registry.yml -e vm_static_ip=192.168.122.24
```

### VM Already Exists
**Solution:** Force recreate:
```bash
ansible-playbook playbooks/deploy-registry.yml -e vm_force_recreate=true
```

## Roadmap

### Phase 1 (Complete)
- ✅ `common_vm` role
- ✅ `registry_vm` role
- ✅ `deploy-registry.yml` playbook

### Phase 2 (Next)
- 🔜 `aap_vm` role for Ansible Automation Platform
- 🔜 `harbor_vm` role for Harbor registry
- 🔜 `jfrog_vm` role for JFrog Artifactory

### Phase 3 (Future)
- 🔜 Collection packaging: `ocp4_disconnected.infrastructure`
- 🔜 Ansible Galaxy publication
- 🔜 Molecule test scenarios for all roles
- 🔜 CI/CD integration

## Contributing

When adding new roles:

1. **Use `common_vm` as base** for any VM-based component
2. **Follow role structure** (tasks/, defaults/, handlers/, meta/)
3. **Add verification** (verify.yml task file)
4. **Document variables** in defaults/main.yml
5. **Test idempotency** (run twice, no changes on second run)
6. **Add to playbooks/** with simple orchestrator playbook

## References

- [ADR 0024: Ansible Roles and Collections Architecture](adrs/0024-ansible-roles-collections-architecture.md)
- [Ansible Roles Documentation](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_reuse_roles.html)
- [Ansible Collections](https://docs.ansible.com/ansible/latest/collections_guide/index.html)
- [Molecule Testing Framework](https://molecule.readthedocs.io/)
