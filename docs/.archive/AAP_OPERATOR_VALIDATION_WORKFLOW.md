# AAP Workflow: Disconnected OpenShift Image Mirroring with Operator Validation

**Created**: 2026-06-11  
**ADRs**: 0032 (Workflow Orchestration), 0033 (Validation Framework), 0034 (Operator Validation)  
**Status**: ✅ Ready for Deployment

---

## Overview

This AAP workflow provides end-to-end automation for mirroring OpenShift releases and operators to disconnected registries with **pre-flight operator validation** to prevent costly failures.

### Workflow Architecture

```
┌────────────────────────────────────────────────────────────┐
│  Workflow: Disconnected OpenShift Image Mirroring         │
└────────────────────────────────────────────────────────────┘
                         │
                         ▼
    ┌────────────────────────────────────────┐
    │ Node 1: Validate Operator Selection    │  ← NEW (ADR-0034)
    │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
    │ • Check operator names exist           │
    │ • Validate channels are available      │
    │ • Fuzzy-match suggestions for typos    │
    │ • Duration: <5 seconds (with cache)    │
    └────────────────────────────────────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
         ON SUCCESS             ON FAILURE
              │                     │
              ▼                     ▼
    ┌──────────────────┐    ┌──────────────┐
    │ Continue         │    │ STOP         │
    └──────────────────┘    │ Fix errors   │
              │             │ Re-run       │
              ▼             └──────────────┘
    ┌────────────────────────────────────────┐
    │ Node 2: Download Images (Phase 1)      │
    │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
    │ • oc-mirror mirrorToDisk workflow      │
    │ • Download to /data/ocp-mirror/        │
    │ • Duration: 5-60 min (image count)     │
    └────────────────────────────────────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
         ON SUCCESS             ON FAILURE
              │                     │
              ▼                     ▼
    ┌────────────────────┐    ┌──────────────┐
    │ Continue           │    │ STOP         │
    └────────────────────┘    │ Review logs  │
              │               └──────────────┘
              ▼
    ┌────────────────────────────────────────┐
    │ Node 3: Mirror to Registry (Phase 2)   │
    │ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
    │ • oc-mirror diskToMirror workflow      │
    │ • Push to target registry              │
    │ • Generate IDMS/ITMS manifests         │
    │ • Duration: 10-90 min (image count)    │
    └────────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │ ✅ Complete          │
              │                       │
              │ Artifacts:            │
              │ • Mirrored images     │
              │ • IDMS YAML           │
              │ • ITMS YAML           │
              │ • Signature ConfigMap │
              └──────────────────────┘
```

---

## Deployment Steps

### Prerequisites

1. **AAP 2.6 Installed**: https://aap.sandbox3377.opentlc.com
2. **Credentials Configured**:
   - `admin_password` (AAP Controller password)
   - `KVM Hypervisor SSH Key`
   - `Ansible Vault Password`
3. **Project Synced**: `ocp4-disconnected-helper` latest commit
4. **Execution Environment**: `OCP4 Custom EE with oc-mirror`

### Step 1: Deploy Workflow to AAP

```bash
cd /home/vpcuser/ocp4-disconnected-helper

ansible-playbook playbooks/aap-configuration/configure-oc-mirror-workflow.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Expected Output**:
```
✅ Operator validation template created (ADR-0034)
   ID: <job_template_id>
   Name: Validate Operator Selection

✅ Download template created
   ID: <job_template_id>
   Name: Download OpenShift Images to Disk (Phase 1)

✅ Push template created
   ID: <job_template_id>
   Name: Mirror Images to Registry (Phase 2)

✅ Workflow template created
   ID: <workflow_id>
   Name: Disconnected OpenShift Image Mirroring

Workflow Graph:
  1. Validate Operator Selection (NEW - ADR-0034)
     └─► ON SUCCESS → 2
     └─► ON FAILURE → STOP

  2. Download OpenShift Images (Phase 1)
     └─► ON SUCCESS → 3
     └─► ON FAILURE → STOP

  3. Mirror Images to Registry (Phase 2)
     └─► ON SUCCESS → Complete
     └─► ON FAILURE → Manual intervention required
```

**Duration**: ~30 seconds

---

### Step 2: Test Workflow with Storage Operators

#### Option A: Via AAP Web UI

1. Navigate to https://aap.sandbox3377.opentlc.com
2. Login with Gateway credentials:
   - Username: `admin`
   - Password: `<automationgateway_admin_password>`

3. Go to **Resources → Templates**
4. Find **"Disconnected OpenShift Image Mirroring"**
5. Click **Launch** (rocket icon)

6. Provide extra variables:
```yaml
---
# OpenShift Releases
openshift_releases:
  - name: stable-4.21
    minVersion: 4.21.0
    maxVersion: 4.21.0
    shortestPath: true

# Storage Operators
operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
    packages:
      - name: local-storage-operator
        channels:
          - name: stable
      - name: odf-operator
        channels:
          - name: stable-4.21

# Target Configuration
target_mirror_path: "/data/ocp-mirror"
target_registry: "registry.ocp4.sandbox3377.opentlc.com:8443"
target_namespace: "openshift4"
skip_tls_verify: false
```

7. Click **Next** → **Launch**

#### Option B: Via AAP API

```bash
# Get workflow ID
WORKFLOW_ID=$(curl -sk -u admin:<controller_password> \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/workflow_job_templates/" | \
  jq -r '.results[] | select(.name=="Disconnected OpenShift Image Mirroring") | .id')

# Launch workflow
curl -sk -u admin:<controller_password> \
  -X POST \
  -H "Content-Type: application/json" \
  -d @extra_vars/operators/storage-operators.yml \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/workflow_job_templates/${WORKFLOW_ID}/launch/"
```

---

### Step 3: Monitor Workflow Execution

#### Via Web UI

1. Go to **Views → Jobs**
2. Find latest "Disconnected OpenShift Image Mirroring" job
3. Watch workflow progress:
   - **Green**: Node succeeded
   - **Red**: Node failed
   - **Blue**: Node running

#### Via API

```bash
# Get latest workflow job
JOB_ID=$(curl -sk -u admin:<controller_password> \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/workflow_jobs/" | \
  jq -r '.results[0].id')

# Monitor workflow status
watch -n 5 "curl -sk -u admin:<controller_password> \
  'https://aap.sandbox3377.opentlc.com/api/controller/v2/workflow_jobs/${JOB_ID}/' | \
  jq -r '.status, .elapsed'"
```

---

## Expected Workflow Behavior

### Scenario 1: Valid Configuration (Happy Path)

**Input**: `extra_vars/operators/storage-operators.yml`

**Node 1 Output** (Validate Operators):
```
============================================
Operator Validation Results
============================================

Total Operators Checked: 2
✅ Valid: 2
❌ Invalid: 0

✅ All operators validated successfully!

Proceed with mirroring...
============================================

Status: successful
Duration: 3 seconds
```

**Node 2 Output** (Download):
```
oc-mirror v2 Download Complete
Workspace: /data/ocp-mirror/oc-mirror-workspace
Size: 45 GB
Images: 194 release + 50 operator images

Status: successful
Duration: 15 minutes
```

**Node 3 Output** (Push to Registry):
```
oc-mirror v2 Push Complete
Registry: registry.ocp4.sandbox3377.opentlc.com:8443
Namespace: openshift4
Images mirrored: 244 / 244

Artifacts generated:
- IDMS: /data/ocp-mirror/oc-mirror-workspace/.../idms-oc-mirror.yaml
- ITMS: /data/ocp-mirror/oc-mirror-workspace/.../itms-oc-mirror.yaml
- Signatures: /data/ocp-mirror/oc-mirror-workspace/.../signature-configmap.yaml

Status: successful
Duration: 25 minutes
```

**Total Duration**: ~43 minutes

---

### Scenario 2: Invalid Operators (Catches Errors Fast)

**Input**: `extra_vars/operators/test-validation.yml` (has intentional typos)

**Node 1 Output** (Validate Operators):
```
============================================
Operator Validation Results
============================================

Total Operators Checked: 6
✅ Valid: 4
❌ Invalid: 2

Invalid Operators:
  • local-storage (catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21)
    → Did you mean: local-storage-operator?
  • gitops (catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21)
    → Did you mean: openshift-gitops-operator?

Invalid Channels:
  • ocs-operator:stable-4.22 (catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21)
    → Available channels: stable-4.21

Status: failed
Duration: 4 seconds
```

**Workflow Status**: ❌ **STOPPED** at Node 1

**Nodes 2 & 3**: ⏭️ **SKIPPED** (not executed)

**Total Duration**: 4 seconds (vs 10-30 minutes if validation didn't exist)

**Next Steps**:
1. Fix operator names in extra_vars:
   - Change `local-storage` → `local-storage-operator`
   - Change `gitops` → `openshift-gitops-operator`
   - Change `ocs-operator:stable-4.22` → `ocs-operator:stable-4.21`

2. Re-launch workflow

---

## Performance Comparison

### Before Operator Validation (Old Workflow)

```
Time to Detect Invalid Operator:
  ├─ Start workflow: 0 min
  ├─ Download OCP releases: 5 min
  ├─ Download operators (fails here): 10 min
  └─ Error: "package local-storage not found"
  Total: 10 minutes wasted

Bandwidth Used: ~5-10 GB (partial download)
User Experience: ❌ Cryptic error, no suggestions
```

### After Operator Validation (New Workflow)

```
Time to Detect Invalid Operator:
  ├─ Start workflow: 0 min
  ├─ Validate operators (fails here): 0.05 min
  └─ Error: "Did you mean: local-storage-operator?"
  Total: 3 seconds

Bandwidth Used: ~73 KB (cache only)
User Experience: ✅ Clear error with suggestion
```

**Improvement**: **200x faster** error detection, **99.999% bandwidth savings**

---

## Troubleshooting

### Issue 1: Validation Node Fails - "Cache not found"

**Error**:
```
❌ ERROR: Operator catalog cache not found
```

**Cause**: First-time cache download failed or cache expired

**Solution**:
```bash
# Force cache refresh via extra vars
openshift_version: "4.21"
force_refresh: true
```

Or manually refresh cache on kvm-host:
```bash
ssh kvm-host
sudo rm -rf /var/cache/oc-mirror/catalogs/*
ansible-playbook playbooks/validate-operator-selection.yml \
  -e "force_refresh=true" \
  -e "openshift_version=4.21"
```

---

### Issue 2: Node 2 Fails - "oc-mirror not found"

**Error**:
```
❌ ERROR: oc-mirror binary not found at /usr/local/bin/oc-mirror
```

**Cause**: Execution environment missing oc-mirror

**Solution**: Verify execution environment has oc-mirror:
```bash
# Via AAP API
curl -sk -u admin:<password> \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/execution_environments/" | \
  jq -r '.results[] | select(.name=="OCP4 Custom EE with oc-mirror")'

# Should show image with oc-mirror installed
```

---

### Issue 3: Node 3 Fails - "Registry authentication failed"

**Error**:
```
Error: running /usr/bin/newuidmap: Permission denied
```

**Cause**: Rootless podman authentication issue in AAP EE (known limitation)

**Solution**: This is non-blocking - oc-mirror authenticates via pull-secret file. Check actual mirror results:
```bash
ssh kvm-host
ls -lh /data/ocp-mirror/oc-mirror-workspace/

# If workspace has images, authentication worked
```

---

## Maintenance

### Cache Refresh Policy

**Default TTL**: 24 hours

**Manual Refresh**:
```bash
# Option 1: Via workflow extra vars
force_refresh: true

# Option 2: CLI on kvm-host
sudo rm -rf /var/cache/oc-mirror/catalogs/*
```

**When to Refresh**:
- Before major version upgrades (4.21 → 4.22)
- When new operators released
- Monthly as best practice

### Monitoring

**Metrics to Track**:
- Validation node success rate (should be >95%)
- Average validation duration (should be <10 sec)
- Cache hit rate (should be >90%)
- Bandwidth savings (should be ~99.9% for validation)

**Query via AAP API**:
```bash
# Get validation node statistics
curl -sk -u admin:<password> \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/job_templates/<validate_template_id>/jobs/" | \
  jq '[.results[] | {status: .status, duration: .elapsed}]'
```

---

## Benefits Summary

### Time Savings

| Scenario | Old Workflow | New Workflow | Improvement |
|----------|-------------|--------------|-------------|
| Invalid operator detection | 10-30 min | <5 sec | **200-360x faster** |
| Valid config (no change) | 40 min | 40 min | Same |
| Trial-and-error config tuning | Hours | Minutes | **10-20x faster** |

### Bandwidth Savings

| Operation | Old Workflow | New Workflow | Savings |
|-----------|-------------|--------------|---------|
| Validation (invalid config) | 5-10 GB | 73 KB | **99.999%** |
| Full mirror (valid config) | 50-100 GB | 50-100 GB | 0% (same) |

### User Experience

| Aspect | Old Workflow | New Workflow |
|--------|-------------|--------------|
| Error messages | ❌ Cryptic | ✅ Clear with suggestions |
| Failure detection | ❌ Late (10+ min) | ✅ Fast (<5 sec) |
| Fix guidance | ❌ None | ✅ Actionable suggestions |
| Bandwidth waste | ❌ High | ✅ Minimal |

---

## Related Documentation

- [ADR-0034: Operator Catalog Validation Framework](adrs/adr-0034-operator-catalog-validation-framework.md)
- [ADR-0032: AAP Workflow Orchestration](adrs/adr-0032-aap-workflow-orchestration.md)
- [ADR-0033: Workflow Validation Framework](adrs/adr-0033-workflow-validation-framework.md)
- [Operator Validation Quick Start](OPERATOR_VALIDATION_QUICKSTART.md)
- [Operator Validation Test Results](OPERATOR_VALIDATION_TEST_RESULTS.md)
- [AAP Deployment Guide](AAP_DEPLOYMENT_GUIDE.md)

---

## Next Steps

1. ✅ **Deploy workflow to AAP**: Run configure-oc-mirror-workflow.yml
2. ⏳ **Test with storage operators**: Validate happy path
3. ⏳ **Test with invalid config**: Verify error detection
4. ⏳ **Monitor cache performance**: Track hit rate and staleness
5. ⏳ **Train team**: Share quick start guide with operators

---

## Support

For issues or questions:
1. Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Review test results in [OPERATOR_VALIDATION_TEST_RESULTS.md](OPERATOR_VALIDATION_TEST_RESULTS.md)
3. Open GitHub issue with workflow job ID
