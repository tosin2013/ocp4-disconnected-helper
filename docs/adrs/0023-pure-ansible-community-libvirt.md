# ADR 0023: Pure Ansible with community.libvirt Migration

**Status:** Accepted  
**Date:** 2026-06-02  
**Deciders:** Platform Team, Product Owner (Tosin)  
**Supersedes:** ADR 0018 (Registry Deployment on Dedicated VM via kcli)  
**PRD Reference:** PRD v4.21.0 Section 2 - "Migrate to Pure Ansible (Deprecate kcli and Qubinode)"

## Context

The ocp4-disconnected-helper project currently uses **kcli** (KVM Command Line Interface) for provisioning virtual machines in development environments. This is documented in ADR 0018 (Registry Deployment on Dedicated VM via kcli).

### Current Implementation (kcli-based)

**playbooks/provision-registry-vm.yml** (current):
```yaml
- name: Provision Registry VM via kcli
  hosts: localhost
  tasks:
    - name: Create VM with kcli
      ansible.builtin.shell: |
        kcli create vm {{ registry_vm_name }} \
          --memory {{ registry_vm_memory }} \
          --cpus {{ registry_vm_cpus }} \
          --disk {{ registry_vm_disk_size }} \
          --image rhel9
```

**Problems with kcli:**

1. **External dependency**: kcli is not part of Ansible core or standard collections
2. **Installation complexity**: Requires `pip install kcli` + configuration
3. **Non-idempotent**: Shell commands are harder to make idempotent
4. **Limited Ansible integration**: kcli is a standalone CLI tool, not Ansible-native
5. **Deviation from "pure Ansible" goal**: PRD Section 2 explicitly requires deprecation of kcli
6. **Development → Production mismatch**: Uses kcli in dev, but bare metal in prod (different tooling)

### PRD Requirements (Section 2)

> "Migrate to Pure Ansible (Deprecate kcli and Qubinode): Convert all existing VM provisioning scripts and playbooks to use native Ansible `community.libvirt` modules."

**All-VMs-on-KVM Rule:**
> "Every component must run as a Virtual Machine on KVM. This includes the OpenShift cluster nodes, the Image Registry, and the Ansible Automation Platform (AAP) orchestrator."

**Pure Ansible Requirement:**
> "The project will deprecate all legacy dependencies on Qubinode, kcli, and Airflow, migrating entirely to pure Ansible using the `community.libvirt` collection."

## Decision

**Deprecate kcli** and **migrate all VM provisioning to pure Ansible** using the `community.libvirt` collection.

### Key Changes

1. **Replace kcli commands** with `community.libvirt.virt` module calls
2. **Use Ansible templates** for libvirt XML domain definitions
3. **Implement cloud-init** for VM initialization (user accounts, SSH keys, network config)
4. **Idempotent design**: All playbooks can be safely re-run
5. **Consistent tooling**: Ansible for both development (KVM VMs) and production (bare metal)

### Scope of Migration

All VM provisioning playbooks must migrate to `community.libvirt`:

| Playbook | Current (kcli) | New (community.libvirt) |
|----------|----------------|-------------------------|
| `provision-registry-vm.yml` | ✅ Uses kcli | ⏩ Migrate to libvirt |
| `provision-aap-vm.yml` | 🆕 New (uses kcli in initial draft) | ⏩ Use libvirt from start |
| `provision-haproxy-vm.yml` | 🆕 New (for openshift-forwarder) | ⏩ Use libvirt from start |
| `provision-ocp-nodes-vms.yml` | 🆕 New (for agent-install testing) | ⏩ Use libvirt from start |

## Rationale

### Why community.libvirt?

| Aspect | kcli | community.libvirt |
|--------|------|-------------------|
| **Ansible Integration** | External CLI tool | Native Ansible module |
| **Installation** | `pip install kcli` | `ansible-galaxy collection install community.libvirt` |
| **Idempotency** | Manual implementation | Built into module |
| **State Management** | Manual tracking | Ansible facts |
| **Dependencies** | Python package + config | Ansible collection (standard) |
| **Documentation** | kcli docs | Ansible docs + examples |
| **Cloud-init support** | Via CLI flags | Via Ansible templates |
| **Debugging** | Shell command logs | Ansible verbose mode |

### Development → Production Parity

**Before (kcli in dev, bare metal in prod):**
```
Development (KVM):
  - kcli create vm registry ...              ← kcli command
  - ansible-playbook setup-registry.yml      ← Ansible playbook

Production (Bare Metal):
  - (no VM provisioning, hardware exists)
  - ansible-playbook setup-registry.yml      ← Same playbook
  
⚠️ MISMATCH: Different tools for VM provisioning vs bare metal setup
```

**After (Ansible everywhere):**
```
Development (KVM):
  - ansible-playbook provision-registry-vm.yml   ← Ansible + libvirt
  - ansible-playbook setup-registry.yml          ← Ansible playbook

Production (Bare Metal):
  - ansible-playbook provision-registry-vm.yml   ← Skipped (when: kvm_mode)
  - ansible-playbook setup-registry.yml          ← Same playbook
  
✅ PARITY: Pure Ansible, conditional logic for KVM vs bare metal
```

## Implementation

### Phase 1: Install community.libvirt Collection

**In `playbooks/setup-dependencies.yml`:**
```yaml
- name: Install community.libvirt collection
  ansible.builtin.command:
    cmd: ansible-galaxy collection install community.libvirt
  become: no
```

### Phase 2: Create Libvirt XML Templates

**templates/libvirt/registry-vm.xml.j2:**
```xml
<domain type='kvm'>
  <name>{{ vm_name }}</name>
  <memory unit='MiB'>{{ vm_memory }}</memory>
  <vcpu>{{ vm_cpus }}</vcpu>
  <os>
    <type arch='x86_64' machine='pc'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
  </features>
  <cpu mode='host-passthrough'/>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/libexec/qemu-kvm</emulator>
    
    <!-- Disk -->
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='{{ libvirt_images_path }}/{{ vm_name }}.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    
    <!-- Cloud-init CDROM -->
    <disk type='file' device='cdrom'>
      <driver name='qemu' type='raw'/>
      <source file='{{ libvirt_images_path }}/{{ vm_name }}-cloud-init.iso'/>
      <target dev='hdb' bus='ide'/>
      <readonly/>
    </disk>
    
    <!-- Network -->
    <interface type='network'>
      <source network='{{ vm_network }}'/>
      <mac address='{{ vm_mac_address }}'/>
      <model type='virtio'/>
    </interface>
    
    <!-- Console -->
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    
    <!-- Graphics (for virt-manager access) -->
    <graphics type='spice' autoport='yes'>
      <listen type='address' address='127.0.0.1'/>
    </graphics>
  </devices>
</domain>
```

### Phase 3: Create Cloud-Init Configuration Templates

**templates/cloud-init/registry-user-data.yml.j2:**
```yaml
#cloud-config
hostname: {{ vm_hostname }}
fqdn: {{ vm_hostname }}.{{ vm_domain }}
manage_etc_hosts: true

users:
  - name: {{ ansible_user }}
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - {{ lookup('file', ssh_public_key_path) }}

# Set timezone
timezone: {{ timezone | default('UTC') }}

# Install base packages
packages:
  - vim
  - wget
  - curl
  - git
  - python3
  - python3-pip

# Run commands on first boot
runcmd:
  - systemctl enable --now sshd
  - echo "{{ vm_hostname }}" > /etc/hostname
  - hostnamectl set-hostname {{ vm_hostname }}

# Configure network (static IP)
write_files:
  - path: /etc/sysconfig/network-scripts/ifcfg-eth0
    content: |
      DEVICE=eth0
      BOOTPROTO=static
      ONBOOT=yes
      IPADDR={{ vm_ip_address }}
      NETMASK={{ vm_netmask }}
      GATEWAY={{ vm_gateway }}
      DNS1={{ vm_dns_1 }}
      DNS2={{ vm_dns_2 }}

power_state:
  mode: reboot
  timeout: 30
  condition: True
```

**templates/cloud-init/registry-meta-data.yml.j2:**
```yaml
instance-id: {{ vm_name }}
local-hostname: {{ vm_hostname }}
```

**templates/cloud-init/registry-network-config.yml.j2:**
```yaml
version: 2
ethernets:
  eth0:
    addresses:
      - {{ vm_ip_address }}/{{ vm_netmask_prefix }}
    gateway4: {{ vm_gateway }}
    nameservers:
      addresses:
        - {{ vm_dns_1 }}
        - {{ vm_dns_2 }}
```

### Phase 4: Rewrite provision-registry-vm.yml (Pure Ansible)

**playbooks/provision-registry-vm.yml (REWRITTEN):**
```yaml
---
- name: Provision Registry VM using community.libvirt (Pure Ansible)
  hosts: localhost
  gather_facts: yes
  become: yes
  vars:
    # VM Configuration
    vm_name: "registry"
    vm_hostname: "registry"
    vm_domain: "ocp.local"
    vm_memory: 16384  # 16GB RAM
    vm_cpus: 4
    vm_disk_size: 500  # 500GB
    
    # Network Configuration
    vm_network: "default"
    vm_ip_address: "192.168.122.100"
    vm_netmask: "255.255.255.0"
    vm_netmask_prefix: 24
    vm_gateway: "192.168.122.1"
    vm_dns_1: "192.168.122.1"
    vm_dns_2: "8.8.8.8"
    vm_mac_address: "52:54:00:6c:3c:01"  # Generate with: pwgen -A 6 | sed 's/../&:/g;s/:$//'
    
    # Base Image
    base_image_url: "https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
    base_image_name: "CentOS-Stream-9-base.qcow2"
    
    # Paths
    libvirt_images_path: "/var/lib/libvirt/images"
    libvirt_pool: "default"
    
    # SSH
    ansible_user: "cloud-user"
    ssh_public_key_path: "~/.ssh/id_rsa.pub"
    
    # Timezone
    timezone: "America/New_York"
  
  tasks:
    # ========================================================================
    # Pre-flight Checks
    # ========================================================================
    - name: Check if libvirtd is running
      ansible.builtin.systemd:
        name: libvirtd
        state: started
        enabled: yes
    
    - name: Ensure libvirt images directory exists
      ansible.builtin.file:
        path: "{{ libvirt_images_path }}"
        state: directory
        mode: '0755'
    
    - name: Check if VM already exists
      community.libvirt.virt:
        command: list_vms
      register: existing_vms
    
    - name: Set VM exists fact
      ansible.builtin.set_fact:
        vm_exists: "{{ vm_name in existing_vms.list_vms }}"
    
    - name: Skip if VM already exists
      ansible.builtin.debug:
        msg: "VM {{ vm_name }} already exists. Skipping provisioning."
      when: vm_exists
    
    - name: End play if VM exists (idempotent)
      ansible.builtin.meta: end_play
      when: vm_exists
    
    # ========================================================================
    # Base Image Download
    # ========================================================================
    - name: Download base cloud image
      ansible.builtin.get_url:
        url: "{{ base_image_url }}"
        dest: "{{ libvirt_images_path }}/{{ base_image_name }}"
        mode: '0644'
      when: not vm_exists
    
    # ========================================================================
    # Create VM Disk (Copy-on-Write from base image)
    # ========================================================================
    - name: Create VM disk from base image
      ansible.builtin.command:
        cmd: >
          qemu-img create -f qcow2
          -F qcow2
          -b {{ libvirt_images_path }}/{{ base_image_name }}
          {{ libvirt_images_path }}/{{ vm_name }}.qcow2
          {{ vm_disk_size }}G
        creates: "{{ libvirt_images_path }}/{{ vm_name }}.qcow2"
      when: not vm_exists
    
    # ========================================================================
    # Cloud-Init Configuration
    # ========================================================================
    - name: Create cloud-init config directory
      ansible.builtin.file:
        path: "/tmp/cloud-init-{{ vm_name }}"
        state: directory
        mode: '0755'
      when: not vm_exists
    
    - name: Generate cloud-init user-data
      ansible.builtin.template:
        src: templates/cloud-init/registry-user-data.yml.j2
        dest: "/tmp/cloud-init-{{ vm_name }}/user-data"
        mode: '0644'
      when: not vm_exists
    
    - name: Generate cloud-init meta-data
      ansible.builtin.template:
        src: templates/cloud-init/registry-meta-data.yml.j2
        dest: "/tmp/cloud-init-{{ vm_name }}/meta-data"
        mode: '0644'
      when: not vm_exists
    
    - name: Generate cloud-init network-config
      ansible.builtin.template:
        src: templates/cloud-init/registry-network-config.yml.j2
        dest: "/tmp/cloud-init-{{ vm_name }}/network-config"
        mode: '0644'
      when: not vm_exists
    
    - name: Create cloud-init ISO
      ansible.builtin.command:
        cmd: >
          genisoimage -output {{ libvirt_images_path }}/{{ vm_name }}-cloud-init.iso
          -volid cidata -joliet -rock
          /tmp/cloud-init-{{ vm_name }}/user-data
          /tmp/cloud-init-{{ vm_name }}/meta-data
          /tmp/cloud-init-{{ vm_name }}/network-config
        creates: "{{ libvirt_images_path }}/{{ vm_name }}-cloud-init.iso"
      when: not vm_exists
    
    # ========================================================================
    # Define and Start VM
    # ========================================================================
    - name: Generate libvirt XML definition
      ansible.builtin.template:
        src: templates/libvirt/registry-vm.xml.j2
        dest: "/tmp/{{ vm_name }}-domain.xml"
        mode: '0644'
      when: not vm_exists
    
    - name: Define VM in libvirt
      community.libvirt.virt:
        command: define
        xml: "{{ lookup('file', '/tmp/' + vm_name + '-domain.xml') }}"
      when: not vm_exists
    
    - name: Start VM
      community.libvirt.virt:
        name: "{{ vm_name }}"
        state: running
      when: not vm_exists
    
    - name: Set VM to autostart
      community.libvirt.virt:
        name: "{{ vm_name }}"
        autostart: yes
      when: not vm_exists
    
    # ========================================================================
    # Wait for VM to Boot and SSH to Be Available
    # ========================================================================
    - name: Wait for VM to get IP address
      ansible.builtin.pause:
        seconds: 30
      when: not vm_exists
    
    - name: Get VM IP address from libvirt
      ansible.builtin.shell:
        cmd: |
          virsh domifaddr {{ vm_name }} | grep -oP '(\d+\.){3}\d+' | head -1
      register: vm_ip_result
      retries: 10
      delay: 10
      until: vm_ip_result.stdout != ""
      when: not vm_exists
    
    - name: Set VM IP fact
      ansible.builtin.set_fact:
        vm_detected_ip: "{{ vm_ip_result.stdout | trim }}"
      when: not vm_exists
    
    - name: Wait for SSH to become available
      ansible.builtin.wait_for:
        host: "{{ vm_detected_ip }}"
        port: 22
        delay: 10
        timeout: 300
      when: not vm_exists
    
    # ========================================================================
    # Post-Provisioning Validation
    # ========================================================================
    - name: Test SSH connection to VM
      ansible.builtin.command:
        cmd: ssh -o StrictHostKeyChecking=no {{ ansible_user }}@{{ vm_detected_ip }} hostname
      register: ssh_test
      when: not vm_exists
    
    - name: Display VM information
      ansible.builtin.debug:
        msg:
          - "✅ VM Provisioned Successfully!"
          - "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          - "VM Name:       {{ vm_name }}"
          - "Hostname:      {{ vm_hostname }}.{{ vm_domain }}"
          - "IP Address:    {{ vm_detected_ip }}"
          - "vCPUs:         {{ vm_cpus }}"
          - "Memory:        {{ vm_memory }}MB"
          - "Disk:          {{ vm_disk_size }}GB"
          - "SSH User:      {{ ansible_user }}"
          - "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          - "SSH Command:   ssh {{ ansible_user }}@{{ vm_detected_ip }}"
          - "Console:       virsh console {{ vm_name }}"
          - "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      when: not vm_exists
    
    # ========================================================================
    # Add VM to Inventory (Dynamic)
    # ========================================================================
    - name: Add VM to in-memory inventory
      ansible.builtin.add_host:
        name: "{{ vm_name }}"
        groups: registry
        ansible_host: "{{ vm_detected_ip }}"
        ansible_user: "{{ ansible_user }}"
        ansible_ssh_private_key_file: "~/.ssh/id_rsa"
      when: not vm_exists

# ============================================================================
# Second Play: Verify VM Accessibility
# ============================================================================
- name: Verify Registry VM is Accessible
  hosts: registry
  gather_facts: no
  tasks:
    - name: Wait for cloud-init to complete
      ansible.builtin.wait_for:
        path: /var/lib/cloud/instance/boot-finished
        timeout: 300
    
    - name: Gather facts from VM
      ansible.builtin.setup:
    
    - name: Display VM facts
      ansible.builtin.debug:
        msg:
          - "OS:            {{ ansible_distribution }} {{ ansible_distribution_version }}"
          - "Kernel:        {{ ansible_kernel }}"
          - "Architecture:  {{ ansible_architecture }}"
          - "Total Memory:  {{ ansible_memtotal_mb }}MB"
          - "Total CPUs:    {{ ansible_processor_vcpus }}"
```

### Phase 5: Create Additional VM Provisioning Playbooks

**playbooks/provision-aap-vm.yml:**
```yaml
---
- name: Provision AAP VM using community.libvirt
  hosts: localhost
  vars:
    vm_name: "aap-controller"
    vm_memory: 16384  # AAP requires 16GB minimum
    vm_cpus: 4
    vm_disk_size: 60
    # ... (same pattern as provision-registry-vm.yml)
  
  tasks:
    # Same tasks as provision-registry-vm.yml
    # Just different VM name, specs, and cloud-init config
```

**playbooks/provision-haproxy-vm.yml:**
```yaml
---
- name: Provision HAProxy VM for OpenShift Load Balancer
  hosts: localhost
  vars:
    vm_name: "openshift-forwarder"
    vm_memory: 4096
    vm_cpus: 2
    vm_disk_size: 50
    # ... (same pattern)
```

**playbooks/provision-ocp-nodes-vms.yml:**
```yaml
---
- name: Provision OpenShift Node VMs for Agent-Based Install Testing
  hosts: localhost
  vars:
    ocp_nodes:
      - name: "ocp-master-1"
        memory: 16384
        cpus: 4
        disk: 120
        ip: "192.168.122.101"
        mac: "52:54:00:6c:3c:02"
      
      - name: "ocp-master-2"
        memory: 16384
        cpus: 4
        disk: 120
        ip: "192.168.122.102"
        mac: "52:54:00:6c:3c:03"
      
      - name: "ocp-master-3"
        memory: 16384
        cpus: 4
        disk: 120
        ip: "192.168.122.103"
        mac: "52:54:00:6c:3c:04"
  
  tasks:
    - name: Provision OCP node VMs
      ansible.builtin.include_tasks: tasks/provision-vm-libvirt.yml
      loop: "{{ ocp_nodes }}"
      loop_control:
        loop_var: node
```

### Phase 6: Create Reusable Task File

**tasks/provision-vm-libvirt.yml:**
```yaml
---
# Reusable task file for provisioning VMs with community.libvirt
# Include this file with:
#   ansible.builtin.include_tasks: tasks/provision-vm-libvirt.yml
#   vars:
#     vm_name: "my-vm"
#     vm_memory: 8192
#     vm_cpus: 2
#     ...

- name: Check if {{ vm_name }} exists
  community.libvirt.virt:
    command: list_vms
  register: existing_vms

- name: Create {{ vm_name }}
  when: vm_name not in existing_vms.list_vms
  block:
    - name: Download base image (if needed)
      ansible.builtin.get_url:
        url: "{{ base_image_url }}"
        dest: "{{ libvirt_images_path }}/{{ base_image_name }}"
    
    - name: Create VM disk
      ansible.builtin.command:
        cmd: qemu-img create -f qcow2 -F qcow2 -b {{ libvirt_images_path }}/{{ base_image_name }} {{ libvirt_images_path }}/{{ vm_name }}.qcow2 {{ vm_disk_size }}G
    
    # ... (cloud-init, XML generation, define, start)
    
    - name: Start {{ vm_name }}
      community.libvirt.virt:
        name: "{{ vm_name }}"
        state: running
```

## Consequences

### Positive

- ✅ **Pure Ansible**: No external dependencies (kcli removed)
- ✅ **Idempotent**: All playbooks can be safely re-run
- ✅ **Cloud-init support**: Proper VM initialization (user accounts, network config, SSH keys)
- ✅ **Development → Production parity**: Same Ansible tooling, different inventory
- ✅ **Template-based**: Reusable libvirt XML and cloud-init templates
- ✅ **Better error handling**: Ansible module error messages vs shell script failures
- ✅ **Easier debugging**: `ansible-playbook -vvv` shows exact libvirt API calls
- ✅ **Standard collection**: `community.libvirt` is well-maintained and documented

### Negative

- ⚠️ **More verbose**: Ansible playbooks are longer than single `kcli create vm` commands
- ⚠️ **Learning curve**: Developers must learn libvirt XML and cloud-init syntax
- ⚠️ **Template maintenance**: XML templates need updates for new VM types
- ⚠️ **Initial complexity**: More upfront work to set up templates

### Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **cloud-init failures** | MEDIUM | Extensive testing, fallback to manual config |
| **libvirt XML errors** | LOW | Use validated templates, test incrementally |
| **MAC address conflicts** | LOW | Generate unique MACs, document in inventory |
| **Disk space exhaustion** | MEDIUM | Pre-flight checks in playbooks |

## Migration Plan

### Phase 1: Setup (Week 1)

```bash
# Install community.libvirt collection
ansible-galaxy collection install community.libvirt

# Create directory structure
mkdir -p templates/libvirt
mkdir -p templates/cloud-init
mkdir -p tasks
```

### Phase 2: Create Templates (Week 1)

- Create `templates/libvirt/registry-vm.xml.j2`
- Create `templates/cloud-init/registry-user-data.yml.j2`
- Create `templates/cloud-init/registry-meta-data.yml.j2`
- Create `templates/cloud-init/registry-network-config.yml.j2`

### Phase 3: Rewrite provision-registry-vm.yml (Week 2)

- Replace kcli commands with `community.libvirt.virt` module
- Add cloud-init ISO generation
- Add idempotency checks (VM existence)
- Add post-provisioning validation

### Phase 4: Test (Week 2)

```bash
# Test fresh provisioning
ansible-playbook playbooks/provision-registry-vm.yml

# Test idempotency (should skip all tasks)
ansible-playbook playbooks/provision-registry-vm.yml

# Test VM deletion and re-provisioning
virsh destroy registry
virsh undefine registry --remove-all-storage
ansible-playbook playbooks/provision-registry-vm.yml
```

### Phase 5: Create Additional VM Playbooks (Week 3)

- Create `provision-aap-vm.yml`
- Create `provision-haproxy-vm.yml`
- Create `provision-ocp-nodes-vms.yml`
- Create reusable `tasks/provision-vm-libvirt.yml`

### Phase 6: Update Documentation (Week 3)

- Update README with libvirt examples
- Remove all kcli references
- Document cloud-init customization
- Add troubleshooting guide for libvirt/cloud-init

### Phase 7: Deprecate kcli (Week 4)

```bash
# Archive old kcli-based playbooks
mkdir -p archive/kcli-legacy
mv playbooks/provision-registry-vm.yml.bak archive/kcli-legacy/

# Remove kcli from setup-dependencies.yml
sed -i '/kcli/d' playbooks/setup-dependencies.yml

# Add deprecation notice
cat >> README.md <<EOF

## ⚠️ kcli Deprecated

kcli has been replaced with pure Ansible using \`community.libvirt\` as of v4.21.0.

For legacy kcli-based provisioning, see \`v4.20.0-airflow\` tag.
EOF
```

## Verification Criteria

✅ `community.libvirt` collection installed via `setup-dependencies.yml`  
✅ `provision-registry-vm.yml` uses `community.libvirt.virt` (no kcli)  
✅ Libvirt XML templates created for all VM types  
✅ Cloud-init templates configure users, SSH, network  
✅ Playbooks are idempotent (re-run without errors)  
✅ VMs boot successfully with cloud-init configuration  
✅ SSH access works with configured user and key  
✅ Network configuration applied correctly (static IP)  
✅ All kcli references removed from codebase  
✅ Documentation updated (README, templates, troubleshooting)  
✅ Migration guide created for kcli users  

## Timeline

- **Week 1**: Install collection, create templates
- **Week 2**: Rewrite `provision-registry-vm.yml`, testing
- **Week 3**: Create additional VM playbooks, reusable task file
- **Week 3**: Update documentation
- **Week 4**: Deprecate kcli, final validation

**Total Estimated Timeline: 4 weeks (~1 month)**

**⚠️ Note**: This timeline runs in parallel with ADR 0021 (Airflow → AAP) and ADR 0022 (Deprecate qubinode).

## Example: Complete Workflow (Before vs After)

### Before (kcli-based)

```bash
# Install kcli
pip install kcli

# Configure kcli
kcli create pool -p /var/lib/libvirt/images default

# Provision registry VM (non-idempotent shell command)
ansible-playbook playbooks/provision-registry-vm.yml
# Playbook runs: kcli create vm registry --memory 16384 --cpus 4 ...

# Manual cloud-init or kickstart setup
# Manual network configuration
# Manual SSH key injection
```

### After (community.libvirt-based)

```bash
# Install collection (one-time)
ansible-galaxy collection install community.libvirt

# Provision registry VM (idempotent Ansible playbook)
ansible-playbook playbooks/provision-registry-vm.yml
# Playbook:
#  - Creates disk from base image
#  - Generates cloud-init ISO
#  - Defines VM via libvirt XML
#  - Starts VM
#  - Waits for SSH
#  - Validates connectivity

# Re-run playbook (idempotent, skips existing VM)
ansible-playbook playbooks/provision-registry-vm.yml
# Output: "VM registry already exists. Skipping provisioning."
```

## Directory Structure Changes

### Before (v4.20.0 with kcli)

```
playbooks/
├── provision-registry-vm.yml       ← Uses kcli shell commands
└── ...

# kcli installed externally
pip install kcli
```

### After (v4.21.0 with community.libvirt)

```
playbooks/
├── provision-registry-vm.yml       ✅ REWRITTEN (uses community.libvirt)
├── provision-aap-vm.yml            ✅ NEW (uses community.libvirt)
├── provision-haproxy-vm.yml        ✅ NEW (uses community.libvirt)
├── provision-ocp-nodes-vms.yml     ✅ NEW (uses community.libvirt)
└── ...

templates/
├── libvirt/
│   ├── registry-vm.xml.j2          ✅ NEW (libvirt domain XML)
│   ├── aap-vm.xml.j2               ✅ NEW
│   ├── haproxy-vm.xml.j2           ✅ NEW
│   └── ocp-node-vm.xml.j2          ✅ NEW
└── cloud-init/
    ├── registry-user-data.yml.j2   ✅ NEW (cloud-init config)
    ├── registry-meta-data.yml.j2   ✅ NEW
    ├── registry-network-config.yml.j2 ✅ NEW
    └── ... (similar for each VM type)

tasks/
└── provision-vm-libvirt.yml        ✅ NEW (reusable task file)

archive/
└── kcli-legacy/                    📦 ARCHIVED (for reference)
    └── provision-registry-vm.yml.bak

docs/
├── libvirt-vm-provisioning.md      ✅ NEW (libvirt guide)
└── adrs/
    ├── 0018-registry-vm-deployment.md  (marked SUPERSEDED)
    └── 0023-pure-ansible-community-libvirt.md  ✅ THIS ADR

# No kcli installation needed
# Collection installed via: ansible-galaxy collection install community.libvirt
```

## Related ADRs

- **Supersedes:**
  - ADR 0018: Registry Deployment on Dedicated VM via kcli

- **Superseded By:** (none yet)

- **Related:**
  - ADR 0021: Deprecate Airflow and Adopt AAP
  - ADR 0022: Deprecate qubinode_navigator Dependency
  - ADR 0002: Ansible as Automation Framework

## References

1. PRD v4.21.0 (2026-05-28), Section 2 - "Migrate to Pure Ansible (Deprecate kcli and Qubinode)"
2. Ansible `community.libvirt` collection documentation - https://docs.ansible.com/ansible/latest/collections/community/libvirt/
3. Cloud-init documentation - https://cloudinit.readthedocs.io/
4. Libvirt domain XML format - https://libvirt.org/formatdomain.html
5. ADR 0018: Registry Deployment on Dedicated VM via kcli
