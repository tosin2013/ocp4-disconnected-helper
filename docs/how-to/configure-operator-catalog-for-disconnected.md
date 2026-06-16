---
layout: default
title: Configure Operator Catalog for Disconnected Cluster
parent: How-To Guides
nav_order: 11
---

# Configure Operator Catalog for Disconnected OpenShift Cluster

**Goal**: Connect your OpenShift cluster to mirrored operator images so OperatorHub pulls from your disconnected registry instead of the internet.

**Time**: 15-30 minutes (includes waiting for node reboots)

**Prerequisites**:
- ✅ OpenShift 4.21+ cluster deployed and accessible
- ✅ Operators mirrored to registry (see [Your First OpenShift Image Mirror](../tutorials/your-first-openshift-image-mirror.md))
- ✅ `KUBECONFIG` environment variable set
- ✅ Ansible 2.16+ with `kubernetes.core` collection installed

---

## What This Does

This playbook automates the 3-step process to configure your cluster for disconnected operator installation:

1. **Apply ImageContentSourcePolicy (ICSP)** — Redirects image pulls from `registry.redhat.io` → `registry.example.com:8443`
2. **Wait for MachineConfigPool rollout** — Nodes reboot sequentially to apply new container runtime config (5-15 minutes)
3. **Create CatalogSource** — Points OperatorHub to your mirrored operator catalog

**Result**: Operators appear in OperatorHub and pull images from your registry (no internet needed).

---

## Quick Start

### Step 1: Set Environment Variables

```bash
export KUBECONFIG=/root/openshift-install/auth/kubeconfig
export REGISTRY_URL=registry.example.com:8443
export OCP_VERSION=4.21
```

### Step 2: Run Playbook

```bash
ansible-playbook playbooks/configure-operator-catalog.yml \
  -e kubeconfig=$KUBECONFIG \
  -e registry_url=$REGISTRY_URL \
  -e ocp_version=$OCP_VERSION
```

### Step 3: Verify in OpenShift Console

1. Login to OpenShift Console
2. Navigate to **Operators → OperatorHub**
3. Search for "storage" (or any operator you mirrored)
4. Click on operator → **Source: Red Hat Operators (Mirrored)**

**Expected Output**:
```
✅ Operator catalog configuration complete!

Next steps:
  1. Login to OpenShift Console
  2. Navigate to Operators → OperatorHub
  3. Search for operators (storage, networking, observability)
  4. Install operators (images will pull from registry.example.com:8443)

No internet connection needed for operator installation!
```

---

## Detailed Steps

### Step 1: Validate Prerequisites

**Check cluster connectivity**:
```bash
oc whoami --show-server
# Expected: https://api.ocp4.example.com:6443
```

**Verify registry has mirrored operators**:
```bash
curl -k https://registry.example.com:8443/v2/_catalog | jq '.repositories | length'
# Expected: 200+ repositories
```

**Install Ansible kubernetes.core collection** (if not already installed):
```bash
ansible-galaxy collection install kubernetes.core
```

---

### Step 2: Configure Playbook Variables

**Option A: Environment Variables** (recommended for CLI)
```bash
export KUBECONFIG=/root/openshift-install/auth/kubeconfig
export REGISTRY_URL=registry.example.com:8443
export OCP_VERSION=4.21

ansible-playbook playbooks/configure-operator-catalog.yml \
  -e kubeconfig=$KUBECONFIG \
  -e registry_url=$REGISTRY_URL \
  -e ocp_version=$OCP_VERSION
```

**Option B: Extra Vars File** (recommended for automation)
```bash
# Create extra_vars/operator-catalog.yml
cat > extra_vars/operator-catalog.yml <<EOF
---
kubeconfig: /root/openshift-install/auth/kubeconfig
registry_url: registry.example.com:8443
ocp_version: "4.21"
catalog_name: redhat-operator-index
validate_catalog: true
EOF

# Run playbook
ansible-playbook playbooks/configure-operator-catalog.yml \
  -e @extra_vars/operator-catalog.yml
```

---

### Step 3: Monitor Playbook Execution

**Phase 1: ICSP Creation** (5 seconds)
```
TASK [Apply ImageContentSourcePolicy for operators]
ok: [localhost]

⚠️  MachineConfigPool rollout will begin (nodes will reboot sequentially)
```

**Phase 2: MachineConfigPool Rollout** (10-20 minutes)
```
TASK [Monitor master MachineConfigPool]
TASK [Monitor worker MachineConfigPool]

✓ Master nodes: 3/3 ready
✓ Worker nodes: 2/2 ready
MachineConfigPool rollout complete!
```

**What's happening**:
- Machine Config Operator applies ICSP to all nodes
- Master nodes reboot one-by-one (update, reboot, ready)
- Worker nodes reboot one-by-one after masters complete
- Container runtime (CRI-O) configuration updated with registry mirrors

**Phase 3: CatalogSource Creation** (1-2 minutes)
```
TASK [Create CatalogSource for mirrored operators]
ok: [localhost]

TASK [Wait for CatalogSource to become READY]
✓ CatalogSource 'redhat-operator-index' is READY
✓ Catalog pod 'redhat-operator-index-xxxxx' is Running
✓ 32 operators available from mirrored catalog
```

---

### Step 4: Verify Configuration

**Check ImageContentSourcePolicy**:
```bash
oc get imagecontentsourcepolicy
# Expected:
# NAME                      AGE
# operator-mirror-config    5m
```

**Check MachineConfigPool status**:
```bash
oc get mcp
# Expected:
# NAME     CONFIG    UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT
# master   rendered  True      False      False      3              3
# worker   rendered  True      False      False      2              2
```

**Check CatalogSource**:
```bash
oc get catalogsource -n openshift-marketplace
# Expected:
# NAME                      DISPLAY                          TYPE   PUBLISHER   AGE
# redhat-operator-index     Red Hat Operators (Mirrored)     grpc   Red Hat     2m
```

**Check catalog pod**:
```bash
oc get pods -n openshift-marketplace | grep redhat-operator
# Expected:
# redhat-operator-index-xxxxx   1/1   Running   0   2m
```

**List available operators**:
```bash
oc get packagemanifests -n openshift-marketplace | grep -v "redhat-operators"

# Example output (if you mirrored storage-operators):
# local-storage-operator
# lvms-operator
# odf-operator
```

---

## What Operators Are Available?

The operators available depend on what you mirrored in **Workflow 2**:

| Mirrored Preset | Available Operators |
|-----------------|---------------------|
| **storage-operators** | ODF, LVMS, Local Storage, Portworx |
| **networking-operators** | MetalLB, NMState, SR-IOV, Submariner |
| **observability-operators** | Cluster Logging, Loki, Tempo, Cluster Observability |
| **security-operators** | Compliance, File Integrity, Quay, Quay Bridge |
| **rhacm-operators** | Advanced Cluster Management, Multi-cluster Engine, GitOps |
| **virtualization-operators** | KubeVirt, ODF, NMState, MetalLB |
| **service-mesh-operators** | Istio, Kiali, Tempo, Distributed Tracing |
| **openshift-ai-operators** | RHODS, Authorino, Service Mesh, Serverless, GPU |

**See full list**: [Operator Preset Catalog](../reference/operator-preset-catalog.md)

---

## Installing an Operator from OperatorHub

**Via Web Console**:
1. Navigate to **Operators → OperatorHub**
2. Search for operator (e.g., "local storage")
3. Click operator card
4. Verify **Source: Red Hat Operators (Mirrored)**
5. Click **Install**
6. Configure namespace and approval strategy
7. Click **Install** again

**Via CLI**:
```bash
# Example: Install Local Storage Operator
oc apply -f - <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: local-storage-operator
  namespace: openshift-local-storage
spec:
  channel: stable
  name: local-storage-operator
  source: redhat-operator-index
  sourceNamespace: openshift-marketplace
EOF
```

**Verify operator installation**:
```bash
oc get csv -n openshift-local-storage
# Expected:
# NAME                            DISPLAY              VERSION   REPLACES   PHASE
# local-storage-operator.v4.21.0  Local Storage        4.21.0               Succeeded
```

---

## Multi-Cluster Usage

**For hub-spoke architectures**, run this playbook once per spoke cluster:

```bash
# Configure hub cluster
export KUBECONFIG=/root/hub-kubeconfig
ansible-playbook playbooks/configure-operator-catalog.yml \
  -e registry_url=registry.hub.example.com:8443

# Configure spoke cluster 1
export KUBECONFIG=/root/spoke1-kubeconfig
ansible-playbook playbooks/configure-operator-catalog.yml \
  -e registry_url=registry.hub.example.com:8443

# Configure spoke cluster 2
export KUBECONFIG=/root/spoke2-kubeconfig
ansible-playbook playbooks/configure-operator-catalog.yml \
  -e registry_url=registry.hub.example.com:8443
```

**All spoke clusters** will pull operators from the hub registry.

---

## Troubleshooting

### Issue: ICSP Not Applied to Nodes

**Symptoms**: Nodes stuck in "Updating" state

**Check**:
```bash
oc get mcp
# If UPDATING=True for > 30 minutes, investigate:
oc describe mcp master
```

**Common causes**:
- Node SSH access issues
- Insufficient disk space on nodes
- Custom MachineConfig conflicts

**Fix**:
```bash
# Check node status
oc get nodes

# SSH to problematic node
oc debug node/<node-name>
chroot /host

# Check disk space
df -h /var
```

---

### Issue: CatalogSource Not READY

**Symptoms**: `oc get catalogsource` shows "TRANSIENT_FAILURE" or stuck in "CONNECTING"

**Check**:
```bash
oc get catalogsource -n openshift-marketplace redhat-operator-index -o yaml
# Look at status.connectionState.lastObservedState
```

**Common causes**:
- Registry unreachable from cluster
- Wrong registry URL in CatalogSource
- ICSP not applied (nodes not rebooted yet)

**Fix**:
```bash
# Test registry connectivity from cluster
oc debug node/worker-0
chroot /host
podman pull registry.example.com:8443/redhat/redhat-operator-index:v4.21

# If pull fails, check ICSP:
oc get imagecontentsourcepolicy operator-mirror-config -o yaml
```

---

### Issue: Operators Not Appearing in OperatorHub

**Symptoms**: OperatorHub is empty or only shows community operators

**Check**:
```bash
# List package manifests
oc get packagemanifests -n openshift-marketplace

# Check marketplace operator logs
oc logs -n openshift-marketplace -l app=marketplace-operator
```

**Fix**:
```bash
# Restart marketplace operator
oc delete pod -n openshift-marketplace -l app=marketplace-operator

# Force catalog refresh
oc delete catalogsource -n openshift-marketplace redhat-operator-index
ansible-playbook playbooks/configure-operator-catalog.yml -e registry_url=registry.example.com:8443
```

---

## Parameters Reference

| Parameter | Default | Description |
|-----------|---------|-------------|
| `kubeconfig` | `$KUBECONFIG` or `/root/openshift-install/auth/kubeconfig` | Path to kubeconfig file |
| `registry_url` | `registry.example.com:8443` | Disconnected registry URL (no `https://`) |
| `ocp_version` | `4.21` | OpenShift version (matches catalog index tag) |
| `catalog_name` | `redhat-operator-index` | CatalogSource name |
| `validate_catalog` | `true` | Validate catalog becomes READY |
| `wait_timeout` | `3600` | Maximum seconds to wait for MachineConfigPool rollout |

---

## Related Documentation

- [Your First OpenShift Image Mirror](../tutorials/your-first-openshift-image-mirror.md) — Mirror operators before running this
- [Operator Preset Catalog](../reference/operator-preset-catalog.md) — Complete list of available operators
- [End-to-End Disconnected Deployment](../tutorials/end-to-end-disconnected-deployment.md) — Full deployment tutorial
- [ADR-0034: Operator Validation Framework](../adrs/adr-0034-operator-catalog-validation-framework.md) — Operator validation architecture

---

**Created**: 2026-06-16  
**Playbook**: `playbooks/configure-operator-catalog.yml`  
**Templates**: `templates/operator-icsp.yaml.j2`, `templates/catalogsource.yaml.j2`
