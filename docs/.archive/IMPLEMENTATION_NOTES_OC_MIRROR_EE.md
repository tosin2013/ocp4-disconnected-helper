# Implementation Notes: oc-mirror in AAP Custom Execution Environment

**Date**: 2026-06-10  
**Implements**: ADR 0029 § oc-mirror Enhancement  
**Related ADRs**: ADR 0003 (oc-mirror v2), ADR 0021 (AAP Adoption)

---

## Problem Statement

AAP job template "Mirror OpenShift Images to Registry" failed with:
```
fatal: [localhost]: FAILED! => {"msg": "[Errno 2] No such file or directory: b'oc-mirror'"}
```

**Root Causes**:
1. Custom execution environment included `oc` and `kubectl` but not `oc-mirror`
2. AAP controller VM has only 60GB disk (insufficient for 50GB mirror operations)
3. Hypervisor has 1TB at `/data` but AAP jobs run locally on controller by default

---

## Solution Architecture

### 1. Add oc-mirror Binary to Custom EE

**Changes**: `ocp4-aap-execution-environment/execution-environment.yml`

Added oc-mirror installation in `prepend_galaxy` section:
- Downloads from: `https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-4.21/oc-mirror.tar.gz`
- Installs to: `/usr/local/bin/oc-mirror` with symlink at `/usr/bin/oc-mirror`
- Configured via: `files/optional-configs/oc-mirror-install.env`

**Impact**:
- EE image size: +300MB (oc-mirror binary)
- Build time: +2-3 minutes
- Total EE size: ~3GB

### 2. Enable SSH Delegation to Hypervisor

**Storage Architecture**:
```
Before (FAILED):
AAP Job → Runs on AAP Controller (192.168.10.21, 60GB) → No space ❌

After (SUCCESS):
AAP Web UI → AAP Controller spawns EE → SSH to Hypervisor (10.241.64.9) →
oc-mirror downloads to /data/ocp-mirror/ (1TB storage) ✅
```

**Changes**: `playbooks/configure-aap-job-templates.yml`
- Added `limit: "kvm-host"` to "Mirror OpenShift Images" job template
- Forces execution on hypervisor instead of AAP controller
- Requires "KVM Hypervisor SSH Key" credential

**Changes**: `playbooks/push-to-registry-v2.yml`
- Changed `hosts: localhost` → `hosts: all`
- Allows AAP job template's limit to resolve target to `kvm-host`

---

## Implementation Steps Completed

### 1. ADR Updates
- ✅ Updated ADR 0029 with oc-mirror Enhancement section
- ✅ Documented storage architecture and SSH delegation

### 2. Execution Environment Repository
- ✅ Updated `execution-environment.yml` with oc-mirror installation
- ✅ Created `files/optional-configs/oc-mirror-install.env`
- ✅ Committed and pushed to GitHub

### 3. Main Project Repository
- ✅ Updated `configure-aap-job-templates.yml` with limit
- ✅ Updated `push-to-registry-v2.yml` hosts directive
- ✅ Committed and pushed to GitHub

### 4. Custom EE Build
- ✅ Fixed trailing space in `registry_username` (again!)
- 🔄 Building updated EE with oc-mirror (~15-20 minutes)

---

## Next Steps

### After EE Build Completes

1. **Verify Build Success**:
   ```bash
   podman images quay.io/takinosh/ocp4-aap-execution-environment:latest
   ```

2. **Sync AAP Project** (pulls updated playbooks):
   ```bash
   ansible-playbook -i inventory/ibm-cloud.yml \
     playbooks/create-aap-project.yml \
     -e@extra_vars/rhel-subscription-secrets.yml \
     --vault-password-file ~/.vault_pass
   ```

3. **Re-configure AAP Job Templates** (applies limit setting):
   ```bash
   ansible-playbook -i inventory/ibm-cloud.yml \
     playbooks/configure-aap-job-templates.yml \
     -e@extra_vars/rhel-subscription-secrets.yml \
     --vault-password-file ~/.vault_pass
   ```

4. **Test Mirroring Job**:
   - Login: https://aap.sandbox3377.opentlc.com
   - Navigate: Resources → Templates
   - Launch: "Mirror OpenShift Images to Registry"
   - Expected: Job SSH's to hypervisor, downloads ~50GB to `/data/ocp-mirror/`

---

## Verification Checklist

### Pre-Launch Verification

- [ ] Custom EE image built successfully with oc-mirror
- [ ] Custom EE image pushed to Quay.io
- [ ] AAP project synced (latest commit: `eb0b9cc`)
- [ ] AAP job templates updated with limit
- [ ] SSH key "KVM Hypervisor SSH Key" exists in AAP credentials

### Post-Launch Verification

- [ ] Job executes on `kvm-host` (10.241.64.9), not localhost
- [ ] oc-mirror binary found and version check passes
- [ ] Downloads write to `/data/ocp-mirror/` (not controller)
- [ ] Disk space adequate throughout download (monitor `df -h /data`)
- [ ] Images successfully pushed to registry at 192.168.10.10:8443

### Success Criteria

```bash
# On hypervisor after successful mirror:
ls -lh /data/ocp-mirror/oc-mirror-workspace/
# Expected: workspace directory with ImageSetConfiguration

du -sh /data/ocp-mirror/
# Expected: ~50GB total

curl -sk https://192.168.10.10:8443/v2/_catalog | jq
# Expected: repositories list including openshift4 images
```

---

## Lessons Learned

### Credential Trailing Space Issue (Recurring)

**Pattern**: Service account credentials with trailing spaces fail authentication.

**Affected**:
1. AAP installer inventory: `registry_username='<YOUR-ORG-ID>|ansible-execution-environment '`
2. Ansible Vault: `registry_username: "<YOUR-ORG-ID>|ansible-execution-environment "`

**Prevention**:
- Pre-commit hook detects some patterns but not all
- Manual verification needed: `cat -A <file>` to show trailing spaces
- Consider: Ansible Vault validation playbook

### Storage Architecture Planning

**Critical Question**: "Where does the data go?"

For AAP job templates:
- Default: Executes on AAP controller (limited disk)
- Solution: Use `limit` to delegate to target with adequate storage
- Document: Storage requirements in job template description

---

## Related Files

### Custom EE Repository
- `execution-environment.yml` - EE definition with oc-mirror
- `files/optional-configs/oc-mirror-install.env` - oc-mirror version config

### Main Project Repository
- `docs/adrs/0029-custom-execution-environment-for-aap-registry-authentication.md` - Enhanced ADR
- `playbooks/configure-aap-job-templates.yml` - Job template with limit
- `playbooks/push-to-registry-v2.yml` - Updated hosts directive
- `playbooks/build-custom-ee.yml` - EE build automation

### AAP Configuration
- Job Template: "Mirror OpenShift Images to Registry" (ID 17)
- Inventory: "Disconnected Infrastructure"
- Credential: "KVM Hypervisor SSH Key"
- Project: "ocp4-disconnected-helper" (ID 15)

---

## References

- ADR 0029: Custom Execution Environment for AAP Registry Authentication
- ADR 0003: oc-mirror v2 for Image Mirroring
- ADR 0021: Deprecate Airflow and Adopt AAP
- [oc-mirror Documentation](https://docs.openshift.com/container-platform/4.21/installing/disconnected_install/installing-mirroring-creating-registry.html)

---

**Status**: ✅ Implementation complete, awaiting EE build  
**EE Build Started**: 2026-06-10 13:52 UTC  
**Expected Completion**: ~14:10 UTC (15-20 minutes)
