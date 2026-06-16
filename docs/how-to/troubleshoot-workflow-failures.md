# How to Troubleshoot Workflow Failures

Quick diagnosis and resolution for common AAP workflow failures.

---

## Diagnose Workflow Failure

### Step 1: Check Workflow Job Status

```bash
# Get recent workflow jobs
curl -sk -u admin:"$GATEWAY_PASSWORD" \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/workflow_jobs/?order_by=-id" | \
  jq -r '.results[0:5] | .[] | "\(.id) - \(.name) - \(.status)"'
```

### Step 2: Get Failed Job Details

```bash
WORKFLOW_JOB_ID=<failed-job-id>

curl -sk -u admin:"$GATEWAY_PASSWORD" \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/workflow_jobs/$WORKFLOW_JOB_ID/" | \
  jq '{id, name, status, failed, workflow_nodes}'
```

### Step 3: Identify Failed Node

```bash
curl -sk -u admin:"$GATEWAY_PASSWORD" \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/workflow_jobs/$WORKFLOW_JOB_ID/workflow_nodes/" | \
  jq -r '.results[] | select(.failed == true) | {identifier, job_id, summary_fields}'
```

---

## Common Failure Patterns

### Failure: "Playbook not found for project"

**Symptom**:
```
Unable to create job_template Step X: {'playbook': ['Playbook not found for project.']}
```

**Cause**: AAP project cache is stale (Git changes not synced).

**Fix**:
```bash
# Get project ID
PROJECT_ID=$(curl -sk -u admin:"$GATEWAY_PASSWORD" \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/projects/" | \
  jq -r '.results[] | select(.name == "ocp4-disconnected-helper") | .id')

# Trigger project sync
curl -sk -u admin:"$GATEWAY_PASSWORD" -X POST \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/projects/$PROJECT_ID/update/"

# Wait for sync to complete (30-60 seconds)
watch -n 5 "curl -sk -u admin:\"$GATEWAY_PASSWORD\" \
  \"https://aap.sandbox3377.opentlc.com/api/controller/v2/project_updates/?project=$PROJECT_ID&order_by=-id\" | \
  jq -r '.results[0].status'"
```

**Verification**: Re-run workflow configuration playbook.

---

### Failure: "Prerequisites not met" (Workflow 2 Step 0)

**Symptom**:
```
FAILED! => {"msg": "Prerequisites not met: Registry not deployed. Run Workflow 1 first."}
```

**Cause**: Workflow 2 requires registry infrastructure from Workflow 1.

**Fix**: Run Workflow 1 before Workflow 2:

```bash
# Deploy Workflow 1 via Web UI
# Navigate to Templates → Workflows → "Workflow 1: Registry Infrastructure Deployment" → Launch

# Or via CLI
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/aap-configuration/configure-infrastructure-workflow.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Verification**: Check registry accessibility:
```bash
curl -k https://registry.example.com:8443/health/instance
```

---

### Failure: "Credential not found"

**Symptom**:
```
Request to /api/controller/v2/credentials/?name=XYZ+Credentials returned 0 items, expected 1
```

**Cause**: Referenced credential doesn't exist in AAP.

**Fix Option 1**: Create the credential in AAP Web UI
1. Navigate to **Resources → Credentials**
2. Click **Add**
3. Fill credential details
4. Save

**Fix Option 2**: Use `ask_credential_on_launch`
Update workflow configuration to prompt for credentials at launch instead of hardcoding.

---

### Failure: SSH connection timeout

**Symptom**:
```
UNREACHABLE! => {"msg": "Failed to connect to the host via ssh: ssh: connect to host 192.168.10.10 port 22: Connection timed out"}
```

**Cause**: Target VM not running or network unreachable.

**Fix**:
```bash
# Check VM is running
virsh list --all | grep <vm-name>

# If VM exists but stopped
virsh start <vm-name>

# If VM doesn't exist
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-<component>.yml
```

**Verification**:
```bash
ssh admin@192.168.10.10 "hostname"
```

---

## Advanced Debugging

### Enable Verbose Logging

For manual playbook execution:

```bash
ansible-playbook -vvv playbooks/<playbook>.yml
```

For AAP workflows, edit job template:
1. Navigate to **Templates → Job Templates**
2. Edit template
3. Set **Verbosity** to `3 (Debug)`
4. Save

### Check Ansible Facts

```bash
ansible -i inventory/ibm-cloud.yml <host> -m setup
```

### Inspect Task Output

```bash
# Get job output
JOB_ID=<job-id>
curl -sk -u admin:"$GATEWAY_PASSWORD" \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/jobs/$JOB_ID/stdout/?format=txt"
```

---

## Workflow-Specific Issues

### Workflow 1: Infrastructure Deployment

**Issue**: HAProxy configuration fails

**Check**:
```bash
ssh admin@<haproxy-host> "systemctl status haproxy"
ssh admin@<haproxy-host> "haproxy -c -f /etc/haproxy/haproxy.cfg"
```

**Issue**: Certificate generation fails

**Check**:
```bash
# For Let's Encrypt
dig TXT _acme-challenge.registry.example.com

# For self-signed
ls -l /opt/registry-credentials/
```

### Workflow 2: Image Mirroring

**Issue**: oc-mirror port 55000 conflict

**Fix**: Clear async cache (see [Resolve oc-mirror Async Cache](resolve-oc-mirror-async-cache.md))

**Issue**: Registry authentication fails

**Fix**: See [Resolve Registry TLS Authentication](resolve-registry-tls-authentication.md)

---

## Get Help

1. **Check logs**: `/data/logs/` on hypervisor
2. **Review ADRs**: `docs/adrs/` for architectural context
3. **Search hardening reports**: `docs/hardening/` for similar failures
4. **Check CLAUDE.md**: Known failure patterns section
