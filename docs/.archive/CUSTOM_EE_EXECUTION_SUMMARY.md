# Custom Execution Environment - Execution Summary

**Date**: 2026-06-05  
**ADR**: [ADR 0029](adrs/0029-custom-execution-environment-for-aap-registry-authentication.md)  
**Status**: Ready for Build & Deploy

---

## ✅ Completed Setup

### 1. Repository Preparation
- ✅ Cloned `tosin2013/ansible-execution-environment` → `/home/vpcuser/ocp4-aap-execution-environment`
- ✅ Modified `execution-environment.yml` to include `registry.redhat.io` authentication (ADR 0029)
- ✅ Registry authentication added via build args (`REGISTRY_USERNAME`, `REGISTRY_PASSWORD`)

### 2. Quay Registry
- ✅ Registry created: `quay.io/takinosh/ocp4-aap-execution-environment`
- ✅ Verified accessible: `podman pull quay.io/takinosh/ocp4-aap-execution-environment`

### 3. Automation Playbooks
- ✅ `playbooks/build-custom-ee.yml` - Builds EE and pushes to Quay
- ✅ `playbooks/configure-custom-ee-in-aap.yml` - Configures AAP to use custom EE
- ✅ Both playbooks configured for Quay registry: `quay.io/takinosh/`

### 4. Documentation
- ✅ ADR 0029 written and accepted
- ✅ Quick-start guide: `docs/CUSTOM_EE_GUIDE.md`
- ✅ Secrets template updated with Quay credentials section

---

## 🚀 Next Steps: Build & Deploy

### Step 1: Configure Quay Robot Account (One-Time Setup)

**✅ RECOMMENDED**: Use Quay robot account for automation (not personal credentials).

**See detailed setup guide**: [Quay Robot Account Setup](QUAY_ROBOT_ACCOUNT_SETUP.md)

**Quick Setup**:

1. **Create robot account in Quay**:
   - Go to: https://quay.io/repository/takinosh/ocp4-aap-execution-environment
   - Settings → Robot Accounts → Create Robot Account
   - Name: `aap_builder`
   - Permissions: **Write** (for pushing images)
   - Copy robot token (shown only once)

2. **Update secrets file**:

```bash
ansible-vault edit extra_vars/rhel-subscription-secrets.yml
```

Add robot account credentials:

```yaml
# Quay.io Robot Account (Recommended)
# Format: {username}+{robot_name}
quay_username: "takinosh+aap_builder"
quay_password: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIs..."  # Robot token

# Red Hat Registry Credentials (already configured)
registry_username: "your-redhat-email@example.com"
registry_password: "your-redhat-portal-password"
```

Save and exit (`:wq` in vim).

3. **Test robot authentication** (optional but recommended):

```bash
echo "YOUR_ROBOT_TOKEN" | podman login quay.io \
  --username takinosh+aap_builder --password-stdin

# Verify
podman login --get-login quay.io
# Should show: takinosh+aap_builder
```

---

### Step 2: Build Custom Execution Environment

This builds the container image with embedded registry.redhat.io credentials and pushes to Quay:

```bash
cd /home/vpcuser/ocp4-disconnected-helper

ansible-playbook -i inventory/ibm-cloud.yml playbooks/build-custom-ee.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**What this does**:
1. Verifies ansible-builder is installed (installs if missing)
2. Builds EE image at `/home/vpcuser/ocp4-aap-execution-environment`
3. Embeds `registry.redhat.io` auth via build args
4. Tags image: `quay.io/takinosh/ocp4-aap-execution-environment:latest`
5. Authenticates to Quay with your credentials
6. Pushes image to Quay registry

**Expected Duration**: 10-15 minutes (depends on network speed)

**Success Indicators**:
```
✅ Execution Environment Built Successfully
  - Image: quay.io/takinosh/ocp4-aap-execution-environment:latest
  - Size: ~1.2 GB
  
✅ Pushed to Quay Registry
  - URL: https://quay.io/repository/takinosh/ocp4-aap-execution-environment
```

---

### Step 3: Configure AAP to Use Custom EE

This creates the execution environment in AAP and sets it as the default:

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/configure-custom-ee-in-aap.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**What this does**:
1. Creates "Quay Custom EE Registry" credential in AAP
2. Creates "Custom OCP4 EE" execution environment (pulls from Quay)
3. Sets custom EE as default for Default organization
4. Triggers test project sync to verify authentication works

**Expected Duration**: 2-3 minutes

**Success Indicators**:
```
✅ Quay registry credential created
✅ Custom execution environment created (ID: 5)
✅ Default organization updated
✅ Project Sync Status: successful
```

---

### Step 4: Verify in AAP Web UI

1. **Log into AAP**: https://aap.sandbox3377.opentlc.com
   - Username: `admin`
   - Password: `<automationgateway_admin_password>`

2. **Verify Execution Environment**:
   - Navigate: **Administration** → **Execution Environments**
   - Find: **Custom OCP4 EE**
   - Check:
     - ✅ Image: `quay.io/takinosh/ocp4-aap-execution-environment:latest`
     - ✅ Pull: Always
     - ✅ Credential: Quay Custom EE Registry

3. **Verify Default Organization**:
   - Navigate: **Access** → **Organizations** → **Default**
   - Check: **Default Execution Environment** = **Custom OCP4 EE**

4. **Test Project Sync**:
   - Navigate: **Resources** → **Projects** → **ocp4-disconnected-helper**
   - Click: **Sync** button
   - Verify: ✅ **Successful** status (no registry auth errors)

---

## 📋 Quick Reference

### Check Build Status
```bash
# Verify image exists locally
podman images | grep ocp4-aap-execution-environment

# Verify image in Quay
curl -s https://quay.io/api/v1/repository/takinosh/ocp4-aap-execution-environment \
  | jq '.tags[].name'
```

### Rebuild EE (After Credential Rotation)
```bash
# 1. Update credentials
ansible-vault edit extra_vars/rhel-subscription-secrets.yml

# 2. Rebuild and republish
ansible-playbook -i inventory/ibm-cloud.yml playbooks/build-custom-ee.yml \
  -e@extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass

# AAP auto-pulls new image on next project sync (Pull: Always)
```

### Manual Quay Authentication Test
```bash
# Test Quay login
podman login quay.io
# Username: takinosh
# Password: <your-quay-password>

# Pull image manually
podman pull quay.io/takinosh/ocp4-aap-execution-environment:latest

# Inspect image
podman inspect quay.io/takinosh/ocp4-aap-execution-environment:latest
```

---

## ⚠️ Troubleshooting

### Issue: ansible-builder not found

**Solution**:
```bash
pip3 install --user ansible-builder
export PATH="$HOME/.local/bin:$PATH"
```

---

### Issue: Quay push fails with "unauthorized"

**Symptom**:
```
Error: unauthorized: access to the requested resource is not authorized
```

**Solution**:
```bash
# Re-authenticate to Quay
podman login quay.io
# Username: takinosh
# Password: YOUR_QUAY_PASSWORD

# Verify login
podman login --get-login quay.io
```

---

### Issue: AAP project sync still fails after custom EE

**Diagnosis**:
```bash
# 1. Verify custom EE is actually being used
curl -k -u admin:<admin_password> \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/organizations/1/ \
  | jq '.default_environment'

# 2. Check project uses Default org
curl -k -u admin:<admin_password> \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/projects/<PROJECT_ID>/ \
  | jq '.organization'
```

**Solution**: Ensure custom EE is set as organization default (not just created)

---

## 📊 Architecture Flow

```
┌─────────────────────────────────────────────┐
│ /home/vpcuser/ocp4-aap-execution-environment│
│ ├─ execution-environment.yml (modified)     │
│ └─ files/requirements.yml                   │
└──────────────────┬──────────────────────────┘
                   │
                   ▼ ansible-builder build --build-arg
┌─────────────────────────────────────────────┐
│ Container Image                              │
│ ├─ Base: registry.redhat.io/aap-25/ee-min  │
│ ├─ Ansible collections installed            │
│ └─ registry.redhat.io auth configured       │
└──────────────────┬──────────────────────────┘
                   │
                   ▼ podman push
┌─────────────────────────────────────────────┐
│ quay.io/takinosh/ocp4-aap-execution-environment│
│ ├─ Tag: latest                               │
│ └─ Visibility: Private (or public)          │
└──────────────────┬──────────────────────────┘
                   │
                   ▼ AAP pulls
┌─────────────────────────────────────────────┐
│ AAP 2.6                                      │
│ ├─ Credential: Quay Custom EE Registry      │
│ ├─ EE: Custom OCP4 EE                       │
│ └─ Default Organization → Custom OCP4 EE    │
└──────────────────┬──────────────────────────┘
                   │
                   ▼ Project syncs
┌─────────────────────────────────────────────┐
│ ✅ ocp4-disconnected-helper project         │
│ └─ Sync: Successful (no registry errors)   │
└─────────────────────────────────────────────┘
```

---

## 📚 Related Documentation

- [ADR 0029](adrs/0029-custom-execution-environment-for-aap-registry-authentication.md)
- [Custom EE Quick Start Guide](CUSTOM_EE_GUIDE.md)
- [AAP Post-Installation](AAP_POST_INSTALLATION.md)
- [AAP Project Import Guide](AAP_PROJECT_IMPORT_GUIDE.md)

---

## ✅ Checklist

Before proceeding, ensure:

- [ ] Quay credentials configured in `extra_vars/rhel-subscription-secrets.yml`
- [ ] Red Hat registry credentials configured (already done for AAP installation)
- [ ] ansible-builder installed (`pip install ansible-builder`)
- [ ] Podman running (`podman --version`)
- [ ] AAP 2.6 accessible at `https://aap.sandbox3377.opentlc.com`

---

**Ready to execute**: Run Step 2 (Build) and Step 3 (Configure AAP) commands above.
