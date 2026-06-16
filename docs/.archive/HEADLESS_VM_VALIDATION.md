# Headless VM Provisioning Validation Plan

**Context**: ocp4-disconnected-helper v4.21.0 migration requires VM provisioning on **headless KVM host** (no GUI, no X11 display).

**Reference**: [HAProxy Forwarder Guide](https://tosin2013.github.io/openshift-agent-install/haproxy-forwarder-guide/) - proven headless approach.

---

## Problem Statement

The v4.21.0 migration plan (ADR 0023) proposes using `community.libvirt` Ansible collection for VM provisioning. Before proceeding with Phase 1, we must validate that this approach works in a **headless environment**.

### Constraints

- **No GUI**: Server has no X11 display, no virt-manager
- **CLI-only**: All VM operations must be scriptable via Ansible/bash
- **Cloud-init**: VM initialization must be automated (no manual console interaction)
- **Remote management**: VMs must be manageable via SSH only

---

## Validation Requirements

### ✅ Required Tools (Headless-Compatible)

- `virsh` - libvirt CLI for VM management
- `virt-install` - CLI VM creation (no GUI needed)
- `qemu-img` - Disk image management
- `genisoimage` - Cloud-init ISO generation
- `libvirtd` - KVM hypervisor service

### ❌ Not Required (GUI Tools)

- ~~`virt-manager`~~ - GUI tool, not needed
- ~~`virt-viewer`~~ - VNC/SPICE viewer, not needed
- ~~X11/Xorg~~ - No graphical display needed

---

## Validation Plan: Pre-Phase 1

Before starting Phase 1 (libvirt migration), execute this validation:

### **Task 0.4: Headless Libvirt Validation** (NEW)

**Status**: 🔴 NOT STARTED  
**Priority**: P0 (BLOCKER for Phase 1)  
**Owner**: Platform Team  
**Effort**: 1 day  
**Dependencies**: None (can start immediately)

**Description**:  
Validate that libvirt VM provisioning works in headless environment using proven approach from HAProxy forwarder guide.

**Validation Steps**:

#### Step 1: Install Headless Libvirt Stack

```bash
# Create validation playbook
cat > playbooks/validate-headless-libvirt.yml <<'EOF'
---
- name: Validate Headless Libvirt Stack
  hosts: localhost
  become: yes
  
  tasks:
    - name: Install libvirt packages (headless)
      ansible.builtin.dnf:
        name:
          - libvirt
          - libvirt-client          # virsh CLI
          - qemu-kvm                 # KVM hypervisor
          - virt-install             # CLI VM installer (no GUI)
          - python3-libvirt          # Python bindings
          - genisoimage              # Cloud-init ISO
          - qemu-img                 # Disk management
        state: present
    
    - name: Ensure virt-manager is NOT installed (we don't need GUI)
      ansible.builtin.dnf:
        name: virt-manager
        state: absent
    
    - name: Enable and start libvirtd
      ansible.builtin.systemd:
        name: libvirtd
        enabled: yes
        state: started
    
    - name: Verify virsh connection (headless)
      ansible.builtin.command:
        cmd: virsh --connect qemu:///system list --all
      register: virsh_test
      changed_when: false
    
    - name: Display virsh output
      ansible.builtin.debug:
        msg: "✅ virsh works in headless mode: {{ virsh_test.stdout_lines }}"
EOF

# Run validation
ansible-playbook playbooks/validate-headless-libvirt.yml
```

**Expected Output**:
```
✅ virsh works in headless mode: [' Id   Name   State', '--------------------']
```

---

#### Step 2: Create Test VM Using Headless Method

**Approach**: Use `virt-install` CLI with `--graphics none` (proven by HAProxy guide).

```bash
# Create minimal test VM playbook
cat > playbooks/test-headless-vm.yml <<'EOF'
---
- name: Test Headless VM Creation
  hosts: localhost
  become: yes
  vars:
    test_vm_name: "headless-test-vm"
    test_vm_memory: 512
    test_vm_cpus: 1
    test_vm_disk: "/var/lib/libvirt/images/{{ test_vm_name }}.qcow2"
  
  tasks:
    - name: Check if test VM already exists
      ansible.builtin.command:
        cmd: virsh --connect qemu:///system dominfo {{ test_vm_name }}
      register: vm_check
      failed_when: false
      changed_when: false
    
    - name: Remove existing test VM if present
      ansible.builtin.command:
        cmd: virsh --connect qemu:///system undefine {{ test_vm_name }} --remove-all-storage
      when: vm_check.rc == 0
    
    - name: Create test VM disk
      ansible.builtin.command:
        cmd: qemu-img create -f qcow2 {{ test_vm_disk }} 10G
      args:
        creates: "{{ test_vm_disk }}"
    
    - name: Create test cloud-init user-data
      ansible.builtin.copy:
        dest: /tmp/test-user-data
        content: |
          #cloud-config
          hostname: headless-test
          users:
            - name: testuser
              sudo: ALL=(ALL) NOPASSWD:ALL
              ssh_authorized_keys:
                - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... # Replace with actual key
          runcmd:
            - echo "✅ Cloud-init worked in headless VM" > /tmp/cloud-init-success
    
    - name: Create test cloud-init meta-data
      ansible.builtin.copy:
        dest: /tmp/test-meta-data
        content: |
          instance-id: {{ test_vm_name }}
          local-hostname: headless-test
    
    - name: Create cloud-init ISO
      ansible.builtin.command:
        cmd: genisoimage -output /var/lib/libvirt/images/test-cloud-init.iso -volid cidata -joliet -rock /tmp/test-user-data /tmp/test-meta-data
      args:
        creates: /var/lib/libvirt/images/test-cloud-init.iso
    
    - name: Create VM using virt-install (HEADLESS MODE)
      ansible.builtin.command:
        cmd: >
          virt-install
          --connect qemu:///system
          --name {{ test_vm_name }}
          --memory {{ test_vm_memory }}
          --vcpus {{ test_vm_cpus }}
          --disk path={{ test_vm_disk }},format=qcow2
          --cdrom /var/lib/libvirt/images/test-cloud-init.iso
          --os-variant rhel9.0
          --graphics none
          --noautoconsole
          --import
      register: virt_install_result
    
    - name: Wait for VM to start
      ansible.builtin.command:
        cmd: virsh --connect qemu:///system domstate {{ test_vm_name }}
      register: vm_state
      until: vm_state.stdout == "running"
      retries: 10
      delay: 5
    
    - name: Display VM info
      ansible.builtin.command:
        cmd: virsh --connect qemu:///system dominfo {{ test_vm_name }}
      register: vm_info
    
    - name: Show results
      ansible.builtin.debug:
        msg:
          - "✅ VM created successfully in HEADLESS mode"
          - "VM State: {{ vm_state.stdout }}"
          - "Graphics: NONE (headless)"
          - "Cloud-init: ISO attached"
          - ""
          - "{{ vm_info.stdout_lines }}"
EOF

# Run test
ansible-playbook playbooks/test-headless-vm.yml
```

**Success Criteria**:
- [x] VM created without GUI (`--graphics none` works)
- [x] VM shows as "running" in `virsh list`
- [x] Cloud-init ISO attached
- [x] No errors about missing X11 display

---

#### Step 3: Validate community.libvirt Collection (Headless)

```bash
# Install collection
ansible-galaxy collection install community.libvirt

# Test collection in headless mode
cat > playbooks/test-community-libvirt.yml <<'EOF'
---
- name: Test community.libvirt Collection (Headless)
  hosts: localhost
  vars:
    test_vm_name: "libvirt-collection-test"
  
  tasks:
    - name: List VMs using community.libvirt
      community.libvirt.virt:
        command: list_vms
      register: vm_list
    
    - name: Display VMs
      ansible.builtin.debug:
        msg: "✅ community.libvirt works headless: {{ vm_list.list_vms }}"
    
    - name: Get VM info using community.libvirt
      community.libvirt.virt:
        command: info
      register: vm_info
    
    - name: Display info
      ansible.builtin.debug:
        msg: "✅ VM info retrieved: {{ vm_info }}"
EOF

ansible-playbook playbooks/test-community-libvirt.yml
```

**Success Criteria**:
- [x] `community.libvirt.virt` module works without GUI
- [x] Can list VMs
- [x] Can get VM info
- [x] No X11/display errors

---

#### Step 4: Cleanup Test VM

```bash
# Cleanup playbook
cat > playbooks/cleanup-headless-test.yml <<'EOF'
---
- name: Cleanup Headless Test VMs
  hosts: localhost
  become: yes
  
  tasks:
    - name: Destroy and undefine test VMs
      ansible.builtin.command:
        cmd: virsh --connect qemu:///system undefine {{ item }} --remove-all-storage
      loop:
        - headless-test-vm
        - libvirt-collection-test
      failed_when: false
    
    - name: Remove cloud-init test files
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop:
        - /tmp/test-user-data
        - /tmp/test-meta-data
        - /var/lib/libvirt/images/test-cloud-init.iso
    
    - name: Confirm cleanup
      ansible.builtin.command:
        cmd: virsh --connect qemu:///system list --all
      register: final_check
    
    - name: Display final state
      ansible.builtin.debug:
        msg: "✅ Cleanup complete: {{ final_check.stdout_lines }}"
EOF

ansible-playbook playbooks/cleanup-headless-test.yml
```

---

## Headless VM Management Patterns

### ✅ Proven Headless Techniques

Based on HAProxy forwarder guide, these patterns work:

#### 1. **virt-install with --graphics none**
```bash
virt-install \
  --name my-vm \
  --memory 4096 \
  --vcpus 2 \
  --disk path=/var/lib/libvirt/images/my-vm.qcow2 \
  --graphics none \        # ← KEY: No GUI needed
  --noautoconsole \        # ← Don't auto-attach console
  --import
```

#### 2. **Serial Console Access (SSH Alternative)**
```bash
# If SSH not available, use serial console via virsh
virsh console my-vm

# Exit: Ctrl+]
```

#### 3. **Cloud-init for Automated Setup**
```yaml
#cloud-config
ssh_authorized_keys:
  - ssh-rsa AAAAB3... your-key-here

# No manual console interaction needed
```

#### 4. **VM State Management**
```bash
# All headless-compatible
virsh list --all                 # List VMs
virsh start my-vm                # Start VM
virsh shutdown my-vm             # Graceful shutdown
virsh destroy my-vm              # Force stop
virsh undefine my-vm             # Delete VM definition
```

---

## Integration with Phase 1

### Updated Task 1.3: Registry VM Rewrite (Headless-Aware)

**Add to playbook**:

```yaml
- name: Create VM using virt-install (HEADLESS MODE)
  ansible.builtin.command:
    cmd: >
      virt-install
      --connect qemu:///system
      --name {{ vm_name }}
      --memory {{ vm_memory }}
      --vcpus {{ vm_cpus }}
      --disk path={{ vm_disk }},format=qcow2
      --cdrom {{ cloud_init_iso }}
      --os-variant {{ os_variant | default('rhel9.0') }}
      --graphics none              # ← CRITICAL for headless
      --noautoconsole              # ← No auto-console attach
      --import
  when: not vm_exists
```

**OR use community.libvirt** (preferred):

```yaml
- name: Define VM in libvirt (HEADLESS)
  community.libvirt.virt:
    command: define
    xml: "{{ lookup('template', 'templates/libvirt/registry-vm.xml.j2') }}"

- name: Start VM
  community.libvirt.virt:
    name: "{{ vm_name }}"
    state: running
```

**XML Template must specify graphics type="none"**:

```xml
<domain type='kvm'>
  <!-- ... other config ... -->
  <devices>
    <!-- NO <graphics> element, or: -->
    <graphics type='none'/>  <!-- ← Explicitly headless -->
    
    <!-- Serial console for emergency access -->
    <serial type='pty'>
      <target type='isa-serial' port='0'>
        <model name='isa-serial'/>
      </target>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
  </devices>
</domain>
```

---

## Verification Checklist

Before proceeding to Phase 1:

- [ ] **Task 0.4 complete**: Headless libvirt validation passed
- [ ] `virsh` works without GUI
- [ ] `virt-install --graphics none` creates VM successfully
- [ ] `community.libvirt` collection works headless
- [ ] Cloud-init ISO approach validated
- [ ] Test VM accessible via SSH (not console)
- [ ] Serial console works as backup (virsh console)

**GO/NO-GO Decision**:
- ✅ **GO**: All validation tasks pass → Proceed to Phase 1
- ❌ **NO-GO**: Headless approach fails → Investigate alternative (e.g., keep kcli, or use OpenStack)

---

## Alternative Approaches (If Validation Fails)

### Option A: Keep kcli (Rollback v4.21.0 Scope)

If headless libvirt proves problematic:
- Remove ADR 0023 from v4.21.0 scope
- Keep kcli for VM provisioning
- Focus v4.21.0 on AAP + qubinode removal only

### Option B: Use Assisted Installer API

For OpenShift nodes specifically:
- Use Red Hat Assisted Installer service
- API-driven, no local VM provisioning needed
- Generates bootable ISOs with agent-based installer

### Option C: Manual virsh + XML Files

If `community.libvirt` fails but `virsh` works:
- Use `virsh define` with XML files
- Shell commands instead of Ansible modules
- More brittle but proven approach

---

## Timeline Impact

**If Task 0.4 passes**: No impact, Phase 1 proceeds as planned (Weeks 1-4)

**If Task 0.4 fails**:
- **Investigate**: 1 week
- **Implement alternative**: 2 weeks
- **Total delay**: 3 weeks (adjust RELEASE_PLAN.md timeline)

---

## References

1. **HAProxy Forwarder Guide**: https://tosin2013.github.io/openshift-agent-install/haproxy-forwarder-guide/
   - Proven headless approach for OCP deployments
   
2. **virt-install man page**: Headless options
   - `--graphics none` - No graphical console
   - `--noautoconsole` - Don't auto-attach console
   
3. **community.libvirt docs**: https://docs.ansible.com/ansible/latest/collections/community/libvirt/
   - Ansible collection for libvirt management
   
4. **Cloud-init docs**: https://cloudinit.readthedocs.io/
   - ISO NoCloud data source (works headless)

---

**Created**: 2026-06-02  
**Owner**: Platform Team  
**Status**: 🔴 VALIDATION REQUIRED before Phase 1  
**Next Action**: Execute Task 0.4 (Headless Libvirt Validation)
