---
layout: default
title: Developer Guide
parent: Explanations
nav_order: 7
---


**ocp4-disconnected-helper** | Developer Onboarding & Workflow Guide

---

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
  - [Hardware Requirements](#hardware-requirements)
  - [Software Requirements](#software-requirements)
- [Environment Setup](#environment-setup)
  - [1. Base System Installation](#1-base-system-installation)
  - [2. Clone Repository](#2-clone-repository)
  - [3. Install Dependencies](#3-install-dependencies)
  - [4. Verify Installation](#4-verify-installation)
- [KVM Development Environment](#kvm-development-environment)
  - [Libvirt Network Configuration](#libvirt-network-configuration)
  - [Storage Pool Setup](#storage-pool-setup)
  - [SSH Key Configuration](#ssh-key-configuration)
- [Development Workflows](#development-workflows)
  - [VM Provisioning Pattern](#vm-provisioning-pattern)
  - [Testing Playbooks Locally](#testing-playbooks-locally)
  - [Working with Inventory](#working-with-inventory)
  - [Using Extra Vars](#using-extra-vars)
- [Common Development Tasks](#common-development-tasks)
  - [Provision Registry VM](#provision-registry-vm)
  - [Setup HAProxy Load Balancer](#setup-haproxy-load-balancer)
  - [Deploy AAP Controller](#deploy-aap-controller)
  - [Mirror OpenShift Images](#mirror-openshift-images)
- [Architecture & Design Patterns](#architecture--design-patterns)
  - [Idempotent VM Provisioning](#idempotent-vm-provisioning)
  - [Cloud-Init Integration](#cloud-init-integration)
  - [Reusable Task Pattern](#reusable-task-pattern)
- [Testing & Validation](#testing--validation)
  - [Syntax Validation](#syntax-validation)
  - [Dry-Run Testing](#dry-run-testing)
  - [Integration Testing](#integration-testing)
- [Troubleshooting](#troubleshooting)
  - [Common Issues](#common-issues)
  - [Debugging Tips](#debugging-tips)
  - [Logs & Diagnostics](#logs--diagnostics)
- [Contributing](#contributing)
  - [Code Standards](#code-standards)
  - [Pull Request Process](#pull-request-process)
  - [Documentation](#documentation)
- [Resources](#resources)

---

## Overview

This guide helps developers set up a KVM-based development environment for **ocp4-disconnected-helper**. You'll learn how to:

- Configure a RHEL/CentOS Stream 9.4+ KVM host
- Provision VMs using pure Ansible (`community.libvirt`)
- Test OpenShift disconnected installation workflows
- Develop and validate Ansible playbooks locally

**Architecture**: This project uses a **standalone, self-contained architecture** with:
- **Tier 1**: Shell + `ansible-playbook` CLI (development & production parity)
- **Tier 2**: Red Hat Ansible Automation Platform (optional orchestration)
- **VM Provisioning**: `community.libvirt` collection (no kcli dependency)
- **Image Mirroring**: `oc-mirror` v2 (Red Hat supported tool)

---

## Prerequisites

### Hardware Requirements

**Minimum** (for basic development):
- **CPU**: 8 cores (Intel VT-x/AMD-V enabled)
- **RAM**: 32GB
- **Disk**: 200GB SSD
- **Network**: 1Gbps NIC

**Recommended** (for full OCP cluster testing):
- **CPU**: 16+ cores
- **RAM**: 128GB
- **Disk**: 500GB NVMe SSD
- **Network**: 10Gbps NIC (optional)

### Software Requirements

**Operating System** (one of):
- Red Hat Enterprise Linux (RHEL) 9.4+
- CentOS Stream 9.4+
- Rocky Linux 9.4+

**Required Subscriptions/Access**:
- Red Hat Subscription (for RHEL) or configured repos (CentOS/Rocky)
- Red Hat pull secret: https://console.redhat.com/openshift/install/pull-secret
- (Optional) Red Hat AAP subscription for Tier 2 orchestration

---

## Environment Setup

### 1. Base System Installation

Install a minimal/server OS with the following configuration:

```bash
# Network configuration (example - adjust for your environment)
# Static IP: 192.168.122.1/24
# Gateway: 192.168.122.1
# DNS: 8.8.8.8, 1.1.1.1

# Register system (RHEL only)
sudo subscription-manager register --username <your-username>
sudo subscription-manager attach --pool=<your-pool-id>

# Enable required repositories (RHEL)
sudo subscription-manager repos --enable=rhel-9-for-x86_64-baseos-rpms
sudo subscription-manager repos --enable=rhel-9-for-x86_64-appstream-rpms

# For CentOS Stream, verify repos are configured
sudo dnf repolist
```

### 2. Clone Repository

```bash
# Create workspace directory
mkdir -p ~/workspace
cd ~/workspace

# Clone the repository
git clone https://github.com/tosin2013/ocp4-disconnected-helper.git
cd ocp4-disconnected-helper

# Checkout the latest stable release (or stay on main for development)
git checkout main  # or git checkout v4.21.0
```

### 3. Install Dependencies

Run the automated dependency installer:

```bash
# Install base packages and configure libvirt
sudo ansible-playbook playbooks/setup-dependencies.yml

# Expected output:
# ✅ Base packages installed (ansible-core, libvirt, qemu-kvm, etc.)
# ✅ Libvirt enabled and started
# ✅ Ansible collections installed (community.libvirt, ansible.posix)
# ✅ Directory structure created
```

**What gets installed:**
- `ansible-core` (2.15+)
- `libvirt`, `libvirt-client`, `qemu-kvm`
- `python3-libvirt`, `python3-pip`
- `virt-install`, `genisoimage`
- `wget`, `curl`, `git`, `jq`
- Ansible collections: `community.libvirt`, `ansible.posix`

### 4. Verify Installation

```bash
# Run environment validation playbook
ansible-playbook playbooks/validate-environment.yml

# Check libvirt status
sudo systemctl status libvirtd

# Verify libvirt connection
virsh list --all

# Check Ansible version
ansible --version
# Expected: ansible-core 2.15.0 or later

# Verify collections
ansible-galaxy collection list | grep -E "(community.libvirt|ansible.posix)"
```

---

## KVM Development Environment

### Libvirt Network Configuration

**Default Network** (`default` - NAT):

```bash
# Check default network
virsh net-list --all

# If not active, start it
virsh net-start default
virsh net-autostart default

# View network details
virsh net-dumpxml default
```

**Custom Network** (optional - for isolated testing):

```bash
# Create custom network definition
cat > /tmp/ocp-network.xml <<EOF
<network>
  <name>ocp4-network</name>
  <forward mode='nat'/>
  <bridge name='virbr1' stp='on' delay='0'/>
  <ip address='192.168.100.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.100.100' end='192.168.100.200'/>
    </dhcp>
  </ip>
</network>
EOF

# Define and start network
virsh net-define /tmp/ocp-network.xml
virsh net-start ocp4-network
virsh net-autostart ocp4-network
```

### Storage Pool Setup

```bash
# Check existing storage pools
virsh pool-list --all

# Create dedicated storage pool for VMs
sudo mkdir -p /var/lib/libvirt/images/ocp4-vms

# Define storage pool
virsh pool-define-as ocp4-pool dir - - - - /var/lib/libvirt/images/ocp4-vms
virsh pool-build ocp4-pool
virsh pool-start ocp4-pool
virsh pool-autostart ocp4-pool

# Verify
virsh pool-info ocp4-pool
```

### SSH Key Configuration

```bash
# Generate SSH key for VM access (if not exists)
if [ ! -f ~/.ssh/id_rsa ]; then
  ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

# Display public key (this will be injected into VMs via cloud-init)
cat ~/.ssh/id_rsa.pub
```

---

## Development Workflows

### VM Provisioning Pattern

This project uses **pure Ansible with `community.libvirt`** for VM provisioning. The pattern is:

```
1. Define VM variables (name, memory, CPUs, disk, network)
2. Generate cloud-init configuration (user-data, meta-data, network-config)
3. Create cloud-init ISO
4. Define VM in libvirt from Jinja2 template
5. Start VM
6. Wait for cloud-init to complete
```

**Example**: Provision a test VM

```bash
# Edit inventory to set your variables
vi inventory/local-dev.yml

---
all:
  hosts:
    localhost:
      ansible_connection: local
  vars:
    vm_name: "test-vm"
    vm_memory: 4096
    vm_cpus: 2
    vm_disk_size: 20
    vm_network: "default"
    vm_user: "cloud-user"
    ssh_public_key: "{{ lookup('file', lookup('env', 'HOME') + '/.ssh/id_rsa.pub') }}"

# Run provisioning playbook
ansible-playbook -i inventory/local-dev.yml playbooks/provision-test-vm.yml
```

### Testing Playbooks Locally

**Syntax Check**:

```bash
# Check playbook syntax
ansible-playbook --syntax-check playbooks/provision-registry-vm.yml

# Check with inventory
ansible-playbook -i inventory/ibm-cloud.yml --syntax-check playbooks/provision-registry-vm.yml
```

**Dry-Run Mode** (for supported playbooks):

```bash
# Test without making changes
ansible-playbook playbooks/setup-dependencies.yml --check

# For custom playbooks with dry-run support
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/mirror-v2-example.yml \
  -e "dry_run=true"
```

**Verbose Output**:

```bash
# Debug mode
ansible-playbook -i inventory/local-dev.yml playbooks/provision-registry-vm.yml -vvv

# Show task details
ansible-playbook -i inventory/local-dev.yml playbooks/provision-registry-vm.yml -v
```

### Working with Inventory

**Inventory Structure**:

```
inventory/
├── local-dev.yml          # Local development environment
├── ibm-cloud.yml          # IBM Cloud production environment
└── group_vars/
    └── all.yml            # Global variables
```

**Example**: Create local development inventory

```bash
cat > inventory/local-dev.yml <<EOF
---
all:
  hosts:
    localhost:
      ansible_connection: local
  
  vars:
    # KVM Host Configuration
    kvm_host_ip: "192.168.122.1"
    libvirt_network: "default"
    storage_pool: "default"
    
    # VM Configuration
    base_image: "/var/lib/libvirt/images/rhel-9.4-x86_64-kvm.qcow2"
    vm_disk_path: "/var/lib/libvirt/images"
    
    # Registry VM
    quay_vm_name: "registry-vm"
    quay_vm_ip: "192.168.122.26"
    quay_vm_port: 8443
    quay_vm_memory: 8192
    quay_vm_cpus: 2
    
    # HAProxy VM
    haproxy_vm_name: "haproxy-vm"
    haproxy_vm_ip: "192.168.122.25"
    haproxy_vm_memory: 4096
    haproxy_vm_cpus: 2
    
    # AAP Controller VM
    aap_vm_name: "aap-controller"
    aap_vm_ip: "192.168.122.30"
    aap_vm_memory: 16384
    aap_vm_cpus: 4
    
    # DNS & Domain
    base_domain: "local.dev"
    cluster_name: "ocp4"
EOF
```

### Using Extra Vars

**Extra Vars Pattern**: Variable precedence (highest to lowest)

```
1. CLI extra vars (-e)
2. Playbook vars
3. Inventory vars
4. Role defaults
```

**Example**: Override variables at runtime

```bash
# Use extra_vars file
ansible-playbook playbooks/provision-registry-vm.yml \
  -e @extra_vars/registry-config.yml

# Override specific variables
ansible-playbook playbooks/provision-registry-vm.yml \
  -e "quay_vm_memory=16384" \
  -e "quay_vm_cpus=4"

# Combine both
ansible-playbook playbooks/provision-registry-vm.yml \
  -e @extra_vars/registry-config.yml \
  -e "quay_vm_ip=192.168.122.100"
```

---

## Common Development Tasks

### Provision Registry VM

```bash
# Using inventory variables
ansible-playbook -i inventory/local-dev.yml \
  playbooks/provision-registry-vm.yml

# Expected output:
# - VM created with specified resources
# - Cloud-init configures OS, network, packages
# - SSH access available
# - Firewall rules applied

# Verify VM
virsh list --all | grep registry-vm
ssh cloud-user@192.168.122.26
```

### Setup HAProxy Load Balancer

```bash
# Provision HAProxy VM
ansible-playbook -i inventory/local-dev.yml \
  playbooks/provision-haproxy-vm.yml

# Configure HAProxy with Let's Encrypt SSL
ansible-playbook -i inventory/local-dev.yml \
  playbooks/setup-haproxy.yml \
  -e "letsencrypt_email=your-email@example.com"

# Verify HAProxy
curl -k https://registry.ocp4.local.dev:8443/health/instance
```

### Deploy AAP Controller

```bash
# Provision AAP VM (16GB RAM, 4 vCPU, 60GB disk)
ansible-playbook -i inventory/local-dev.yml \
  playbooks/provision-aap-vm.yml

# Install AAP 2.5 Containerized
ansible-playbook -i inventory/local-dev.yml \
  playbooks/setup-aap-containerized.yml \
  -e "aap_admin_password=<your-password>"

# Access AAP UI
# https://192.168.122.30
# Username: admin
# Password: <your-password>
```

### Mirror OpenShift Images

**Phase 1: Download to Disk**

```bash
# Create extra_vars file
cat > extra_vars/mirror-local-dev.yml <<EOF
---
target_mirror_path: "/data/ocp-mirror"
openshift_releases:
  - name: stable-4.21
    minVersion: 4.21.0
    maxVersion: 4.21.0
architectures:
  - amd64
EOF

# Download images
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/mirror-local-dev.yml

# Expected: 194 images (~22GB) downloaded to cache
```

**Phase 2: Push to Registry**

```bash
# Setup registry authentication
ansible-playbook -i inventory/local-dev.yml \
  playbooks/setup-registry-authentication.yml

# Push to mirror registry
ansible-playbook -i inventory/local-dev.yml \
  playbooks/push-to-registry-v2.yml \
  -e "workspace_path=/data/ocp-mirror/oc-mirror-workspace"

# Verify images in registry
curl -k -u <user>:<password> \
  https://registry.ocp4.local.dev:8443/v2/_catalog | jq .
```

---

## Architecture & Design Patterns

### Idempotent VM Provisioning

**Problem**: Running the same playbook twice should not create duplicate VMs.

**Solution**: Check if VM exists before provisioning

```yaml
- name: Check if VM already exists
  community.libvirt.virt:
    command: list_vms
  register: existing_vms

- name: Set VM exists fact
  ansible.builtin.set_fact:
    vm_exists: "{{ vm_name in existing_vms.list_vms }}"

- name: Skip if VM exists
  ansible.builtin.meta: end_play
  when: vm_exists

# VM provisioning tasks only run if VM does not exist
```

### Cloud-Init Integration

**Pattern**: Use cloud-init for VM initialization instead of post-boot Ansible runs

**Benefits**:
- Faster VM ready time
- No SSH wait loops
- Atomic configuration on first boot

**Example**: `templates/cloud-init/registry-user-data.yml.j2`

```yaml
#cloud-config
hostname: {{ vm_hostname }}
fqdn: {{ vm_fqdn }}

users:
  - name: {{ vm_user }}
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - {{ ssh_public_key }}

packages:
  - podman
  - firewalld
  - python3

runcmd:
  - systemctl enable --now firewalld
  - firewall-cmd --permanent --add-port=8443/tcp
  - firewall-cmd --reload
```

### Reusable Task Pattern

**Pattern**: Extract common VM provisioning logic into reusable task file

**File**: `tasks/provision-vm-libvirt.yml`

**Usage**:

```yaml
- name: Provision Registry VM
  hosts: localhost
  vars:
    vm_name: "registry-vm"
    vm_memory: 8192
    vm_cpus: 2
    vm_template: "templates/libvirt/registry-vm.xml.j2"
    cloud_init_user_data_template: "templates/cloud-init/registry-user-data.yml.j2"
  
  tasks:
    - name: Include reusable provisioning task
      ansible.builtin.include_tasks: tasks/provision-vm-libvirt.yml
```

**Benefits**:
- DRY (Don't Repeat Yourself)
- Consistent VM provisioning across all playbooks
- Easier maintenance and testing

---

## Testing & Validation

### Syntax Validation

```bash
# Validate all playbooks
find playbooks -name "*.yml" -exec ansible-playbook --syntax-check {} \;

# Validate specific playbook
ansible-playbook --syntax-check playbooks/provision-registry-vm.yml

# Validate with inventory
ansible-playbook -i inventory/local-dev.yml \
  --syntax-check playbooks/setup-mirror-registry.yml
```

### Dry-Run Testing

```bash
# Ansible check mode
ansible-playbook -i inventory/local-dev.yml \
  playbooks/setup-dependencies.yml --check

# Custom dry-run (for supported playbooks)
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/mirror-v2-example.yml \
  -e "dry_run=true"

# Diff mode (show what would change)
ansible-playbook -i inventory/local-dev.yml \
  playbooks/setup-haproxy.yml --check --diff
```

### Integration Testing

```bash
# Full workflow test
./scripts/test-full-workflow.sh

# Test VM provisioning idempotency
ansible-playbook -i inventory/local-dev.yml \
  playbooks/provision-registry-vm.yml

# Run again - should skip VM creation
ansible-playbook -i inventory/local-dev.yml \
  playbooks/provision-registry-vm.yml

# Cleanup test VMs
virsh destroy test-vm; virsh undefine test-vm --remove-all-storage
```

---

## Troubleshooting

### Common Issues

**Issue 1: Libvirt connection failed**

```bash
# Symptoms
# ERROR: failed to connect to the hypervisor

# Resolution
sudo systemctl status libvirtd
sudo systemctl start libvirtd

# Check user permissions
sudo usermod -a -G libvirt $(whoami)
# Log out and back in for group changes
```

**Issue 2: VM fails to start**

```bash
# Check VM status
virsh domstate <vm-name>

# View VM logs
sudo journalctl -u libvirtd -f

# Check VM XML definition
virsh dumpxml <vm-name>

# Force destroy and restart
virsh destroy <vm-name>
virsh start <vm-name>
```

**Issue 3: Cloud-init not running**

```bash
# SSH to VM and check cloud-init status
ssh cloud-user@<vm-ip>
sudo cloud-init status

# View cloud-init logs
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log

# Manually trigger cloud-init
sudo cloud-init clean
sudo cloud-init init
```

**Issue 4: Network connectivity issues**

```bash
# Check libvirt network
virsh net-list --all
virsh net-start default

# Check VM network interface
virsh domiflist <vm-name>

# Test connectivity
ping -c 4 192.168.122.26

# Check firewall rules
sudo firewall-cmd --list-all
```

**Issue 5: Ansible playbook hangs**

```bash
# Common causes:
# 1. SSH host key verification
# 2. Wrong inventory IP
# 3. Firewall blocking SSH

# Solutions:
# Disable strict host key checking (development only)
export ANSIBLE_HOST_KEY_CHECKING=False

# Verify SSH access
ssh -vvv cloud-user@<vm-ip>

# Check Ansible connectivity
ansible -i inventory/local-dev.yml all -m ping
```

### Debugging Tips

**Enable Ansible Debug Output**:

```bash
# Verbose mode (-v to -vvvv)
ansible-playbook -i inventory/local-dev.yml playbooks/provision-registry-vm.yml -vvv

# Debug specific task
ansible-playbook -i inventory/local-dev.yml playbooks/provision-registry-vm.yml \
  --start-at-task="Define VM in libvirt" -vvv
```

**Check Variable Values**:

```yaml
# Add debug task to playbook
- name: Debug variables
  ansible.builtin.debug:
    msg:
      - "VM Name: {{ vm_name }}"
      - "VM Memory: {{ vm_memory }}"
      - "VM IP: {{ vm_ip }}"
```

**Test Individual Commands**:

```bash
# Test virsh commands
virsh list --all
virsh net-list --all
virsh pool-list --all

# Test cloud-init ISO creation
genisoimage -output /tmp/test-cidata.iso \
  -volid cidata -joliet -rock \
  /tmp/user-data /tmp/meta-data

# Test libvirt XML validation
virt-xml-validate /tmp/vm-definition.xml domain
```

### Logs & Diagnostics

**Key Log Locations**:

```bash
# Libvirt logs
sudo journalctl -u libvirtd -f

# VM console logs
sudo virsh console <vm-name>

# Cloud-init logs (on VM)
ssh cloud-user@<vm-ip>
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log

# Ansible logs (if configured)
export ANSIBLE_LOG_PATH=~/ansible.log
```

**Collect Diagnostics**:

```bash
# Generate diagnostic bundle
./scripts/collect-diagnostics.sh

# Manual collection
mkdir -p /tmp/diagnostics
virsh list --all > /tmp/diagnostics/vms.txt
virsh net-list --all > /tmp/diagnostics/networks.txt
virsh pool-list --all > /tmp/diagnostics/pools.txt
sudo journalctl -u libvirtd > /tmp/diagnostics/libvirtd.log
tar czf diagnostics.tar.gz /tmp/diagnostics/
```

---

## Contributing

### Code Standards

**Ansible Best Practices**:

1. **Idempotency**: All playbooks must be idempotent
   ```yaml
   # Bad - always creates
   - command: create-something
   
   # Good - checks first
   - stat:
       path: /path/to/something
     register: something_stat
   
   - command: create-something
     when: not something_stat.stat.exists
   ```

2. **Variable Naming**: Use descriptive, prefixed names
   ```yaml
   # Bad
   - name: myvar
   - ip: 192.168.1.1
   
   # Good
   - quay_vm_name: "registry-vm"
   - quay_vm_ip: "192.168.122.26"
   ```

3. **Task Naming**: Clear, descriptive task names
   ```yaml
   # Bad
   - name: Run command
   
   # Good
   - name: Provision Registry VM using community.libvirt
   ```

4. **Error Handling**: Use `block/rescue` for error recovery
   ```yaml
   - name: Deploy mirror-registry
     block:
       - name: Download installer
         get_url: ...
       - name: Run installer
         command: ...
     rescue:
       - name: Cleanup on failure
         file:
           path: /opt/mirror-registry
           state: absent
   ```

**Code Review Checklist**:

- [ ] Playbook runs without errors
- [ ] Idempotency verified (run twice, second run no changes)
- [ ] Variables properly scoped (inventory vs. playbook vs. role)
- [ ] Error handling implemented
- [ ] Documentation updated (README, ADRs, comments)
- [ ] No hardcoded credentials (use vault or external auth)
- [ ] Syntax validation passes
- [ ] Dry-run mode works (if applicable)

### Pull Request Process

1. **Fork and Clone**:
   ```bash
   # Fork on GitHub, then:
   git clone https://github.com/<your-username>/ocp4-disconnected-helper.git
   cd ocp4-disconnected-helper
   git remote add upstream https://github.com/tosin2013/ocp4-disconnected-helper.git
   ```

2. **Create Feature Branch**:
   ```bash
   git checkout -b feature/add-vm-provisioning-pattern
   ```

3. **Make Changes**:
   ```bash
   # Edit files
   vi playbooks/provision-new-vm.yml
   
   # Test locally
   ansible-playbook --syntax-check playbooks/provision-new-vm.yml
   ansible-playbook -i inventory/local-dev.yml playbooks/provision-new-vm.yml
   ```

4. **Commit with Meaningful Messages**:
   ```bash
   git add playbooks/provision-new-vm.yml
   git commit -m "feat: Add VM provisioning pattern for new service
   
   - Implements reusable provision-vm-libvirt.yml task
   - Adds cloud-init templates for automated setup
   - Includes idempotency checks
   - Tested on RHEL 9.4 KVM host
   
   Closes #123"
   ```

5. **Push and Create PR**:
   ```bash
   git push origin feature/add-vm-provisioning-pattern
   # Create PR on GitHub
   ```

6. **PR Template**:
   ```markdown
   ## Description
   Brief description of changes
   
   ## Type of Change
   - [ ] Bug fix
   - [x] New feature
   - [ ] Documentation update
   - [ ] Refactoring
   
   ## Testing
   - [x] Syntax validation passed
   - [x] Dry-run tested
   - [x] Integration tested on KVM host
   - [x] Idempotency verified
   
   ## Checklist
   - [x] Code follows project style guidelines
   - [x] Documentation updated
   - [x] ADR created (if architectural change)
   - [x] CHANGELOG.md updated
   ```

### Documentation

**Required Documentation**:

1. **Playbook Comments**: Explain complex logic
   ```yaml
   # Provision VM using community.libvirt instead of kcli (ADR 0023)
   # This pattern ensures idempotency and follows cloud-init best practices
   - name: Provision Registry VM
   ```

2. **README Updates**: For new features
   ```markdown
   ## New VM Provisioning Pattern
   
   As of v4.21.0, we use `community.libvirt` for VM provisioning.
   See [Developer Guide](docs/developer-guide.md#vm-provisioning-pattern)
   ```

3. **ADRs**: For architectural decisions
   ```bash
   # Create ADR for significant changes
   docs/adrs/0024-new-architectural-decision.md
   ```

4. **CHANGELOG**: For user-facing changes
   ```markdown
   ### Added
   - New VM provisioning pattern using community.libvirt
   ```

---

## Resources

### Official Documentation

- **Red Hat OpenShift**: https://docs.openshift.com
- **Ansible Documentation**: https://docs.ansible.com
- **Libvirt Documentation**: https://libvirt.org/docs.html
- **Cloud-Init Documentation**: https://cloudinit.readthedocs.io
- **oc-mirror Guide**: https://docs.openshift.com/container-platform/4.21/installing/disconnected_install/installing-mirroring-disconnected.html

### Project Documentation

- [README](../README.md) - Project overview and quick start
- [PREREQUISITES](PREREQUISITES.md) - OS installation and setup
- [ADRs](adrs/) - Architectural Decision Records
- [CHANGELOG](../CHANGELOG.md) - Version history and changes
- [RELEASE_PLAN](../RELEASE_PLAN.md) - v4.21.0 migration roadmap
- [Migration Guides](.) - Airflow→AAP, Qubinode→Standalone

### Community Resources

- **GitHub Issues**: https://github.com/tosin2013/ocp4-disconnected-helper/issues
- **Discussions**: https://github.com/tosin2013/ocp4-disconnected-helper/discussions
- **Red Hat Communities**: https://www.redhat.com/en/explore/communities

### Learning Resources

- **Ansible for DevOps**: https://www.ansiblefordevops.com
- **KVM Virtualization**: https://www.linux-kvm.org/page/Documents
- **OpenShift Virtualization**: https://docs.openshift.com/container-platform/4.21/virt/about_virt/about-virt.html
- **Libvirt Ansible Collection**: https://galaxy.ansible.com/community/libvirt

---

## Quick Reference

### Essential Commands

```bash
# List VMs
virsh list --all

# Start/Stop VM
virsh start <vm-name>
virsh shutdown <vm-name>
virsh destroy <vm-name>  # Force stop

# Delete VM
virsh undefine <vm-name> --remove-all-storage

# Console access
virsh console <vm-name>  # Ctrl+] to exit

# Network info
virsh net-list --all
virsh net-dhcp-leases default

# Ansible ad-hoc
ansible -i inventory/local-dev.yml all -m ping
ansible -i inventory/local-dev.yml all -a "uptime"

# Test playbook syntax
ansible-playbook --syntax-check playbooks/<playbook>.yml

# Run playbook
ansible-playbook -i inventory/local-dev.yml playbooks/<playbook>.yml
```

### Directory Structure

```
ocp4-disconnected-helper/
├── docs/                      # Documentation
│   ├── adrs/                  # Architecture Decision Records
│   ├── developer-guide.md     # This file
│   ├── PREREQUISITES.md       # Setup requirements
│   └── *.md                   # Other guides
├── playbooks/                 # Ansible playbooks
│   ├── provision-*.yml        # VM provisioning
│   ├── setup-*.yml            # Service configuration
│   └── download-*.yml         # Image mirroring
├── inventory/                 # Ansible inventories
│   ├── local-dev.yml          # Development environment
│   └── ibm-cloud.yml          # Production environment
├── extra_vars/                # Variable files
├── templates/                 # Jinja2 templates
│   ├── libvirt/               # VM domain definitions
│   ├── cloud-init/            # Cloud-init configs
│   └── haproxy/               # HAProxy configs
├── tasks/                     # Reusable Ansible tasks
└── scripts/                   # Helper scripts
```

---

**Last Updated**: 2026-06-03  
**Version**: v4.21.0  
**Maintainer**: Platform Team

For questions or issues, open a GitHub issue or discussion.
