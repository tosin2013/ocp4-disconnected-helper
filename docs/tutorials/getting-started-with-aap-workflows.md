# Tutorial: Getting Started with AAP Workflows

**Time to Complete**: 60-90 minutes  
**Prerequisites**: Fresh IBM Cloud VSI with CentOS Stream 10  
**What You'll Learn**: Deploy complete AAP workflow infrastructure from scratch  
**End State**: Working AAP 2.6 with Workflow 1 and 2 configured and ready to execute

---

## What You Will Build

By the end of this tutorial, you will have:
- ✅ VyOS router providing network services
- ✅ DNS services (Route53 or FreeIPA)
- ✅ AAP 2.6 automation platform
- ✅ Workflow 1: Registry Infrastructure Deployment (configured)
- ✅ Workflow 2: Image Mirroring (configured)
- ✅ Verification that workflows execute successfully

This is the **foundation** for all OpenShift disconnected deployments in this project.

---

## Step 1: Clone the Repository

Open your terminal and clone the project:

```bash
cd ~
git clone https://github.com/tosin2013/ocp4-disconnected-helper
cd ocp4-disconnected-helper
```

Install the pre-commit hook to prevent credential leaks:

```bash
./scripts/install-git-hooks.sh
```

You will see:
```
✅ Git hooks installed successfully
```

---

## Step 2: Set Up Your Credentials

Create an encrypted secrets file for your Red Hat credentials:

```bash
# Create vault password file
echo "your-vault-password-here" > ~/.vault_pass
chmod 600 ~/.vault_pass

# Copy the secrets template
cp extra_vars/rhel-subscription-secrets.yml.example \
   extra_vars/rhel-subscription-secrets.yml
```

Edit the secrets file:

```bash
ansible-vault edit extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

Update these values:
- `redhat_username`: Your Red Hat Customer Portal username
- `redhat_password`: Your Red Hat Customer Portal password
- `admin_password`: AAP Controller API password (create a strong password)
- `automationgateway_admin_password`: AAP Web UI password (create a strong password)
- `postgresql_admin_password`: PostgreSQL password (create a strong password)

**Important**: Use **different passwords** for `admin_password` and `automationgateway_admin_password`. See the explanation on [AAP 2.6 password architecture](../explanations/aap-password-architecture.md).

Save and exit (`:wq` in vim).

---

## Step 3: Deploy the Bootstrap Layer

The bootstrap layer consists of infrastructure that **must exist before AAP can work**. This is deployed via manual playbooks, not AAP workflows (because AAP doesn't exist yet!).

### 3.1: Deploy VyOS Router

The VyOS router provides network routing for all VMs:

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-vyos.yml
```

Wait 5-10 minutes. You will see:
```
PLAY RECAP *********************************************************************
localhost                  : ok=X    changed=Y    unreachable=0    failed=0
```

Verify the router is accessible:

```bash
ssh vyos@192.168.122.2 "show version"
```

Expected output:
```
Version:          VyOS 1.4.x
Release train:    sagitta
```

### 3.2: Deploy DNS Services

Deploy Route53 DNS (requires AWS credentials):

```bash
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/setup-route53-dns.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

Wait 2-3 minutes. Verify DNS resolution:

```bash
nslookup aap.sandbox3377.opentlc.com
```

Expected output:
```
Server:         192.168.122.1
Address:        192.168.122.1#53

Name:   aap.sandbox3377.opentlc.com
Address: 192.168.122.30
```

### 3.3: Deploy AAP 2.6

Now deploy the automation platform itself:

```bash
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/deploy-aap-multi-node.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

This takes 15-20 minutes. **Go get coffee!** ☕

When complete, you will see:
```
TASK [Display AAP deployment summary] ******************************************
ok: [localhost] => {
    "msg": [
        "==============================================",
        "AAP 2.6 Deployment Complete!",
        "==============================================",
        "Web UI: https://aap.sandbox3377.opentlc.com",
        "Username: admin",
        "Password: <automationgateway_admin_password from secrets file>",
        ...
    ]
}
```

Verify AAP is accessible:

```bash
curl -sk https://aap.sandbox3377.opentlc.com/api/controller/v2/ping/ | jq .
```

Expected output:
```json
{
  "instances": [...],
  "instance_groups": [...],
  "ha": true,
  "version": "4.7.12",
  "active_node": "..."
}
```

---

## Step 4: Configure Workflows in AAP

Now that AAP exists, configure the two workflows.

### 4.1: Configure Workflow 1 (Registry Infrastructure)

```bash
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/aap-configuration/configure-infrastructure-workflow.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

Wait 2-3 minutes. You will see:
```
TASK [Display workflow configuration summary] **********************************
ok: [localhost] => {
    "msg": [
        "==============================================",
        "Workflow 1: Registry Infrastructure Deployment - Configured",
        "==============================================",
        "Workflow Name: Workflow 1: Registry Infrastructure Deployment",
        "Survey Enabled: Yes (2 questions)",
        "Nodes: 5 job templates",
        ...
    ]
}
```

### 4.2: Configure Workflow 2 (Image Mirroring)

```bash
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/aap-configuration/configure-oc-mirror-workflow.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

Wait 2-3 minutes. You will see:
```
TASK [Display workflow configuration summary] **********************************
ok: [localhost] => {
    "msg": [
        "==============================================",
        "Workflow 2: OpenShift Image Mirroring - Configured",
        "==============================================",
        "Workflow Name: Workflow 2: OpenShift Image Mirroring",
        "Survey Enabled: Yes (2 questions)",
        "Nodes: 4 job templates",
        ...
    ]
}
```

---

## Step 5: Verify Workflows in AAP Web UI

Open your browser and navigate to AAP:

**URL**: https://aap.sandbox3377.opentlc.com  
**Username**: `admin`  
**Password**: `<automationgateway_admin_password>` (from secrets file)

### 5.1: Check Workflow 1

1. Click **Templates** in the left sidebar
2. Click **Workflows** tab
3. Find **"Workflow 1: Registry Infrastructure Deployment"**
4. Click the workflow name to view details

You should see:
- **Survey**: Enabled (2 questions)
- **Workflow Visualizer**: 5 nodes in sequence

### 5.2: Check Workflow 2

1. Still in **Templates → Workflows**
2. Find **"Workflow 2: OpenShift Image Mirroring"**
3. Click the workflow name to view details

You should see:
- **Survey**: Enabled (2 questions)
- **Workflow Visualizer**: 4 nodes (Step 0 validation + 3 execution nodes)

---

## Step 6: Test Workflow Execution (Optional)

**Warning**: This step will provision VMs and download ~50GB of container images. Only proceed if you have:
- At least 100GB free disk space
- Time for a 1-2 hour workflow execution

### 6.1: Launch Workflow 2 (Simpler Test)

Workflow 2 is easier to test because it assumes the registry already exists.

1. In AAP Web UI, go to **Templates → Workflows**
2. Click the rocket icon (🚀) next to **"Workflow 2: OpenShift Image Mirroring"**
3. Fill the survey:
   - **Operator Preset**: `storage-operators` (or any preset)
   - **Registry URL**: `registry.example.com:8443` (your registry)
4. Click **Launch**

You will see:
- **Step 0**: Verify prerequisites (should FAIL if no registry exists)
- Workflow stops with helpful error message directing you to run Workflow 1 first

This confirms prerequisite validation is working!

### 6.2: Launch Workflow 1 (Full Test)

If you want to deploy the full infrastructure:

1. Go to **Templates → Workflows**
2. Click the rocket icon (🚀) next to **"Workflow 1: Registry Infrastructure Deployment"**
3. Fill the survey:
   - **Registry Type**: `quay`
   - **Certificate Mode**: `selfsigned`
4. Click **Launch**

Monitor the workflow execution (15-30 minutes):
- **Step 1**: Deploy Registry VM (5 min)
- **Step 2**: Setup Registry (10 min)
- **Step 3**: Configure HAProxy (2 min)
- **Step 4**: Setup Certificates (2 min)
- **Step 5**: Verify Infrastructure (1 min)

---

## What You've Accomplished

Congratulations! You now have:

✅ **Bootstrap Layer**:
- VyOS router (network services)
- DNS services (name resolution)
- AAP 2.6 (automation platform)

✅ **Workflow Layer**:
- Workflow 1 configured (Registry Infrastructure Deployment)
- Workflow 2 configured (Image Mirroring)
- Prerequisite validation enforcing execution order

✅ **Skills Gained**:
- Deploying infrastructure with Ansible playbooks
- Configuring AAP workflows
- Using AAP surveys for parameterized execution
- Verifying workflow health via API and Web UI

---

## Next Steps

Now that you have AAP workflows configured:

1. **Deploy a registry** using Workflow 1
2. **Mirror OpenShift images** using Workflow 2
3. **Deploy an OpenShift cluster** (Workflow 3 - coming in v1.4)

Continue with:
- [Tutorial: Your First OpenShift Image Mirror](your-first-openshift-image-mirror.md)
- [How-To: Deploy Workflow 1 (Registry Infrastructure)](../how-to/deploy-workflow-1.md)
- [How-To: Troubleshoot Workflow Failures](../how-to/troubleshoot-workflow-failures.md)

---

## Troubleshooting

### Issue: AAP Web UI login fails

**Symptom**: "Invalid username or password" when logging into AAP Web UI

**Solution**: Use the **Gateway password** (`automationgateway_admin_password`), not the Controller password (`admin_password`). See [ADR-0028](../adrs/0028-aap-multi-node-password-architecture.md) for details.

### Issue: Workflow 2 fails at Step 0

**Symptom**: "Prerequisites not met: Registry not deployed"

**Solution**: This is expected! Run Workflow 1 first to deploy the registry infrastructure.

### Issue: VyOS router not accessible

**Symptom**: `ssh vyos@192.168.122.2` times out

**Solution**:
1. Check VM is running: `virsh list`
2. If VM missing, re-run: `ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-vyos.yml`

---

## Further Reading

**Architecture**:
- [Explanation: Bootstrap vs Workflow Layers](../explanations/bootstrap-vs-workflow-layers.md)
- [ADR-0032: Multi-Workflow Architecture](../adrs/adr-0032-aap-workflow-orchestration-strategy.md)

**Operations**:
- [AAP Workflow Catalog](../AAP_WORKFLOW_CATALOG.md) (complete workflow reference)
- [AAP Deployment Guide](../AAP_DEPLOYMENT_GUIDE.md) (detailed AAP installation)
