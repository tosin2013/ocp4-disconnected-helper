# AAP Workflow Configuration Playbooks

This directory contains playbooks for configuring AAP 2.6 workflows and job templates.

## Workflows

### Workflow 2: OpenShift Image Mirroring

**Complete workflow with 4 nodes:**

```
Node 1: Validate Operator Selection
  ↓ (success)
Node 2: Download Images to Disk
  ↓ (success)
Node 3: Push Images to Registry
  ↓ (success)
Node 4: Configure Cluster Catalog ⭐ NEW
  ↓ (success)
Workflow Complete
```

---

## Configuration Playbooks

### `configure-workflow-2-node-4.yml`

**Purpose**: Add Node 4 (Configure Operator Catalog) to Workflow 2

**What it creates**:
- Job Template: "Job: Configure Operator Catalog"
- Workflow Node: Links Node 3 → Node 4
- Survey: Kubeconfig path, registry URL, OCP version

**Usage**:
```bash
ansible-playbook playbooks/aap-configuration/configure-workflow-2-node-4.yml \
  -e controller_host=https://aap.sandbox3377.opentlc.com \
  -e controller_username=admin \
  -e controller_password='<YOUR-AAP-GATEWAY-PASSWORD>' \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Prerequisites**:
- ✅ AAP 2.6 deployed and accessible
- ✅ Workflow 2 already configured (Nodes 1-3 exist)
- ✅ OpenShift kubeconfig credential uploaded to AAP
- ✅ Project "ocp4-disconnected-helper" synced in AAP

---

## Survey Parameters

### Node 4 Survey

When launching Workflow 2 with Node 4, you'll be prompted for:

| Field | Description | Example |
|-------|-------------|---------|
| **Cluster Kubeconfig Path** | Absolute path to cluster kubeconfig | `/root/openshift-install/auth/kubeconfig` |
| **Registry URL** | Mirrored registry URL (no https://) | `registry.ocp4.sandbox3377.opentlc.com:8443` |
| **OpenShift Version** | OpenShift version (matches catalog tag) | `4.21` |
| **Cluster Name** | Cluster name for identification (optional) | `ocp4` |

---

## Workflow Execution Example

**Step 1: Launch Workflow 2 from AAP Web UI**

**Step 2: Fill Survey (Nodes 1-3 - Operator Selection)**
- Operator Preset: `storage-operators`
- Target Registry: `registry.ocp4.sandbox3377.opentlc.com:8443`

**Step 3: Fill Survey (Node 4 - Cluster Configuration)**
- Cluster Kubeconfig: `/root/openshift-install/auth/kubeconfig`
- Registry URL: `registry.ocp4.sandbox3377.opentlc.com:8443`
- OpenShift Version: `4.21`

**Step 4: Monitor Execution** (60-90 minutes total)
- ✅ Node 1: Validation (5 seconds)
- ✅ Node 2: Download (20-40 minutes)
- ✅ Node 3: Push to Registry (15-30 minutes)
- ✅ Node 4: Configure Cluster (15-25 minutes)

**Result**:
- Operators mirrored to registry
- Cluster configured to use mirrored catalog
- Operators appear in OperatorHub
- No internet needed for operator installation!

---

## Credentials Required

### OpenShift Kubeconfig Credential

**Create in AAP**:
1. Navigate to **Resources → Credentials**
2. Click **Add**
3. Fill:
   - **Name**: `OpenShift Kubeconfig`
   - **Credential Type**: `OpenShift or Kubernetes API Bearer Token`
   - **OpenShift or Kubernetes API Endpoint**: `https://api.ocp4.example.com:6443`
   - **API Authentication Bearer Token**: (paste kubeconfig token)
   - **OR Upload kubeconfig file**
4. Click **Save**

**Alternative**: File-based kubeconfig
- Upload kubeconfig to AAP execution environment
- Use path `/runner/project/kubeconfig` in survey

---

## Troubleshooting

### Issue: Node 4 Fails - "Kubeconfig not found"

**Cause**: Kubeconfig path in survey is incorrect or not accessible by execution environment

**Fix**:
```bash
# Option 1: Use AAP credential instead of file path
# Configure OpenShift Kubeconfig credential in AAP

# Option 2: Copy kubeconfig to project directory
cp /root/openshift-install/auth/kubeconfig \
   /opt/ansible-automation-platform/projects/ocp4-disconnected-helper/
# Then use: /runner/project/kubeconfig in survey
```

---

### Issue: Node 4 Fails - "Cannot connect to cluster"

**Cause**: AAP execution environment cannot reach OpenShift API

**Check**:
```bash
# Test from AAP node
curl -k https://api.ocp4.example.com:6443/version
```

**Fix**:
- Ensure firewall allows AAP → OpenShift API (port 6443)
- If using internal DNS, ensure AAP can resolve cluster FQDN
- Add route from AAP network to OpenShift cluster network

---

## Related Documentation

- [Configure Operator Catalog for Disconnected](../../docs/how-to/configure-operator-catalog-for-disconnected.md)
- [End-to-End Disconnected Deployment](../../docs/tutorials/end-to-end-disconnected-deployment.md)
- [AAP Workflow Catalog](../../docs/AAP_WORKFLOW_CATALOG.md)
