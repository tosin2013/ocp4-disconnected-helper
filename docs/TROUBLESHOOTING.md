# Troubleshooting Guide - OpenShift Disconnected Helper

## ADR 0024 Deployment Issues

This guide documents all issues encountered during roles-based deployment and their solutions.

---

## Issue #1-11: VM Provisioning Issues (RESOLVED)

**Historical Issues** (from previous session):
1. ✅ SSH key variable name mismatch
2. ✅ ISO tool auto-detection
3. ✅ Video model compatibility
4. ✅ Custom disk path support
5. ✅ VM disk file permissions (qemu:qemu)
6. ✅ Cloud-init ISO permissions
7. ✅ Delete tasks require become=yes
8. ✅ SELinux contexts (virt_image_t/virt_content_t)
9. ✅ Directory permissions (755, qemu:qemu)
10. ✅ DHCP timeout (increased to 300s)
11. ✅ gather_facts causing early SSH attempt

**Solution**: All fixed in `roles/common_vm/tasks/provision.yml`

**Reference**: See commit history for detailed fixes

---

## Issue #12: meta: end_role Not Supported (RESOLVED)

**Symptom**:
```
ERROR! invalid meta action requested: end_role
```

**Root Cause**: Ansible 2.16.18 doesn't support `meta: end_role` action

**Solution**: Use fact-based conditional logic instead:
```yaml
- name: Set VM exists fact
  ansible.builtin.set_fact:
    vm_already_exists: "{{ vm_name in existing_vms.list_vms }}"

- name: Provision new VM
  when: not (vm_already_exists | default(false) | bool)
  block:
    # All provisioning tasks here
```

**Files Modified**:
- `roles/common_vm/tasks/provision.yml`

**Lesson**: Use `when` conditionals on blocks instead of `meta: end_role/end_play`

---

## Issue #13: VM Detected But Doesn't Exist (RESOLVED)

**Symptom**:
```
TASK [common_vm : Display existing VM message]
    "msg": "VM registry already exists"

# But later:
fatal: [registry -> localhost]: FAILED! => {"attempts": 20, ...}
virsh list --all  # Shows no VMs
```

**Root Cause**: VM was detected in libvirt's list but was deleted between check and use

**Solution**: Implemented fact-based logic with `vm_already_exists` variable

**Status**: RESOLVED

---

## Issue #15: virsh domifaddr Returns Empty Even Though DHCP Works (CRITICAL)

**Symptom**:
```
TASK [common_vm : Display existing VM message]
    "msg": "VM registry already exists"

# But later:
fatal: [registry -> localhost]: FAILED! => {"attempts": 20, ...}
virsh list --all  # Shows no VMs
```

**Root Cause**: VM was detected in libvirt's list but was deleted between check and use

**Potential Solutions**:
1. Add VM state check (running/shut off) after existence check
2. Check VM is actually responsive before skipping provisioning
3. Handle race condition where VM is deleted mid-deployment

**Status**: Under investigation

**Workaround**: Use `vm_force_recreate=true` to provision fresh VM

---

## Issue #14: ansible_connection: local Required

**Symptom**:
```
UNREACHABLE! => {"changed": false, "msg": "Data could not be sent to remote host..."}
```

**Root Cause**: Playbook tries to SSH to `registry` host before VM exists

**Solution**: Add `ansible_connection: local` to playbook:
```yaml
- name: Deploy Registry VM with Mirror-Registry
  hosts: registry
  gather_facts: no
  vars:
    ansible_connection: local
```

**Files Modified**:
- `playbooks/deploy-registry.yml`

**Lesson**: When provisioning the target host itself, use local connection

**Symptom**:
```
FAILED - RETRYING: Detect VM current IP address (20 retries left)...
fatal: [registry -> localhost]: FAILED! => {"attempts": 20, "cmd": ["virsh", "domifaddr", "registry"]}
stdout: " Name       MAC address          Protocol     Address\n-------------------------------------------------------------------------------"

# But dnsmasq logs show DHCP worked:
journalctl -u libvirtd | grep registry
Jun 03 13:13:38 dnsmasq-dhcp: DHCPACK(virbr0) 192.168.122.24 52:54:00:30:22:28 registry
```

**Root Cause**: `virsh domifaddr` depends on **qemu-guest-agent** running inside the VM. On fresh CentOS Stream VMs:
1. Cloud-init starts
2. Network comes up and gets DHCP
3. qemu-guest-agent installs (if in cloud-init packages)
4. qemu-guest-agent starts
5. Only then does `virsh domifaddr` work

This can take 2-5 minutes, longer than our 300-second timeout!

**Solutions**:

**Option A: Parse dnsmasq DHCP leases** (RECOMMENDED - implemented)
```yaml
- name: Get DHCP lease for VM
  ansible.builtin.command:
    cmd: awk '/{{ vm_mac_address }}/ {print $3}' /var/lib/libvirt/dnsmasq/virbr0.status
  register: dhcp_lease
```

**Option B: Use arp-scan on virbr0 network**
```bash
arp-scan --interface=virbr0 192.168.122.0/24 | grep 52:54:00
```

**Option C: Increase timeout to 10 minutes**
```yaml
retries: 40
delay: 15
# Total: 600 seconds
```

**Files Modified**:
- `roles/common_vm/tasks/configure_static_ip.yml`

**Lesson**: Don't rely on qemu-guest-agent for IP detection during provisioning. Use DHCP leases or network scanning instead.

**FINAL SOLUTION (Issue #16)**: Switched to **static DHCP reservations** in libvirt network config instead of complex DHCP detection + NetworkManager reconfiguration. See Issue #16 below.

---

## Issue #16: Static DHCP Reservations - The Correct Approach (IMPLEMENTED)

**Problem**: Previous approaches were fighting the system:
1. Cloud-init network-config doesn't work on CentOS Stream 9
2. DHCP detection requires qemu-guest-agent (slow)
3. Post-boot NetworkManager reconfiguration is complex and error-prone

**Solution**: Use libvirt's built-in static DHCP reservations

**How It Works**:
1. Generate deterministic MAC address from VM name: `52:54:00:xx:xx:xx`
2. Create DHCP reservation in libvirt network BEFORE VM creation:
   ```xml
   <host mac='52:54:00:ab:cd:ef' name='registry' ip='192.168.122.24'/>
   ```
3. VM gets static IP via DHCP immediately on first boot
4. No cloud-init network config needed
5. No post-boot reconfiguration needed

**Benefits**:
✅ Works on all Linux distributions  
✅ IP assigned in <5 seconds (normal DHCP time)  
✅ No qemu-guest-agent dependency  
✅ No NetworkManager commands needed  
✅ Survives VM recreation (reservation persists)  
✅ Standard KVM/libvirt pattern  

**Implementation**:
```yaml
# roles/common_vm/tasks/setup_static_dhcp.yml
- Generate MAC from VM name (deterministic)
- Create DHCP reservation: virsh net-update default add ip-dhcp-host
- Provision VM with pre-configured MAC
- VM boots and gets static IP via DHCP automatically
```

**Files Modified**:
- `roles/common_vm/tasks/setup_static_dhcp.yml` (NEW)
- `roles/common_vm/tasks/main.yml` (call setup_static_dhcp before provision)
- `roles/common_vm/templates/libvirt/domain.xml.j2` (add MAC address)
- `roles/common_vm/defaults/main.yml` (add vm_mac_address variable)

**Removed**:
- `roles/common_vm/tasks/configure_static_ip.yml` (complex NetworkManager approach)
- All DHCP lease parsing logic

**Lesson**: Use the platform's native features instead of working around them. Libvirt static DHCP is the standard KVM pattern for static IPs.

---

## oc-mirror Issues

### oc-mirror Playbook Fails Immediately with "Port 55000 Already Bound"

#### Symptoms
- Playbook `download-to-disk-v2.yml` fails in <5 seconds
- Error message: `[ERROR] [Executor] 55000 is already bound and cannot be used`
- Port 55000 is NOT actually in use: `ss -tlnp | grep 55000` shows nothing
- No oc-mirror processes running: `ps aux | grep oc-mirror` shows nothing

#### Root Cause
Stale Ansible async cache from a previous failed run. The playbook is NOT executing fresh - it's returning a cached failure result.

#### Detection
1. **Execution time**: Cached failures return instantly (<5 seconds). Real oc-mirror runs take 1-60 minutes.
2. **Port check**: Run `sudo ss -tlnp | grep 55000` - if port is free, it's async cache, not a port conflict.
3. **Job ID**: Check logs for `ansible_job_id` (e.g., `j571283734101.416643`) - if same job ID appears across runs, it's cached.

#### Solution

**Step 1**: Clear Ansible async cache
```bash
sudo rm -rf /root/.ansible_async/*
rm -rf ~/.ansible_async/*
```

**Step 2**: Clear oc-mirror workspace (optional - only if workspace is corrupted)
```bash
sudo rm -rf /data/ocp-mirror-test/oc-mirror-workspace/*
```

**Step 3**: Re-run the playbook
```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/download-to-disk-v2.yml -e @extra_vars/mirror-v2-test.yml
```

#### Verification
After clearing cache, the playbook should:
- Take >30 seconds to start (installing prerequisites)
- Show oc-mirror progress messages
- Complete successfully with "✓ N / N images mirrored successfully"
- Real execution time: 1-60 minutes depending on image count

#### Prevention
- Playbook v1.1+ includes preflight warning for stale async cache
- Always check preflight warnings before execution
- Clear async cache after any failed oc-mirror run

#### References
- Incident Report: `docs/hardening/oc-mirror-async-cache-v1.0-2026-06-04.md`
- ADR 0003: "Operational Constraints > Ansible Async Cache Management"

---

## Common Diagnostic Commands

### Check VM Status
```bash
virsh list --all
virsh dominfo registry
virsh domifaddr registry
```

### Check VM Network
```bash
# From hypervisor:
virsh domifaddr registry
ping 192.168.122.24  # Or static IP

# From VM console:
virsh console registry
ip addr show
nmcli connection show
```

### Check Libvirt Permissions
```bash
# Directory:
stat -c 'Access: %a %A  Context: %C  Owner: %U:%G' /data/libvirt-images/

# Files:
stat -c '%n: %a %U:%G %C' /data/libvirt-images/registry.qcow2
stat -c '%n: %a %U:%G %C' /data/libvirt-images/registry-cloud-init.iso

# Expected:
# Directory: 755 drwxr-xr-x  system_u:object_r:virt_image_t:s0  Owner: qemu:qemu
# Disk: 644 qemu:qemu system_u:object_r:virt_image_t:s0
# ISO: 644 qemu:qemu system_u:object_r:virt_content_t:s0
```

### Check Registry Containers
```bash
ssh registry@192.168.122.24
podman ps -a
podman logs quay-app
systemctl status quay-pod.service
journalctl -u quay-pod.service -n 50
```

### Check Registry Health
```bash
# From hypervisor:
curl -k https://192.168.122.24:8443/health/instance

# Expected:
{"is_healthy": true}
```

### Check Cloud-Init Logs
```bash
ssh registry@192.168.122.24
cloud-init status
cat /var/log/cloud-init.log
cat /var/log/cloud-init-output.log
```

---

## Idempotence Verification

### Test 1: First Deployment
```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml
```

**Expected**:
- VM provisioned ✅
- Mirror-registry installed ✅
- Authentication configured ✅
- Health verified ✅
- Total time: ~8 minutes

### Test 2: Re-run (Should Skip Everything)
```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml
```

**Expected**:
- VM exists → skipped provisioning ✅
- Registry running → skipped installation ✅
- Auth already merged → skipped ✅
- Health verified ✅
- Total time: ~10 seconds
- **changed=0** (critical!)

### Test 3: Force Recreate
```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml -e vm_force_recreate=true
```

**Expected**:
- VM deleted → VM provisioned ✅
- Registry installed ✅
- Total time: ~8 minutes

### Test 4: Partial State Recovery
```bash
# Simulate: VM exists but registry not installed
ssh registry@192.168.122.24 "podman pod rm -f quay-pod"

ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml
```

**Expected**:
- VM exists → skipped provisioning ✅
- Registry not running → installed ✅
- Auth configured ✅
- Total time: ~3 minutes

---

## Debugging Ansible Roles

### Enable Debug Output
```bash
ansible-playbook -vvv -i inventory/ibm-cloud.yml playbooks/site.yml
```

### Test Role in Isolation
```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-registry.yml --tags registry_vm
```

### Check Role Variables
```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-registry.yml -e vm_force_recreate=true --start-at-task="Display existing VM message"
```

### Validate Role Syntax
```bash
ansible-playbook --syntax-check playbooks/site.yml
ansible-lint playbooks/site.yml
```

---

## Performance Issues

### Slow VM Boot
**Symptom**: VM takes >5 minutes to get IP

**Solutions**:
1. Increase timeout in `roles/common_vm/defaults/main.yml`:
   ```yaml
   vm_boot_timeout: 60  # Increase to 120
   vm_network_timeout: 300  # Increase to 600
   ```

2. Check cloud-init is working:
   ```bash
   virsh console registry
   cloud-init status --wait
   ```

### Slow Mirror-Registry Installation
**Symptom**: `mirror-registry install` takes >5 minutes

**Normal Behavior**: Downloads ~2GB of images, expect 3-5 minutes

**Check Progress**:
```bash
ssh registry@192.168.122.24
podman images
du -sh /opt/mirror-registry/quay-storage/
```

---

## Security Constraints (NEVER VIOLATE)

From user requirements (previous session):

⚠️ **CRITICAL**: 
- **"it is not good to skip the cert validation"** - NEVER use `-k, --insecure, verify=false` in production
- **"shouldn or ansible playbooks should have ran this"** - ALWAYS use Ansible playbooks, not raw commands

**Violations Will Break Trust**

---

## Known Limitations

### Cloud-Init Network Configuration
**Issue**: CentOS Stream 9 cloud-init network-config doesn't apply static IP reliably

**Workaround**: Use post-boot NetworkManager configuration (already implemented in `configure_static_ip.yml`)

### Nested KVM Performance
**Issue**: VMs may be slower on nested KVM (IBM Cloud VM → KVM → downstream VMs)

**Expected**: This is normal for nested virtualization

---

## Rollback Procedures

### Registry Deployment Fails Mid-Install

**Automatic Rollback**: Role already implements cleanup on failure

**Manual Rollback**:
```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-registry.yml -e vm_state=absent
```

### Partial State Corruption

**Symptoms**:
- VM exists but won't boot
- Mirror-registry containers in crashed state
- Disk corruption

**Solution**: Force recreation
```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml -e vm_force_recreate=true
```

---

## Getting Help

1. **Check Logs**: Always check Ansible output, cloud-init logs, journald
2. **Verify Prerequisites**: Ensure base image exists, network is up, libvirt is running
3. **Test Components**: Isolate issue (is it VM provisioning? Registry installation? Network?)
4. **Document Finding**: Add to this guide for future reference

**Platform Team Contact**: [Add contact info]

---

## Future Improvements

- [ ] Add health check before declaring VM "exists"
- [ ] Implement retry logic for network flakiness
- [ ] Add pre-flight checks (disk space, memory, CPU)
- [ ] Create automated smoke tests
- [ ] Add metrics collection for deployment time tracking
