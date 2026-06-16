# How to Deploy Workflow 1 (Registry Infrastructure)

Deploy container registry infrastructure for OpenShift disconnected deployments.

**Prerequisites**: VyOS router, DNS services, and AAP 2.6 deployed (bootstrap layer).

---

## Deploy via AAP Web UI

1. Navigate to **Templates → Workflows**
2. Find **"Workflow 1: Registry Infrastructure Deployment"**
3. Click the rocket icon (🚀)
4. Fill the survey:
   - **Registry Type**: `quay`, `harbor`, or `jfrog`
   - **Certificate Mode**: `letsencrypt` or `selfsigned`
5. Click **Launch**

Monitor execution (15-30 minutes total):
- Step 1: Deploy Registry VM (5 min)
- Step 2: Setup Registry (10 min)
- Step 3: Configure HAProxy (2 min)
- Step 4: Setup Certificates (2 min)
- Step 5: Verify Infrastructure (1 min)

---

## Deploy via Ansible CLI

```bash
# Deploy Workflow 1 configuration to AAP
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/aap-configuration/configure-infrastructure-workflow.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass

# Trigger workflow execution via API
WORKFLOW_ID=$(curl -sk -u admin:"$GATEWAY_PASSWORD" \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/workflow_job_templates/" | \
  jq -r '.results[] | select(.name == "Workflow 1: Registry Infrastructure Deployment") | .id')

curl -sk -u admin:"$GATEWAY_PASSWORD" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"extra_vars": {"registry_type": "quay", "certificate_mode": "selfsigned"}}' \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/workflow_job_templates/$WORKFLOW_ID/launch/"
```

---

## Manual Playbook Execution (AAP Unavailable)

If AAP is down, run playbooks manually:

```bash
# Step 1: Deploy Registry VM
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-registry.yml

# Step 2: Setup Registry (Quay)
ansible-playbook -i inventory/ibm-cloud.yml playbooks/setup-mirror-registry.yml

# Step 3: Configure HAProxy
ansible-playbook -i inventory/ibm-cloud.yml playbooks/setup-haproxy.yml

# Step 4: Setup Certificates
ansible-playbook -i inventory/ibm-cloud.yml playbooks/setup-certificates.yml \
  -e certificate_mode=selfsigned

# Step 5: Verify Infrastructure
ansible-playbook -i inventory/ibm-cloud.yml playbooks/verify-infrastructure-deployment.yml
```

---

## Verify Deployment Success

Check registry health:

```bash
curl -k https://registry.example.com:8443/health/instance
```

Expected:
```json
{
  "data": {
    "services": {
      "auth": "running",
      "database": "running",
      "redis": "running"
    }
  }
}
```

Test authentication:

```bash
podman login registry.example.com:8443 -u init
```

---

## Common Issues

**Issue**: Step 2 fails with "Playbook not found"

**Fix**: Trigger AAP project sync:
```bash
curl -sk -u admin:"$GATEWAY_PASSWORD" -X POST \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/projects/15/update/"
```

**Issue**: HAProxy not routing correctly

**Fix**: Check HAProxy backend status:
```bash
echo "show stat" | socat stdio /var/lib/haproxy/stats
```
