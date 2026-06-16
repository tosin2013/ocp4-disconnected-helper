# How to Deploy Workflow 2: OpenShift Image Mirroring

Deploy the image mirroring workflow to AAP and execute it to mirror OpenShift images.

---

## Prerequisites

- ✅ **Workflow 1 deployed and completed** - Registry infrastructure must exist
- ✅ **AAP 2.6 operational** - Web UI accessible at `https://aap.example.com`
- ✅ **Credentials configured** in AAP:
  - Red Hat Registry Credentials (for registry.redhat.io)
  - Target Registry Credentials (for your mirror registry)
- ✅ **Project synced** - `ocp4-disconnected-helper` repository imported

---

## Step 1: Deploy Workflow 2 Configuration

### Via Ansible Playbook (Recommended)

```bash
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/aap-configuration/configure-mirroring-workflow.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**What this does**:
1. Creates 4 job templates (Prerequisites, Download, Push, Verify)
2. Links templates into workflow with prerequisite validation
3. Configures survey for operator preset and registry selection
4. Sets up credential prompts

**Expected output**:
```
TASK [Create workflow - Workflow 2: Image Mirroring] *************
changed: [localhost]

PLAY RECAP ********************************************************
localhost                  : ok=5    changed=5
```

### Via AAP Web UI (Manual)

If playbook deployment fails, configure manually:

1. Navigate to **Resources → Templates → Add → Add workflow template**
2. Set:
   - **Name**: `Workflow 2: OpenShift Image Mirroring`
   - **Organization**: Default
   - **Inventory**: `ocp4-disconnected-helper-inventory`
3. Click **Save**
4. Add nodes:
   - Node 1: `Verify Prerequisites` (playbook: `playbooks/verify-registry-ready.yml`)
   - Node 2: `Download Images` (playbook: `playbooks/download-to-disk-v2.yml`)
   - Node 3: `Push to Registry` (playbook: `playbooks/push-to-registry-v2.yml`)
   - Node 4: `Verify Mirror` (playbook: `playbooks/verify-mirror.yml`)
5. Link nodes: 1 → 2 → 3 → 4 (success path only)
6. Configure survey (see [Workflow Survey Parameters](../reference/workflow-survey-parameters.md))

---

## Step 2: Execute Workflow 2

### Via AAP Web UI

1. Navigate to **Resources → Templates**
2. Find **Workflow 2: OpenShift Image Mirroring**
3. Click **Launch** (rocket icon)
4. Fill survey:
   - **Operator Preset**: Select from dropdown (default: `storage-operators`)
   - **Target Registry**: Enter registry URL (example: `registry.example.com:8443`)
5. **Select credentials** when prompted:
   - Red Hat Registry Credentials (for image download)
   - Target Registry Credentials (for image push)
6. Click **Next** → **Launch**

**Execution time**: 10-60 minutes (depends on operator count and network speed)

### Via API (Automation)

```bash
# Get workflow template ID
WORKFLOW_ID=$(curl -sk -u admin:"$GATEWAY_PASSWORD" \
  "https://aap.example.com/api/controller/v2/workflow_job_templates/" | \
  jq -r '.results[] | select(.name=="Workflow 2: OpenShift Image Mirroring") | .id')

# Launch workflow
curl -sk -u admin:"$GATEWAY_PASSWORD" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "extra_vars": {
      "operator_preset_file": "storage-operators",
      "target_registry": "registry.example.com:8443"
    }
  }' \
  "https://aap.example.com/api/controller/v2/workflow_job_templates/$WORKFLOW_ID/launch/" | \
  jq -r '.url'
```

### Via Ansible Playbook (Direct Execution)

Skip AAP and run playbooks directly:

```bash
# Step 1: Verify prerequisites
ansible-playbook playbooks/verify-registry-ready.yml \
  -e target_registry=registry.example.com:8443

# Step 2: Download images
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/operators/storage-operators.yml

# Step 3: Push to registry
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e target_registry=registry.example.com:8443

# Step 4: Verify mirror
ansible-playbook playbooks/verify-mirror.yml \
  -e target_registry=registry.example.com:8443
```

---

## Step 3: Monitor Execution

### Via AAP Web UI

1. Navigate to **Views → Jobs**
2. Click on latest **Workflow 2: OpenShift Image Mirroring** job
3. Watch progress through workflow nodes
4. Expand each node to see playbook output

**Progress indicators**:
- ✅ Green check = Step completed successfully
- 🔄 Blue spinner = Step running
- ❌ Red X = Step failed

### Via CLI

```bash
# Get latest job ID
JOB_ID=$(curl -sk -u admin:"$CONTROLLER_PASSWORD" \
  "https://aap.example.com/api/controller/v2/workflow_jobs/?order_by=-id" | \
  jq -r '.results[0].id')

# Watch job status
watch -n 5 "curl -sk -u admin:$CONTROLLER_PASSWORD \
  https://aap.example.com/api/controller/v2/workflow_jobs/$JOB_ID/ | \
  jq -r '.status'"
```

---

## Step 4: Verify Results

### Check Image Count

```bash
# SSH to registry VM
ssh admin@registry.example.com

# Count mirrored images
sudo podman exec -it quay-app \
  curl -sk https://localhost:8443/v2/_catalog | \
  jq '.repositories | length'

# Expected: 200+ repositories for storage-operators preset
```

### Extract Pull Secret

After successful mirroring, generate pull secret for disconnected installation:

```bash
ansible-playbook playbooks/extract-pull-secret.yml \
  -e target_registry=registry.example.com:8443 \
  -e output_file=/tmp/disconnected-pull-secret.json
```

**Output**: `/tmp/disconnected-pull-secret.json` - Use this for OpenShift installation

### Extract ICSP

Generate ImageContentSourcePolicy for cluster configuration:

```bash
ansible-playbook playbooks/extract-icsp.yml \
  -e target_registry=registry.example.com:8443 \
  -e output_file=/tmp/imageContentSourcePolicy.yaml
```

**Output**: `/tmp/imageContentSourcePolicy.yaml` - Apply to cluster after installation

---

## Troubleshooting

### Node 1 Fails: "Prerequisites not met"

**Cause**: Registry not accessible or not configured correctly

**Solution**:
1. Verify registry is running: `ssh admin@registry.example.com "systemctl status quay-pod"`
2. Test registry connectivity: `curl -k https://registry.example.com:8443/health/instance`
3. Run Workflow 1 if registry not deployed

### Node 2 Fails: "Operator not found in catalog"

**Cause**: Typo in operator name or operator doesn't exist

**Solution**:
1. Run operator validation: 
   ```bash
   ansible-playbook playbooks/validate-operator-selection.yml \
     -e @extra_vars/operators/storage-operators.yml
   ```
2. Use curated presets (guaranteed valid): `extra_vars/operators/*.yml`
3. Check operator name with discovery tool: `./scripts/discover-operators.sh --search <name>`

### Node 2 Fails: "Port 55000 already bound" (<5 seconds)

**Cause**: Stale async cache

**Solution**: See [Resolve: oc-mirror Async Cache](resolve-oc-mirror-async-cache.md)

### Node 3 Fails: "Authentication failed"

**Cause**: Wrong registry credentials

**Solution**:
1. Verify credentials in AAP: **Resources → Credentials → Target Registry Credentials**
2. Test authentication:
   ```bash
   echo "$PASSWORD" | podman login --username "$USERNAME" \
     --password-stdin registry.example.com:8443
   ```
3. Re-create credential in AAP with correct username/password

### Node 4 Fails: "Expected images not found"

**Cause**: Push partially failed or network interruption

**Solution**:
1. Re-run Node 3 (Push to Registry) - it's idempotent
2. Check registry logs: `ssh admin@registry.example.com "journalctl -u quay-pod -n 100"`
3. Verify disk space: `ssh admin@registry.example.com "df -h /opt/mirror-registry"`

---

## Operator Presets

**Available Curated Presets** (validated, production-ready):

1. **storage-operators** (8 operators) - Persistent storage (ODF, local-storage, NFS)
2. **networking-operators** (6 operators) - Advanced networking (Multus, SR-IOV, MetalLB)
3. **observability-operators** (7 operators) - Monitoring (Prometheus, Grafana, Loki)
4. **security-operators** (5 operators) - Security (ACS, Compliance, Cert Manager)
5. **virtualization-operators** (4 operators) - OpenShift Virtualization (CNV)
6. **service-mesh-operators** (6 operators) - Service mesh (Istio, Kiali, Jaeger)
7. **openshift-ai-operators** (9 operators) - AI/ML workloads (RHOAI, ODH)
8. **rhacm-operators** (5 operators) - Multi-cluster management (RHACM)

**Preset files**: `extra_vars/operators/<preset-name>.yml`

**Custom presets**: See [How to Add Custom Operators](add-custom-operators.md)

---

## Next Steps

After successful image mirroring:

1. **Extract pull secret and ICSP** (see Step 4 above)
2. **Deploy OpenShift cluster** using disconnected installation
3. **Configure ImageContentSourcePolicy** on cluster
4. **Install operators** from mirrored catalog

---

## Related Documentation

- [Troubleshoot Workflow Failures](troubleshoot-workflow-failures.md)
- [Workflow Survey Parameters](../reference/workflow-survey-parameters.md)
- [Operator Validation Framework](../explanations/operator-validation-framework.md)
- [Your First OpenShift Image Mirror](../tutorials/your-first-openshift-image-mirror.md)
