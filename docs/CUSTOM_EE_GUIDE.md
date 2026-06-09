# Custom Execution Environment for AAP - Quick Start Guide

**ADR Reference**: [ADR 0029](adrs/0029-custom-execution-environment-for-aap-registry-authentication.md)

**Purpose**: Resolve AAP project sync failures caused by immutable Control Plane Execution Environment lacking `registry.redhat.io` authentication.

---

## Prerequisites

- ✅ AAP 2.6 multi-node deployed and accessible
- ✅ Podman installed on build host (`podman --version`)
- ✅ ansible-builder installed (`pip install ansible-builder`)
- ✅ Quay.io account created with private repository access
- ✅ Red Hat registry credentials available

---

## Step 1: Fork Execution Environment Repository

```bash
# Fork and clone the repository
gh repo fork tosin2013/ansible-execution-environment \
  --clone --remote \
  --fork-name ocp4-aap-execution-environment

cd ocp4-aap-execution-environment

# Update remote URLs
git remote rename origin upstream
git remote add origin git@github.com:YOUR_USERNAME/ocp4-aap-execution-environment.git
```

**Verification**:
```bash
git remote -v
# Should show:
#   origin    git@github.com:YOUR_USERNAME/ocp4-aap-execution-environment.git (fetch)
#   upstream  https://github.com/tosin2013/ansible-execution-environment.git (fetch)
```

---

## Step 2: Create Quay.io Registry Repository

1. **Log into Quay.io**: https://quay.io/
2. **Create New Repository**:
   - Name: `ocp4-aap-execution-environment`
   - Visibility: **Private** (recommended for security)
   - Description: "Custom AAP execution environment with registry.redhat.io authentication"
3. **Generate Robot Account** (optional but recommended):
   - Navigate to: Organization → Robot Accounts → Create Robot Account
   - Name: `aap_robot`
   - Permissions: Write to `ocp4-aap-execution-environment` repository
   - Save robot token: `YOUR_ORG+aap_robot:TOKEN_HERE`

**Repository URL**: `quay.io/YOUR_USERNAME/ocp4-aap-execution-environment`

---

## Step 3: Configure Secrets

Edit `extra_vars/rhel-subscription-secrets.yml`:

```yaml
# Quay.io credentials
quay_username: "YOUR_QUAY_USERNAME"
quay_password: "YOUR_QUAY_PASSWORD_OR_ROBOT_TOKEN"

# Red Hat registry credentials (already configured for AAP)
registry_username: "your-redhat-email@example.com"
registry_password: "your-redhat-portal-password"
```

**Encrypt if not already encrypted**:
```bash
ansible-vault encrypt extra_vars/rhel-subscription-secrets.yml
```

---

## Step 4: Build Custom Execution Environment

```bash
cd /home/vpcuser/ocp4-disconnected-helper

# Ensure ansible-builder is installed
pip install ansible-builder

# Build and push custom EE to Quay
ansible-playbook -i inventory/ibm-cloud.yml playbooks/build-custom-ee.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Expected Output**:
```
✅ Execution Environment Built Successfully
  - Image: quay.io/YOUR_USERNAME/ocp4-aap-execution-environment:latest
  - Size: ~1.2 GB
  - Architecture: linux/amd64

✅ Pushed to Quay Registry
  - URL: https://quay.io/repository/YOUR_USERNAME/ocp4-aap-execution-environment
```

**Build Time**: ~10-15 minutes (depends on network speed and build complexity)

---

## Step 5: Configure AAP to Use Custom EE

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/configure-custom-ee-in-aap.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**This playbook performs**:
1. Creates "Quay Custom EE Registry" credential in AAP
2. Creates "Custom OCP4 EE" execution environment pointing to Quay image
3. Sets custom EE as default for Default organization
4. Triggers test project sync to verify authentication

**Expected Output**:
```
✅ Quay registry credential created
✅ Custom execution environment created (ID: 5)
✅ Default organization updated
✅ Project Sync Status: successful
```

---

## Step 6: Verify Custom EE in AAP Web UI

1. **Log into AAP**: https://aap.sandbox3377.opentlc.com
   - Username: `admin`
   - Password: `<automationgateway_admin_password>`

2. **Verify Execution Environment**:
   - Navigate: **Administration** → **Execution Environments**
   - Find: **Custom OCP4 EE**
   - Verify:
     - ✅ Image: `quay.io/YOUR_USERNAME/ocp4-aap-execution-environment:latest`
     - ✅ Pull: Always
     - ✅ Credential: Quay Custom EE Registry

3. **Verify Default Organization Setting**:
   - Navigate: **Access** → **Organizations** → **Default**
   - Check: **Default Execution Environment** = **Custom OCP4 EE**

4. **Test Project Sync**:
   - Navigate: **Resources** → **Projects** → **ocp4-disconnected-helper**
   - Click: **Sync** button
   - Wait for status: ✅ **Successful** (green checkmark)
   - Verify no registry authentication errors in output

---

## Troubleshooting

### Issue: Build Fails with "ansible-builder: command not found"

**Solution**:
```bash
pip3 install --user ansible-builder
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

---

### Issue: Quay Authentication Fails During Push

**Symptom**:
```
Error: unauthorized: access to the requested resource is not authorized
```

**Solution**:
```bash
# Re-authenticate to Quay manually
podman login quay.io
# Username: YOUR_QUAY_USERNAME
# Password: YOUR_QUAY_PASSWORD

# Verify authentication
podman login --get-login quay.io
```

---

### Issue: AAP Project Sync Still Fails After Custom EE Configuration

**Symptom**: Same "unable to retrieve auth token" error persists

**Diagnosis Steps**:
```bash
# 1. Verify custom EE is actually being used
curl -k -u admin:<admin_password> \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/projects/<PROJECT_ID>/ \
  | jq '.default_environment'
# Should return Custom OCP4 EE ID

# 2. Check AAP can pull image from Quay
curl -k -u admin:<admin_password> \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/execution_environments/<EE_ID>/ \
  | jq '.image, .credential'

# 3. Manually test Quay credential
podman login quay.io --username YOUR_USERNAME --password YOUR_PASSWORD
podman pull quay.io/YOUR_USERNAME/ocp4-aap-execution-environment:latest
```

**Solution**:
- Ensure Quay repository visibility is **Private** (requires authentication)
- Verify Quay credential in AAP has correct username/password
- Check custom EE is set as **organization default**, not just created

---

### Issue: Custom EE Build Succeeds But Image Size is Unexpectedly Large

**Symptom**: Image size >2 GB (expected: ~1.2 GB)

**Investigation**:
```bash
# Inspect image layers
podman history quay.io/YOUR_USERNAME/ocp4-aap-execution-environment:latest

# Check for unnecessary files
podman run --rm -it quay.io/YOUR_USERNAME/ocp4-aap-execution-environment:latest /bin/bash
du -sh /*
```

**Common Causes**:
- Cached pip packages
- Development tools not removed after build
- Logs or temporary files

**Solution**: Review `execution-environment.yml` and remove unnecessary dependencies

---

## Maintenance: Credential Rotation

When Red Hat registry credentials change:

1. **Update secrets file**:
   ```bash
   ansible-vault edit extra_vars/rhel-subscription-secrets.yml
   # Update registry_username and registry_password
   ```

2. **Rebuild and republish EE**:
   ```bash
   ansible-playbook -i inventory/ibm-cloud.yml playbooks/build-custom-ee.yml \
     -e@extra_vars/rhel-subscription-secrets.yml \
     --vault-password-file ~/.vault_pass
   ```

3. **AAP automatically pulls updated image** (if "Pull: Always" is set):
   - Next project sync will use refreshed image with new credentials

**Frequency**: Rotate credentials quarterly or as required by security policy

---

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│  GitHub: ocp4-aap-execution-environment (forked repo)       │
│  ├─ execution-environment.yml (EE definition)               │
│  ├─ requirements.yml (Ansible collections)                  │
│  └─ requirements.txt (Python dependencies)                  │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼ ansible-builder build
┌─────────────────────────────────────────────────────────────┐
│  Build Host (localhost)                                     │
│  ├─ ansible-builder creates Containerfile                   │
│  ├─ Podman builds container image                           │
│  └─ Image tagged: quay.io/.../ocp4-aap-execution-environment│
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼ podman push
┌─────────────────────────────────────────────────────────────┐
│  Quay.io Registry (private repository)                      │
│  └─ quay.io/YOUR_USERNAME/ocp4-aap-execution-environment    │
│     ├─ Tag: latest                                          │
│     ├─ Visibility: Private                                  │
│     └─ Contains: registry.redhat.io credentials             │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼ AAP pulls image
┌─────────────────────────────────────────────────────────────┐
│  AAP 2.6 Multi-Node                                         │
│  ├─ Credential: "Quay Custom EE Registry"                   │
│  ├─ Execution Environment: "Custom OCP4 EE"                 │
│  │   └─ Image: quay.io/.../ocp4-aap-execution-environment   │
│  └─ Organization: Default                                   │
│      └─ Default EE: Custom OCP4 EE                          │
└─────────────────────────────────────────────────────────────┘
                         │
                         ▼ Project syncs use Custom OCP4 EE
┌─────────────────────────────────────────────────────────────┐
│  Project: ocp4-disconnected-helper                          │
│  ├─ Sync: Pulls from GitHub using Custom OCP4 EE           │
│  ├─ Custom OCP4 EE has registry.redhat.io credentials      │
│  └─ ✅ Project sync succeeds (no auth errors)               │
└─────────────────────────────────────────────────────────────┘
```

---

## Security Considerations

**Credential Storage**:
- ✅ Registry credentials embedded in container image layers
- ✅ Image stored in **private** Quay repository (access-controlled)
- ✅ AAP authenticates to Quay using dedicated credential
- ⚠️ Credentials visible to anyone with Quay repository access

**Best Practices**:
1. **Use Robot Accounts**: Quay robot accounts have scoped permissions (write-only to EE repo)
2. **Rotate Credentials**: Rebuild EE quarterly or when credentials are compromised
3. **Audit Access**: Monitor Quay repository access logs
4. **Least Privilege**: AAP Quay credential should only have pull access (not push)

**Alternatives Considered** (see ADR 0029):
- Storing credentials in HashiCorp Vault → Future enhancement (ADR 0009)
- Using Kubernetes Secrets → Not applicable (AAP is not on K8s yet)

---

## Related Documentation

- [ADR 0029: Custom Execution Environment](adrs/0029-custom-execution-environment-for-aap-registry-authentication.md)
- [AAP Post-Installation Configuration](AAP_POST_INSTALLATION.md)
- [AAP Project Import Guide](AAP_PROJECT_IMPORT_GUIDE.md)
- [AAP 2.6 Execution Environments Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/creating_and_consuming_execution_environments/)

---

## Quick Reference Commands

```bash
# Build custom EE
ansible-playbook playbooks/build-custom-ee.yml \
  -e@extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass

# Configure AAP
ansible-playbook playbooks/configure-custom-ee-in-aap.yml \
  -e@extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass

# Verify EE in AAP
curl -k -u admin:<password> \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/execution_environments/

# Test project sync
curl -k -u admin:<password> -X POST \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/projects/<ID>/update/

# Rebuild EE after credential rotation
ansible-playbook playbooks/build-custom-ee.yml \
  -e@extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass
```
