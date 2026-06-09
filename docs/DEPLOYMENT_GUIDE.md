# OpenShift Disconnected Helper - Deployment Guide

## Architecture Overview

This project uses **ADR 0024: Roles and Collections Architecture** for atomic, idempotent deployments.

**Key Principles**:
- ✅ **Single Entrypoint**: `playbooks/site.yml` deploys entire stack
- ✅ **Idempotent**: Safe to run multiple times, only changes what's needed
- ✅ **Atomic Roles**: Each role handles complete lifecycle (provision → install → verify → cleanup)
- ✅ **Tag-Based Control**: Deploy specific components with `--tags`

---

## Quick Start

### Deploy Everything (Recommended)

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml
```

This single command deploys:
1. **Registry VM** (KVM) + **Mirror-Registry** (Quay)
2. **AAP VM** (KVM) + **AAP 2.5 Containerized** *(when ready)*

**Idempotence**: Run it 10 times, only changes what's missing!

---

## Component-Specific Deployment

### Deploy Only Registry

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml --tags registry
```

### Deploy Only AAP (when ready)

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml --tags aap
```

### Skip AAP Deployment

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml --skip-tags aap
```

---

## Individual Playbooks (Legacy)

For granular control, individual playbooks still work:

### Registry Deployment

```bash
# Deploy registry (idempotent)
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-registry.yml

# Force recreate VM and reinstall everything
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-registry.yml -e vm_force_recreate=true
```

### AAP Deployment (Planned)

```bash
# Deploy AAP (idempotent)
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml

# Force recreate
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml -e vm_force_recreate=true
```

---

## What Happens During Deployment

### Registry Deployment (`deploy-registry.yml`)

The `registry_vm` role executes these steps **atomically**:

1. **Provision VM** (via `common_vm` role):
   - ✅ Check if VM exists → skip if present (unless `vm_force_recreate=true`)
   - ✅ Create VM disk from CentOS Stream base image
   - ✅ Generate cloud-init ISO with SSH keys
   - ✅ Define and start VM in libvirt
   - ✅ Configure static IP via NetworkManager

2. **Install Mirror-Registry**:
   - ✅ Check if Quay containers exist → skip if already installed
   - ✅ Install Podman, configure sysctl, firewall
   - ✅ Download and extract mirror-registry tarball
   - ✅ Run installation (creates quay-app, postgres, redis containers)
   - ✅ Save credentials to `/opt/mirror-registry/credentials.txt`

3. **Setup Authentication**:
   - ✅ Check for pull-secret → skip gracefully if missing
   - ✅ Merge registry credentials into pull-secret
   - ✅ Write combined pull-secret locally

4. **Verify Health**:
   - ✅ Check registry API health endpoint
   - ✅ Validate containers are running

**Rollback**: If any step fails, the role automatically cleans up (deletes VM, removes containers).

---

## Idempotence Behavior

### First Run
```
VM doesn't exist     → Provision VM (5 min)
Registry not running → Install mirror-registry (3 min)
Pull-secret exists   → Merge authentication (5 sec)
                     → Verify health (5 sec)
Total: ~8 minutes
```

### Second Run (Everything Exists)
```
VM exists            → Skip provisioning
Registry running     → Skip installation
Pull-secret merged   → Skip authentication
                     → Verify health (5 sec)
Total: ~10 seconds
```

### Partial State (VM exists, but registry not installed)
```
VM exists            → Skip provisioning
Registry not running → Install mirror-registry (3 min)
Pull-secret exists   → Merge authentication (5 sec)
                     → Verify health (5 sec)
Total: ~3 minutes
```

---

## Advanced Usage

### Dry Run (Check Mode)

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml --check
```

**Note**: Some tasks (like checking if containers exist) may not work in `--check` mode.

### Verbose Output

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml -v   # Basic
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml -vv  # More detail
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml -vvv # Debug level
```

### Limit to Specific Host

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml --limit registry
```

---

## Cleanup / Teardown

### Delete Registry VM

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-registry.yml -e vm_state=absent
```

This removes:
- ✅ Running VM (shutdown and undefine)
- ✅ VM disk file (`/data/libvirt-images/registry.qcow2`)
- ✅ Cloud-init ISO

### Delete AAP VM (when ready)

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml -e vm_state=absent
```

---

## Troubleshooting

### Check VM Status

```bash
virsh list --all
virsh domifaddr registry
ssh registry@192.168.122.24  # or static IP from inventory
```

### Check Registry Containers

```bash
ssh registry@192.168.122.24
podman ps -a
journalctl -u quay-pod.service -n 50
```

### Check Registry Health

```bash
curl -k https://192.168.122.24:8443/health/instance
```

### Common Issues

**Issue**: `Permission denied (publickey)` when SSH to VM

**Solution**: Check cloud-init injected SSH key:
```bash
virsh console registry  # Login with user/password
cat ~/.ssh/authorized_keys
```

**Issue**: `Cannot access storage file` (libvirt permission error)

**Solution**: Already fixed in `common_vm` role (files owned by `qemu:qemu` with SELinux context `virt_image_t`)

**Issue**: VM doesn't get DHCP IP after 5 minutes

**Solution**: Increase timeout in `roles/common_vm/defaults/main.yml`:
```yaml
vm_network_timeout: 300  # Increase to 600 if needed
```

---

## Migration from Old Playbooks

### Before (Disconnected Playbooks)
```bash
# Had to run 4 separate playbooks in order:
ansible-playbook -i inventory/ibm-cloud.yml playbooks/provision-registry-vm.yml
ansible-playbook -i inventory/ibm-cloud.yml playbooks/configure-vm-static-ip.yml
ansible-playbook -i inventory/ibm-cloud.yml playbooks/setup-mirror-registry.yml
ansible-playbook -i inventory/ibm-cloud.yml playbooks/setup-registry-authentication.yml

# Not idempotent - errors if VM already exists
# Manual cleanup required between runs
```

### After (ADR 0024 Roles Architecture)
```bash
# Single command, fully idempotent:
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml
```

**Benefits**:
- ✅ Atomic operations with automatic rollback
- ✅ Idempotent - safe to re-run
- ✅ Single entrypoint reduces cognitive load
- ✅ Tags enable component-specific deployment
- ✅ Easier to test and maintain

---

## Next Steps After Deployment

1. **Test Registry Login**:
   ```bash
   podman login https://$(grep quay_url inventory/ibm-cloud.yml | awk '{print $2}'):8443
   ```

2. **Mirror OpenShift Images**:
   ```bash
   ansible-playbook -i inventory/ibm-cloud.yml playbooks/download-to-disk-v2.yml
   ansible-playbook -i inventory/ibm-cloud.yml playbooks/push-to-registry-v2.yml
   ```

3. **Deploy AAP** (when role is ready):
   ```bash
   ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml --tags aap
   ```

4. **Validate oc-mirror Workflow**:
   ```bash
   # Test oc-mirror can push to registry
   oc-mirror --config imageset-config.yaml docker://registry.example.com:8443
   ```

---

## Architecture Decision Records

See `docs/architecture/decisions/` for design rationale:

- **ADR-0024**: Roles and Collections Architecture (this deployment model)
- **ADR-0009**: HashiCorp Vault Integration (planned for Tier 2)
- **ADR-0021**: Ansible Automation Platform Migration (AAP 2.5 deployment)

---

## Support

**Documentation**:
- Main README: `/README.md`
- Getting Started: `/docs/GETTING_STARTED.md`
- oc-mirror Workflow: `/docs/oc-mirror-workflow.md`

**Issue Tracking**: Contact Platform Team for support
