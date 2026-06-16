# AAP Operator Preset Survey Guide

**Version**: 1.3  
**Created**: 2026-06-16  
**Purpose**: User guide for AAP dropdown operator preset selection

---

## Overview

The AAP workflow for "Disconnected OpenShift Image Mirroring" includes an interactive survey that allows you to select operator presets from a dropdown menu instead of manually editing extra_vars files.

**Benefits**:
- ✅ No manual extra_vars editing required
- ✅ Browse all 12 curated presets in a dropdown
- ✅ See preset descriptions and size estimates
- ✅ Reduce configuration errors

---

## Quick Start

### 1. Access AAP Workflow

1. Login to AAP Web UI: https://aap.sandbox3377.opentlc.com
2. Navigate to: **Resources → Templates → Workflows**
3. Find: **"Disconnected OpenShift Image Mirroring"**
4. Click: **Launch** button

### 2. Survey Form

You'll see a survey with 4 questions:

#### Question 1: Operator Preset
**Type**: Dropdown (Multiple Choice)

**Options**:

**Atomic Presets** (Single Focus Area):
- `storage-operators` - Storage (ODF, LVMS, Local) — ~15 GB
- `rhacm-operators` - Multi-cluster management — ~20 GB
- `openshift-ai-operators` - AI/ML with GPU — ~35 GB
- `virtualization-operators` - VMs + containers — ~25 GB
- `service-mesh-operators` - Istio, Kiali, tracing — ~18 GB
- `observability-operators` - Logging, Loki, Tempo — ~22 GB
- `security-operators` - Compliance, FIM, Quay — ~20 GB
- `networking-operators` - MetalLB, NMState — ~16 GB

**Combination Presets** (Multi-Capability Bundles):
- `full-platform` - Storage + Observability + Security + Networking — ~70 GB
- `enterprise-ready` - RHACM + Storage + Security + Observability — ~65 GB
- `developer-stack` - Service Mesh + AI + Observability + GitOps — ~60 GB
- `vm-platform` - Virtualization + Storage + Networking + Security — ~55 GB

**Custom**:
- `custom` - Provide your own extra_vars file path

**Default**: `storage-operators`

---

#### Question 2: Custom Preset Path
**Type**: Text  
**Required**: No (only if you selected "custom" above)

Provide the full path to your custom extra_vars file:
```
@extra_vars/operators/my-custom-operators.yml
```

**Leave blank** if you selected a curated preset.

---

#### Question 3: Target Registry
**Type**: Text  
**Required**: Yes

Container registry URL where images will be pushed:
```
registry.ocp4.sandbox3377.opentlc.com:8443
```

**Default**: `registry.ocp4.sandbox3377.opentlc.com:8443`

---

#### Question 4: Target Namespace
**Type**: Text  
**Required**: Yes

Registry namespace for mirrored images:
```
openshift4
```

**Default**: `openshift4`

---

### 3. Submit and Monitor

1. Click **Next** to review your selections
2. Click **Launch** to start the workflow
3. Monitor 3-node execution:
   - **Node 1**: Validate Operator Selection (~5 seconds)
   - **Node 2**: Download OpenShift Images (5-60 minutes)
   - **Node 3**: Mirror Images to Registry (10-90 minutes)

---

## Common Workflows

### Scenario 1: Mirror Storage Operators (Quick Test)
**Use Case**: Test the workflow with a small, fast operator bundle

**Steps**:
1. Launch workflow
2. Select: `storage-operators` (default)
3. Provide registry URL: `registry.example.com:8443`
4. Namespace: `openshift4` (default)
5. Launch

**Expected Time**: ~20-30 minutes total

---

### Scenario 2: Full Enterprise Platform
**Use Case**: Mirror all foundational operators for a new deployment

**Steps**:
1. Launch workflow
2. Select: `full-platform`
3. Provide registry URL
4. Launch

**Expected Time**: ~2-3 hours (70 GB download)

**Note**: Ensure adequate disk space (210 GB minimum = 70 GB × 3)

---

### Scenario 3: Multi-Cluster Hub with RHACM
**Use Case**: Set up a hub cluster to manage multiple spoke clusters

**Steps**:
1. Launch workflow
2. Select: `enterprise-ready`
3. Provide registry URL
4. Launch

**Expected Time**: ~1.5-2 hours (65 GB download)

**Post-Deployment**: Install RHACM operator on hub cluster and configure policies

---

### Scenario 4: Custom Operator Selection
**Use Case**: You have a custom operator list not covered by presets

**Steps**:
1. Create custom extra_vars file:
   ```bash
   cp extra_vars/operators/storage-operators.yml \
      extra_vars/operators/my-custom.yml
   # Edit my-custom.yml with your operators
   ```

2. Validate custom preset:
   ```bash
   ansible-playbook playbooks/validate-operator-selection.yml \
     -e @extra_vars/operators/my-custom.yml
   ```

3. Launch workflow:
   - Select: `custom`
   - Custom path: `@extra_vars/operators/my-custom.yml`
   - Provide registry URL
   - Launch

---

## Preset Details

### Atomic Presets

#### Storage Operators (~15 GB)
**Operators**: ODF, LVMS, Local Storage, Portworx  
**Use Case**: Persistent storage for stateful workloads  
**Requirements**: 32 GB RAM per worker

#### RHACM Operators (~20 GB)
**Operators**: Advanced Cluster Management, Multi-cluster Engine, Submariner, GitOps  
**Use Case**: Hub-spoke multi-cluster management  
**Requirements**: 64 GB RAM for hub cluster

#### OpenShift AI (~35 GB)
**Operators**: RHODS, Authorino, Service Mesh, Serverless, GPU  
**Use Case**: AI/ML model training and serving  
**Requirements**: NVIDIA GPUs, 64 GB RAM, S3 storage

#### Virtualization (~25 GB)
**Operators**: KubeVirt, ODF, NMState, MetalLB  
**Use Case**: VMs + containers unified platform  
**Requirements**: VT-x/AMD-V, 64 GB RAM per worker

#### Service Mesh (~18 GB)
**Operators**: Istio, Kiali, Tempo  
**Use Case**: Microservices traffic management  
**Requirements**: 16 GB RAM per worker

#### Observability (~22 GB)
**Operators**: Logging, Loki, Tempo, Cluster Observability, GitOps  
**Use Case**: Centralized logging and tracing  
**Requirements**: 100 GB+ persistent storage for logs

#### Security & Compliance (~20 GB)
**Operators**: Compliance, FIM, Quay, Quay Bridge  
**Use Case**: Security hardening and compliance scanning  
**Requirements**: 500 GB+ storage for Quay

#### Advanced Networking (~16 GB)
**Operators**: MetalLB, NMState, Submariner, Service Mesh  
**Use Case**: Bare metal load balancing, multi-cluster networking  
**Requirements**: BGP router (optional for MetalLB BGP mode)

---

### Combination Presets

#### Full Platform (~70 GB)
**Combines**: Storage + Observability + Security + Networking  
**Operators**: 20 total  
**Use Case**: Complete enterprise platform with all foundational capabilities  
**Requirements**: 64 GB RAM per worker, 500 GB+ storage

**Bandwidth Savings**: ~40% vs mirroring 4 atomic presets separately (deduplication of shared dependencies)

---

#### Enterprise Ready (~65 GB)
**Combines**: RHACM + Storage + Security + Observability  
**Operators**: 16 total  
**Use Case**: Hub cluster managing multiple spoke clusters with governance  
**Requirements**: Hub: 64 GB RAM, 500 GB storage; Spokes: OpenShift 4.10+

---

#### Developer Stack (~60 GB)
**Combines**: Service Mesh + Observability + AI + GitOps  
**Operators**: 13 total  
**Use Case**: Microservices development with AI/ML capabilities  
**Requirements**: 48 GB RAM per worker, NVIDIA GPUs (optional), S3 storage

---

#### VM Platform (~55 GB)
**Combines**: Virtualization + Storage + Networking + Security  
**Operators**: 13 total  
**Use Case**: VMs + containers unified platform (VMware replacement)  
**Requirements**: VT-x/AMD-V, 64 GB RAM per worker, 500 GB+ storage

---

## Troubleshooting

### Survey Not Appearing

**Symptoms**: Workflow launches without survey prompt

**Cause**: Survey not enabled on workflow template

**Fix**:
```bash
# Re-run configuration playbook
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/aap-configuration/configure-oc-mirror-workflow.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

---

### Validation Node Fails with "Preset not found"

**Symptoms**: Node 1 fails with "Preset file not found"

**Cause**: Custom preset path is incorrect or file doesn't exist

**Fix**:
1. Verify custom file exists:
   ```bash
   ls -la extra_vars/operators/my-custom.yml
   ```

2. Use correct path in survey:
   ```
   @extra_vars/operators/my-custom.yml
   ```

---

### Workflow Fails - Insufficient Disk Space

**Symptoms**: Node 2 (Download) fails with "No space left on device"

**Cause**: Workspace directory `/data/ocp-mirror/` is full

**Fix**:
1. Check disk space:
   ```bash
   df -h /data
   ```

2. Clean old workspaces:
   ```bash
   sudo rm -rf /data/ocp-mirror/oc-mirror-workspace/
   ```

3. Allocate 3x the preset size:
   - `full-platform` (~70 GB) requires ~210 GB free space
   - `enterprise-ready` (~65 GB) requires ~195 GB free space

---

## Best Practices

### 1. Start Small
Test with `storage-operators` preset first (~15 GB) before attempting large combination presets.

### 2. Validate Custom Presets
Always run validation before mirroring custom presets:
```bash
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/my-custom.yml
```

### 3. Monitor Disk Space
Check `/data` disk space before launching large presets:
```bash
df -h /data
# Ensure 3x the preset size is available
```

### 4. Use Combination Presets for Multi-Capability Deployments
Combination presets save bandwidth (30-40%) vs mirroring atomic presets separately due to shared dependency deduplication.

### 5. Review Preset Documentation
Read `extra_vars/operators/README.md` for detailed operator lists and requirements before selecting.

---

## Related Documentation

- **Operator Presets README**: `extra_vars/operators/README.md`
- **AAP Workflow Deployment**: `docs/AAP_WORKFLOW_DEPLOYMENT_GUIDE.md`
- **Operator Validation Framework**: `docs/adrs/adr-0034-operator-catalog-validation-framework.md`
- **AAP Orchestration Strategy**: `docs/adrs/adr-0032-aap-workflow-orchestration-strategy.md`

---

**Created**: 2026-06-16  
**Version**: 1.3  
**Last Updated**: 2026-06-16
