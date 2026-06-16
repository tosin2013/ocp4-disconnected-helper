---
layout: default
title: Import GitHub Projects to AAP
parent: How-To Guides
nav_order: 3
---


**Goal**: Import this repository into AAP 2.6 and create job templates for automation workflows

**Prerequisites**:
- AAP 2.6 activated with valid subscription ✅
- Admin access to https://aap.sandbox3377.opentlc.com ✅
- **Red Hat Container Registry credentials configured** (see below) ⚠️
- This repository accessible via Git URL

---

## ⚠️ **CRITICAL: Configure Red Hat Registry Credentials First**

Before importing projects, AAP needs authentication to pull execution environment container images from `registry.redhat.io`.

**Quick Setup**:
1. Log in: https://aap.sandbox3377.opentlc.com
2. **Administration** → **Execution Environments**
3. Edit **Control Plane Execution Environment**
4. **Credential** → Create new **Container Registry** credential:
   - Registry URL: `registry.redhat.io`
   - Username: (from `extra_vars/rhel-subscription-secrets.yml`)
   - Password: (from `extra_vars/rhel-subscription-secrets.yml`)
5. Save and assign credential to execution environment

**Why this matters**: Without this, project syncs fail with:
```
Error: unable to retrieve auth token: invalid username/password: unauthorized
```

See `docs/AAP_POST_INSTALLATION.md` for detailed instructions.

---

## Step 1: Create Git Project in AAP

### Via Web UI

1. **Navigate to Projects**:
   - Log in: https://aap.sandbox3377.opentlc.com
   - Username: `admin`
   - Password: `<automationgateway_admin_password>`
   - Click **Resources** → **Projects** → **Add**

2. **Configure Project Details**:
   ```
   Name: ocp4-disconnected-helper
   Description: OpenShift 4 Disconnected Helper - KVM-based automation for air-gapped OCP deployments
   Organization: Default
   Execution Environment: Default execution environment (use default)
   ```

3. **Configure Source Control**:
   ```
   Source Control Credential Type: Git
   Source Control URL: /home/vpcuser/ocp4-disconnected-helper
   ```
   
   ⚠️ **Important**: For local repository (no GitHub remote yet), use **local filesystem path** instead of Git URL.

   **Alternative for Git URL** (if you've pushed to GitHub):
   ```
   Source Control URL: https://github.com/yourusername/ocp4-disconnected-helper.git
   Source Control Branch/Tag/Commit: main
   ```

4. **Update Options**:
   ```
   ☑ Update Revision on Launch (recommended - pulls latest on each job)
   ☐ Allow Branch Override (not needed for now)
   ```

5. **Save and Sync**:
   - Click **Save**
   - AAP will automatically sync the project
   - Watch for green checkmark: "Successful"
   - If red X appears, check SCM URL and permissions

### Via API (Alternative)

```bash
curl -k -u admin:<admin_password> \
  -H "Content-Type: application/json" \
  -X POST \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/projects/ \
  -d '{
    "name": "ocp4-disconnected-helper",
    "description": "OpenShift 4 Disconnected Helper",
    "organization": 1,
    "scm_type": "git",
    "scm_url": "/home/vpcuser/ocp4-disconnected-helper",
    "scm_update_on_launch": true
  }'
```

**Expected Response**:
```json
{
  "id": 6,
  "name": "ocp4-disconnected-helper",
  "status": "successful",
  ...
}
```

---

## Step 2: Create Inventory for Localhost Execution

AAP needs an inventory to run playbooks. For infrastructure automation (VM provisioning, HAProxy config), we use `localhost`.

### Via Web UI

1. **Navigate to Inventories**:
   - Resources → **Inventories** → **Add** → **Inventory**

2. **Configure Inventory**:
   ```
   Name: KVM Hypervisor (Localhost)
   Description: Local execution for libvirt VM provisioning and infrastructure automation
   Organization: Default
   ```

3. **Save** then **Add Host**:
   - Click on your new inventory
   - **Hosts** tab → **Add**
   - Configure host:
     ```
     Name: localhost
     Description: Local hypervisor for VM provisioning
     Variables (YAML):
     ```
     ```yaml
     ---
     ansible_connection: local
     ansible_python_interpreter: /usr/bin/python3
     ```

4. **Save Host**

### Via API (Alternative)

```bash
# Create inventory
INVENTORY_ID=$(curl -k -u admin:<admin_password> \
  -H "Content-Type: application/json" \
  -X POST \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/inventories/ \
  -d '{
    "name": "KVM Hypervisor (Localhost)",
    "organization": 1
  }' | jq -r '.id')

# Add localhost host
curl -k -u admin:<admin_password> \
  -H "Content-Type: application/json" \
  -X POST \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/inventories/$INVENTORY_ID/hosts/ \
  -d '{
    "name": "localhost",
    "variables": "ansible_connection: local\nansible_python_interpreter: /usr/bin/python3"
  }'
```

---

## Step 3: Create Machine Credential for VM Access

For playbooks that SSH into VMs (like AAP nodes, registry VMs), we need SSH credentials.

### Via Web UI

1. **Navigate to Credentials**:
   - Resources → **Credentials** → **Add**

2. **Configure Credential**:
   ```
   Name: VM SSH Key
   Description: SSH key for accessing provisioned VMs (admin/ansible users)
   Organization: Default
   Credential Type: Machine
   ```

3. **Authentication Details**:
   ```
   Username: ansible
   SSH Private Key: <paste contents of ~/.ssh/id_rsa>
   Privilege Escalation Method: sudo
   Privilege Escalation Username: (leave blank - defaults to root)
   ```

4. **Save**

---

## Step 4: Create Vault Credential for Secrets

For playbooks that need secrets (AAP passwords, registry credentials), create a vault credential.

### Via Web UI

1. **Resources → Credentials → Add**

2. **Configure**:
   ```
   Name: Ansible Vault Password
   Description: Vault password for extra_vars/rhel-subscription-secrets.yml
   Organization: Default
   Credential Type: Vault
   ```

3. **Vault Details**:
   ```
   Vault Password: <your vault password from ~/.vault_pass>
   Vault Identifier: (leave blank for default vault)
   ```

4. **Save**

---

## Step 5: Create Job Template for oc-mirror Workflow

Now create a job template for the oc-mirror image mirroring workflow.

### Via Web UI

1. **Navigate to Templates**:
   - Resources → **Templates** → **Add** → **Job Template**

2. **Configure Template**:
   ```
   Name: OCP Image Mirror (oc-mirror to Disk)
   Description: Mirror OpenShift container images to TAR file for disconnected environments
   Job Type: Run
   Inventory: KVM Hypervisor (Localhost)
   Project: ocp4-disconnected-helper
   Playbook: playbooks/download-to-disk-v2.yml
   Credentials:
     - Machine: VM SSH Key
     - Vault: Ansible Vault Password
   ```

3. **Variables (YAML)**:
   ```yaml
   ---
   # oc-mirror configuration
   ocp_version: "4.21"
   platform: "aws"
   mirror_storage_path: "/data/ocp-mirror"
   clean_mirror: false
   
   # Include optional operators (set to true as needed)
   include_odf: false
   include_serverless: false
   include_service_mesh: false
   include_pipelines: false
   ```

4. **Options**:
   ```
   ☑ Prompt on Launch: Variables (allow runtime override)
   ☑ Enable Concurrent Jobs (if you want parallel mirrors)
   ☐ Enable Fact Storage (not needed for infrastructure tasks)
   ```

5. **Advanced**:
   ```
   Job Slice Count: 1 (no slicing needed)
   Timeout: 7200 (2 hours - oc-mirror can take a while)
   ```

6. **Save**

### Test Launch

1. Click **Launch** on your job template
2. AAP will prompt for variable overrides (if you enabled "Prompt on Launch")
3. Optionally override `ocp_version` or `clean_mirror`
4. Click **Next** → **Launch**
5. Watch real-time output in the Jobs view

**Expected Output**:
- ✅ Play 1: Preflight checks (disk space, oc-mirror binary)
- ✅ Play 2: Generate ImageSetConfiguration
- ✅ Play 3: Run oc-mirror to TAR
- ✅ Play 4: Verification (TAR size, image count)
- ✅ Final: Mirror summary with TAR path

---

## Step 6: Create Additional Useful Job Templates

### Template: Deploy Registry VM

```
Name: Deploy Registry VM (mirror-registry)
Playbook: playbooks/deploy-registry.yml
Inventory: KVM Hypervisor (Localhost)
Credentials: VM SSH Key, Ansible Vault Password
Variables:
  registry_type: mirror-registry
  external_domain: sandbox3377.opentlc.com
```

### Template: Setup HAProxy

```
Name: Configure HAProxy Load Balancer
Playbook: playbooks/setup-haproxy.yml
Inventory: KVM Hypervisor (Localhost)
Credentials: Ansible Vault Password
Variables:
  deployment_type: cloud
  ssl_provider: letsencrypt
```

### Template: Validate AAP Passwords

```
Name: Validate AAP Password Configuration
Playbook: playbooks/validate-aap-passwords.yml
Inventory: KVM Hypervisor (Localhost)
Credentials: Ansible Vault Password
Variables: (none needed)
```

---

## Step 7: Create Workflow Template (Advanced)

Combine multiple job templates into an orchestrated workflow.

### Example: Full Registry Deployment Workflow

1. **Resources → Templates → Add → Workflow Template**

2. **Configure**:
   ```
   Name: Full Registry Deployment
   Description: End-to-end registry deployment (VM + certs + registry + HAProxy)
   Organization: Default
   Inventory: KVM Hypervisor (Localhost)
   ```

3. **Workflow Visualizer** (click "Visualizer" button):
   - **Node 1**: Validate AAP Passwords (preflight check)
   - **Node 2** (on success): Deploy Registry VM
   - **Node 3** (on success): Configure HAProxy
   - **Node 4** (on success): Verify Registry Health

4. **Save** and **Launch**

---

## Troubleshooting

### Issue: Project Sync Fails with "Permission Denied"

**Symptom**: Red X on project sync, error: "fatal: could not read from remote repository"

**Solution** (for local filesystem):
```bash
# Ensure AAP service account can read the repo
sudo chmod -R o+rX /home/vpcuser/ocp4-disconnected-helper

# Or change ownership
sudo chown -R awx:awx /home/vpcuser/ocp4-disconnected-helper
```

**Alternative**: Use Git URL instead of filesystem path (push to GitHub first)

### Issue: Job Template Shows No Playbooks

**Symptom**: Playbook dropdown is empty

**Solution**:
1. Verify project sync succeeded (green checkmark)
2. Check SCM URL is correct
3. Re-sync project: Projects → ocp4-disconnected-helper → **Sync** button
4. Wait for completion, then create job template again

### Issue: oc-mirror Job Fails with "Port 55000 Already Bound"

**Symptom**: Job fails instantly with port conflict

**Solution**: This is the async cache issue documented in CLAUDE.md
```bash
# Clear Ansible async cache
sudo rm -rf /root/.ansible_async/*

# Re-run job from AAP UI
```

### Issue: Vault Password Not Decrypting Secrets

**Symptom**: Error: "Decryption failed"

**Solution**:
1. Verify vault credential password matches `~/.vault_pass`
2. Re-create vault credential with correct password
3. Update job template to use the new credential

---

## Verification Checklist

After completing all steps:

- [ ] Project "ocp4-disconnected-helper" shows green checkmark (synced)
- [ ] Inventory "KVM Hypervisor (Localhost)" contains localhost host
- [ ] Credentials created: "VM SSH Key", "Ansible Vault Password"
- [ ] Job template "OCP Image Mirror (oc-mirror to Disk)" created
- [ ] Test launch succeeded with real-time output visible
- [ ] oc-mirror TAR file created at `/data/ocp-mirror/` on hypervisor

---

## Next Steps

1. **Schedule oc-mirror Jobs**: Set up nightly image sync
2. **Create Push-to-Registry Workflow**: Chain mirror-to-disk + push-to-registry
3. **Add Notifications**: Slack/email alerts for job failures
4. **Explore Execution Environments**: Custom container with oc-mirror pre-installed

---

## References

- [AAP 2.6 User Guide - Projects](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/automation_controller_user_guide/controller-projects)
- [AAP 2.6 User Guide - Job Templates](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/automation_controller_user_guide/controller-jobs)
- [AAP 2.6 User Guide - Workflows](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/automation_controller_user_guide/controller-workflows)
- ADR 0021: Deprecate Airflow and Adopt AAP
- ADR 0028: AAP 2.6 Multi-Node Password Architecture
