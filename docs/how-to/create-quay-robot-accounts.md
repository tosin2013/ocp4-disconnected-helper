---
layout: default
title: Create Quay Robot Accounts
parent: How-To Guides
nav_order: 8
---


**Best Practice**: Use robot accounts instead of personal credentials for automated builds and AAP authentication.

---

## Why Robot Accounts?

✅ **Scoped Permissions**: Limit access to specific repositories only  
✅ **No Password Expiration**: Token-based authentication (doesn't expire)  
✅ **Audit Trail**: Separate from personal account activities  
✅ **Revocable**: Can be deleted without affecting personal account  
✅ **Security**: No 2FA complications, designed for automation  

---

## Step 1: Create Robot Account in Quay

### Via Quay Web UI

1. **Navigate to Repository**:
   - Go to: https://quay.io/repository/takinosh/ocp4-aap-execution-environment
   - (Or create the repository first if it doesn't exist)

2. **Access Robot Accounts**:
   - Click on repository name → **Settings** (gear icon)
   - Left sidebar → **Robot Accounts**

3. **Create New Robot Account**:
   - Click **Create Robot Account** button
   - Name: `aap_builder` (or your preferred name)
   - Description: "Automated builds and AAP execution environment pulls"

4. **Set Permissions**:
   - Repository: `ocp4-aap-execution-environment`
   - Permission: **Write** (needed for pushing images)
   - Click **Add permissions**

5. **Save Robot Account**:
   - Click **Create Robot Account**
   - **IMPORTANT**: Copy the robot token immediately (shown only once)

6. **Robot Account Credentials**:
   - **Username**: `takinosh+aap_builder`
   - **Token**: `eyJhbGciOiJSUzI1NiIsInR5cCI6...` (long string)

---

## Step 2: Configure Robot Account in Secrets File

Edit your secrets file:

```bash
ansible-vault edit extra_vars/rhel-subscription-secrets.yml
```

Add the robot account credentials:

```yaml
# ============================================================
# Quay.io Robot Account (Recommended for Automation)
# ============================================================
# Robot Username Format: {username}+{robot_name}
quay_username: "takinosh+aap_builder"

# Robot Token (NOT a password - this is a long JWT-like string)
# Copy from Quay UI when creating robot account
quay_password: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6Ik..."

# Optional: Quay API token (if using API operations)
# quay_api_token: "YOUR_QUAY_API_TOKEN"
```

**Save and exit** (`:wq` in vim).

---

## Step 3: Test Robot Account Authentication

Test the robot account before building:

```bash
# Test podman login with robot account
echo "YOUR_ROBOT_TOKEN" | podman login quay.io \
  --username takinosh+aap_builder \
  --password-stdin

# Verify login
podman login --get-login quay.io
# Should output: takinosh+aap_builder

# Test push access (optional - creates a test tag)
podman pull registry.access.redhat.com/ubi9/ubi-minimal:latest
podman tag registry.access.redhat.com/ubi9/ubi-minimal:latest \
  quay.io/takinosh/ocp4-aap-execution-environment:test
podman push quay.io/takinosh/ocp4-aap-execution-environment:test

# Cleanup test tag
podman rmi quay.io/takinosh/ocp4-aap-execution-environment:test
```

**Expected Success**:
```
Login Succeeded!
Getting image source signatures
Copying blob ...
✓ Successfully pushed to quay.io
```

---

## Step 4: Create Separate Robot for AAP (Optional but Recommended)

For security best practices, use **two separate robot accounts**:

1. **`aap_builder` (Write permissions)**: For building and pushing images
   - Used by: `playbooks/build-custom-ee.yml`
   - Permissions: Read + Write

2. **`aap_puller` (Read-only)**: For AAP to pull images
   - Used by: AAP execution environment credential
   - Permissions: Read only

### Create AAP Puller Robot

1. **In Quay UI** → Robot Accounts → **Create Robot Account**
   - Name: `aap_puller`
   - Description: "AAP execution environment image pulls"

2. **Set Permissions**:
   - Repository: `ocp4-aap-execution-environment`
   - Permission: **Read** (pull-only access)

3. **Copy Credentials**:
   - Username: `takinosh+aap_puller`
   - Token: `eyJhbGciOiJSUzI1NiIsInR5cCI6...`

4. **Update AAP Configuration**:

In `playbooks/configure-custom-ee-in-aap.yml`, you can either:

**Option A: Use same robot for build and pull** (simpler):
```yaml
# Uses quay_username and quay_password from secrets file
# (aap_builder has write, so it can also read)
```

**Option B: Use separate puller robot** (more secure):

Add to `extra_vars/rhel-subscription-secrets.yml`:
```yaml
# AAP Pull-Only Robot (Read permissions)
aap_quay_username: "takinosh+aap_puller"
aap_quay_password: "PULLER_ROBOT_TOKEN_HERE"
```

Then modify `configure-custom-ee-in-aap.yml`:
```yaml
inputs:
  host: "quay.io"
  username: "{{ aap_quay_username | default(quay_username) }}"
  password: "{{ aap_quay_password | default(quay_password) }}"
```

---

## Step 5: Robot Account Token Security

### Storing Robot Tokens

✅ **DO**:
- Store in Ansible Vault encrypted files
- Use separate robots for build vs. pull
- Rotate tokens periodically (quarterly)
- Audit robot account activity logs

❌ **DON'T**:
- Commit unencrypted tokens to git
- Share tokens across multiple services
- Use personal account credentials for automation
- Use write-access robots when read-only is sufficient

### Token Rotation Process

When rotating robot tokens:

1. **Generate New Token**:
   - Quay UI → Robot Accounts → `aap_builder` → **Regenerate Token**
   - Copy new token

2. **Update Secrets File**:
   ```bash
   ansible-vault edit extra_vars/rhel-subscription-secrets.yml
   # Update quay_password with new token
   ```

3. **Rebuild EE** (only if credentials embedded):
   ```bash
   ansible-playbook playbooks/build-custom-ee.yml \
     -e@extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass
   ```

4. **Update AAP Credential** (if using separate puller):
   - AAP UI → Resources → Credentials → Quay Custom EE Registry
   - Update password field with new token

---

## Robot Account Permissions Reference

### For Building and Pushing Images

**Robot**: `aap_builder`  
**Permissions**: Read + Write  
**Used By**: `playbooks/build-custom-ee.yml`  
**Justification**: Needs write access to push built images to Quay  

**Recommended**: Yes (required for automation)

---

### For AAP Pulling Images

**Robot**: `aap_puller` (optional, can reuse `aap_builder`)  
**Permissions**: Read only  
**Used By**: AAP execution environment pulls  
**Justification**: AAP only needs to pull images, not push  

**Recommended**: Yes (security best practice - least privilege)

---

## Troubleshooting

### Issue: Robot account login fails with "unauthorized"

**Symptom**:
```
Error: unauthorized: Could not find robot with username: takinosh+aap_builder
```

**Solutions**:
1. Verify robot account exists in Quay UI
2. Check username format is correct: `{username}+{robot_name}` (not `{username}/{robot_name}`)
3. Ensure token was copied correctly (no extra spaces/newlines)

---

### Issue: Build succeeds but push fails with "insufficient_scope"

**Symptom**:
```
Error: insufficient_scope: authorization failed
```

**Solutions**:
1. Verify robot has **Write** permissions (not just Read)
2. Check robot permissions are for the correct repository
3. Regenerate robot token and try again

---

### Issue: AAP cannot pull image with robot account

**Symptom**:
AAP project sync fails with "unauthorized: authentication required"

**Solutions**:
1. Verify Quay credential in AAP uses robot username `takinosh+aap_builder`
2. Check robot token is entered correctly in AAP credential password field
3. Verify robot has at least **Read** permission on repository
4. Test manual pull from AAP node:
   ```bash
   ssh ansible@192.168.10.20
   echo "ROBOT_TOKEN" | podman login quay.io --username takinosh+aap_builder --password-stdin
   podman pull quay.io/takinosh/ocp4-aap-execution-environment:latest
   ```

---

## Verification Checklist

Before proceeding with build:

- [ ] Robot account created in Quay: `takinosh+aap_builder`
- [ ] Robot has **Write** permissions on `ocp4-aap-execution-environment` repository
- [ ] Robot token copied and saved securely
- [ ] Secrets file updated with robot username and token
- [ ] Secrets file encrypted with ansible-vault
- [ ] Test authentication succeeded: `podman login quay.io`
- [ ] (Optional) Separate puller robot created: `takinosh+aap_puller`

---

## Quick Reference

### Robot Account Format
```
Username: {quay_username}+{robot_name}
Example:  takinosh+aap_builder

Token:    eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtp...
          (Long JWT-like string, ~800+ characters)
```

### Test Authentication
```bash
# Test robot login
echo "ROBOT_TOKEN" | podman login quay.io \
  --username takinosh+aap_builder --password-stdin

# Verify current login
podman login --get-login quay.io
```

### Update Secrets File
```bash
ansible-vault edit extra_vars/rhel-subscription-secrets.yml
```

```yaml
quay_username: "takinosh+aap_builder"
quay_password: "YOUR_ROBOT_TOKEN_HERE"
```

---

**Next Steps**: After robot account is configured, proceed with build:

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/build-custom-ee.yml \
  -e@extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass
```
