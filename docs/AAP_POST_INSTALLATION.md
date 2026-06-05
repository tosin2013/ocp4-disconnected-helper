# AAP 2.6 Post-Installation Configuration

**Last Updated**: 2026-06-05  
**AAP Version**: 2.6  
**Deployment Type**: Multi-Node (Gateway + Controller + Database)

---

## Table of Contents

1. [Initial Login](#initial-login)
2. [License Activation](#license-activation)
3. [Subscription Manifest Upload](#subscription-manifest-upload)
4. [User Management](#user-management)
5. [First Automation Project](#first-automation-project)
6. [Verification Checklist](#verification-checklist)

---

## Initial Login

### Web UI Access

**URL**: https://aap.sandbox3377.opentlc.com (or your configured domain)

**Credentials**:
- **Username**: `admin`
- **Password**: Value of `automationgateway_admin_password` from `extra_vars/rhel-subscription-secrets.yml`

⚠️ **Important**: Use the **Gateway password** (`automationgateway_admin_password`), NOT the Controller password (`admin_password`). See [ADR 0028](adrs/0028-aap-multi-node-password-architecture.md) for details.

### Expected First Login Experience

1. Navigate to https://aap.sandbox3377.opentlc.com
2. Accept SSL certificate warning (if using self-signed certificate)
3. Enter credentials at login page
4. **Subscription Required Screen**: You'll be prompted to activate AAP

---

## License Activation

AAP requires a valid Red Hat subscription to function beyond the trial period.

### Option 1: Red Hat Account Credentials (Recommended)

**When to Use**: You have a Red Hat Customer Portal account with AAP entitlement

**Steps**:
1. After initial login, click **"Get subscription"** or **"Activate"**
2. Select **"Username / Password"** authentication method
3. Enter your **Red Hat Customer Portal credentials**:
   - **Username**: Your Red Hat login email
   - **Password**: Your Red Hat portal password
4. Click **"Get subscriptions"**
5. AAP will automatically fetch and apply your subscription manifest

**Verification**:
- Dashboard shows "Subscription: Active"
- No trial expiration warning
- Automation Controller shows available automation capacity (execution nodes)

---

### Option 2: Subscription Manifest Upload

**When to Use**: 
- Air-gapped/disconnected environment (no direct internet access)
- Organization uses centralized subscription management
- Prefer manual manifest control

#### Step 1: Create Subscription Manifest at Red Hat Portal

1. Navigate to https://access.redhat.com/management/subscription_allocations
2. Click **"New Subscription Allocation"**
3. Configure allocation:
   - **Name**: `aap-production` (or your naming convention)
   - **Type**: **"Satellite 6.12+"** (AAP uses Satellite manifest format)
4. Click **"Create"**
5. In the new allocation, click **"Subscriptions" tab**
6. Click **"Add Subscriptions"**
7. Select your **Ansible Automation Platform** subscription
8. Enter quantity (number of nodes/managed hosts)
9. Click **"Submit"**
10. Return to allocation overview
11. Click **"Export Manifest"**
12. Save the `.zip` file (e.g., `manifest_aap-production_20260605.zip`)

**Manifest File Structure**:
```
manifest_aap-production_20260605.zip
├── consumer_export.zip
├── signature
└── ...
```

⚠️ **Important**: Keep the manifest `.zip` file intact - do NOT extract it before upload.

#### Step 2: Upload Manifest to AAP

**Via Web UI**:
1. Log into AAP at https://aap.sandbox3377.opentlc.com
2. Navigate to **Settings** (gear icon) → **Subscription**
3. Click **"Browse"** under **"Subscription Manifest"**
4. Select your manifest `.zip` file
5. Click **"Upload"**
6. Wait for processing (10-30 seconds)
7. Verify:
   - Status changes to **"Active"**
   - **Hosts Available** shows your subscription capacity
   - **Hosts Used** shows 0 (if new installation)

**Via API** (for automation):
```bash
# Upload manifest via Controller API
curl -k -u admin:<admin_password> \
  -H "Content-Type: application/zip" \
  --data-binary @manifest_aap-production_20260605.zip \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/config/ \
  -X POST
```

**Via Ansible**:
```yaml
- name: Upload AAP Subscription Manifest
  ansible.controller.license:
    manifest: /path/to/manifest_aap-production_20260605.zip
    controller_host: https://aap.sandbox3377.opentlc.com
    controller_username: admin
    controller_password: "{{ admin_password }}"
    validate_certs: no
```

#### Step 3: Verify Subscription Status

**Web UI Verification**:
- Settings → Subscription shows:
  - ✅ **Status**: Active
  - ✅ **Subscription Type**: Ansible Automation Platform
  - ✅ **Hosts Available**: (your subscription limit)
  - ✅ **Expiration Date**: (future date)

**API Verification**:
```bash
curl -k -u admin:<admin_password> \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/config/ \
  | jq '.license_info'

# Expected output:
{
  "license_type": "enterprise",
  "valid_key": true,
  "subscription_name": "Ansible Automation Platform",
  "instance_count": 100,
  "time_remaining": 7889238,
  ...
}
```

---

## Subscription Manifest Upload

### Disconnected/Air-Gapped Environments

If your AAP deployment has no internet access, you must use the manifest upload method:

1. **On Connected Workstation**:
   - Generate manifest at https://access.redhat.com (see Option 2 above)
   - Download `manifest_*.zip` file

2. **Transfer to AAP Environment**:
   ```bash
   # From connected workstation
   scp manifest_aap-production_20260605.zip \
     user@jump-host:/tmp/

   # From jump-host to AAP gateway
   scp /tmp/manifest_aap-production_20260605.zip \
     ansible@192.168.10.20:/tmp/
   ```

3. **Upload via Web UI or API** (see Option 2, Step 2 above)

---

## User Management

### Create Additional Admin Users

**Via Web UI**:
1. Navigate to **Access** → **Users**
2. Click **"Add"**
3. Fill in user details:
   - **Username**: `john.doe`
   - **Email**: `john.doe@example.com`
   - **Password**: (set secure password)
   - **User Type**: **System Administrator** (for admin access)
4. Click **"Save"**

**Via API**:
```bash
curl -k -u admin:<admin_password> \
  -H "Content-Type: application/json" \
  -X POST \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/users/ \
  -d '{
    "username": "john.doe",
    "email": "john.doe@example.com",
    "password": "SecurePassword123!",
    "is_superuser": true
  }'
```

### Set Up LDAP/Active Directory (Optional)

**For Enterprise Environments**:
1. Navigate to **Settings** → **LDAP**
2. Configure LDAP server details:
   - **LDAP Server URI**: `ldap://ldap.example.com`
   - **Bind DN**: `cn=admin,dc=example,dc=com`
   - **Bind Password**: (LDAP admin password)
   - **User Search**: `ou=users,dc=example,dc=com`
3. Click **"Test"** to verify connection
4. Click **"Save"**

**Reference**: [AAP LDAP Authentication](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/automation_controller_user_guide/controller-ldap-authentication)

---

## First Automation Project

### Quick Start: Import ocp4-disconnected-helper Project

1. **Navigate to Projects**:
   - Resources → Projects → **Add**

2. **Configure Git Project**:
   - **Name**: `ocp4-disconnected-helper`
   - **Organization**: `Default`
   - **Source Control Type**: **Git**
   - **Source Control URL**: `https://github.com/yourusername/ocp4-disconnected-helper.git`
   - **Source Control Branch/Tag/Commit**: `main`
   - **Update Revision on Launch**: ✅ (checked)

3. **Save and Sync**:
   - Click **"Save"**
   - Click **"Sync"** button to pull playbooks
   - Wait for green checkmark (sync successful)

4. **Verify Playbooks Available**:
   - Navigate to **Resources** → **Templates** → **Add** → **Job Template**
   - In **Playbook** dropdown, you should see all playbooks from the repo:
     - `playbooks/deploy-registry.yml`
     - `playbooks/setup-haproxy.yml`
     - `playbooks/deploy-aap-multi-node.yml`
     - etc.

### Create Your First Job Template

1. **Navigate to Templates**:
   - Resources → Templates → **Add** → **Job Template**

2. **Configure Template**:
   - **Name**: `Deploy Registry VM`
   - **Job Type**: **Run**
   - **Inventory**: (create inventory first, see below)
   - **Project**: `ocp4-disconnected-helper`
   - **Playbook**: `playbooks/deploy-registry.yml`
   - **Credentials**: (add SSH credential for VMs)
   - **Variables** (in YAML):
     ```yaml
     registry_type: mirror-registry
     external_domain: sandbox3377.opentlc.com
     ```

3. **Save and Launch**:
   - Click **"Save"**
   - Click **"Launch"** to run the job
   - Monitor output in real-time

### Create Inventory

1. **Navigate to Inventories**:
   - Resources → Inventories → **Add** → **Inventory**

2. **Configure Inventory**:
   - **Name**: `KVM Hypervisor`
   - **Organization**: `Default`

3. **Add Hosts**:
   - Click on your new inventory → **Hosts** tab → **Add**
   - **Name**: `localhost`
   - **Variables**:
     ```yaml
     ansible_connection: local
     ansible_python_interpreter: /usr/bin/python3
     ```

4. **For VM Management**, create another inventory:
   - **Name**: `Managed VMs`
   - Add hosts: `registry-vm`, `aap-gateway`, etc.
   - Configure SSH connection variables

---

## Verification Checklist

After completing post-installation configuration, verify:

### ✅ License and Subscription

- [ ] Web UI shows "Subscription: Active"
- [ ] No trial expiration warnings
- [ ] Subscription manifest uploaded (if disconnected)
- [ ] `curl -k https://aap.../api/controller/v2/config/ | jq '.license_info.valid_key'` returns `true`

### ✅ Authentication

- [ ] Admin user can log in with Gateway password
- [ ] API authentication works with Controller password
- [ ] Additional users created (if needed)
- [ ] LDAP/AD integration tested (if configured)

### ✅ Projects and Automation

- [ ] First project imported from Git
- [ ] Playbooks visible in job template dropdown
- [ ] First job template created
- [ ] Test job executed successfully

### ✅ Network and Access

- [ ] Web UI accessible from browser (https://aap.sandbox3377.opentlc.com)
- [ ] Controller API responds: `curl -k https://aap.../api/controller/v2/ping/`
- [ ] Gateway API responds: `curl -k https://aap.../api/gateway/`
- [ ] HAProxy health checks passing (if using HAProxy)

### ✅ Multi-Node Cluster Health

- [ ] Gateway VM (192.168.10.20): nginx running, web UI responding
- [ ] Controller VM (192.168.10.21): automation-controller service active
- [ ] Database VM (192.168.10.22): postgresql service active
- [ ] All VMs registered with RHEL subscription
- [ ] SSH connectivity between nodes working

---

## Troubleshooting

### Issue: "Subscription Required" Warning Persists

**Symptom**: After uploading manifest, AAP still shows trial/activation required

**Solution**:
```bash
# Restart AAP services
ssh ansible@192.168.10.20
sudo systemctl restart nginx
ssh ansible@192.168.10.21
sudo systemctl restart automation-controller
```

### Issue: Manifest Upload Fails

**Symptom**: Error: "Invalid manifest file" or upload hangs

**Solution**:
1. Verify manifest file is `.zip` format (not extracted)
2. Check manifest was downloaded completely (not corrupted)
3. Ensure manifest subscription type matches AAP (not Satellite/RHEL-only)
4. Try uploading via API instead of web UI:
   ```bash
   curl -k -u admin:<password> \
     --data-binary @manifest.zip \
     -H "Content-Type: application/zip" \
     https://aap.../api/controller/v2/config/ -X POST
   ```

### Issue: Cannot Access Web UI After Activation

**Symptom**: AAP activated successfully but web UI shows 502/503 errors

**Solution**:
```bash
# Check Gateway service status
ssh ansible@192.168.10.20
sudo systemctl status nginx
sudo journalctl -u nginx -n 50

# Restart if needed
sudo systemctl restart nginx
```

---

## Next Steps

After successful activation and verification:

1. **Import Production Inventories**: Add your real infrastructure hosts
2. **Configure Credentials**: Set up SSH keys, vault passwords, cloud credentials
3. **Create Workflow Templates**: Chain multiple playbooks together
4. **Set Up Schedules**: Automate recurring jobs (backups, updates)
5. **Configure Notifications**: Slack/email alerts for job failures
6. **Explore Execution Environments**: Custom container images for automation

---

## References

- [AAP 2.6 User Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/automation_controller_user_guide/)
- [Subscription Management](https://access.redhat.com/management/subscription_allocations)
- [AAP License Model](https://www.redhat.com/en/technologies/management/ansible/pricing)
- [ADR 0028: Multi-Node Password Architecture](adrs/0028-aap-multi-node-password-architecture.md)
