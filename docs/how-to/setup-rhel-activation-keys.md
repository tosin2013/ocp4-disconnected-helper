---
layout: default
title: Setup RHEL Activation Keys
parent: How-To Guides
nav_order: 4
---


**Quick Reference**: ADR 0027 - RHEL Subscription Activation Keys

This guide shows how to create and use Red Hat activation keys for automated RHEL registration in AAP deployment.

---

## Why Activation Keys?

✅ **Recommended by Red Hat** for automation  
✅ No MFA conflicts  
✅ Better security (service account, not personal credentials)  
✅ Easy rotation and audit trail  
❌ Username/password not recommended for automation

---

## Step 1: Create Activation Key

### Navigate to Red Hat Customer Portal

1. Go to: https://access.redhat.com/management/activation_keys
2. Click **"New"** button

### Fill in Activation Key Details

| Field | Value | Notes |
|-------|-------|-------|
| **Name** | `aap-rhel9-automation` | Use descriptive name |
| **Description** | `AAP 2.6 RHEL 9 VM registration` | Optional but recommended |
| **Service Level** | `Premium` | Match your subscription SLA |
| **Usage** | `Development/Test` or `Production` | Based on environment |
| **Auto-attach** | ✅ Enabled | Automatically attach subscriptions |

### Attach Subscriptions

Click **"Subscriptions"** tab and attach:
- ✅ Red Hat Enterprise Linux Server
- ✅ Ansible Automation Platform

### Copy Credentials

After saving, copy:
1. **Organization ID** (top of page, e.g., `1234567`)
2. **Activation Key Name** (e.g., `aap-rhel9-automation`)

---

## Step 2: Create Vault File

### Copy Template

```bash
cd /home/vpcuser/ocp4-disconnected-helper
cp extra_vars/rhel-subscription-secrets.yml.example \
   extra_vars/rhel-subscription-secrets.yml
```

### Edit with Your Values

```bash
vi extra_vars/rhel-subscription-secrets.yml
```

Replace placeholders:

```yaml
---
# Red Hat Subscription Management Credentials

rhsm_org_id: "1234567"  # Your Organization ID
rhsm_activationkey: "aap-rhel9-automation"  # Your Key Name

# AAP Credentials (change defaults!)
aap_admin_password: "YourSecurePassword123!"
aap_pg_password: "YourSecurePostgresPassword123!"
```

### Encrypt with Ansible Vault

```bash
# Create vault password file
echo "your-secure-vault-password-here" > ~/.vault_pass
chmod 600 ~/.vault_pass

# Encrypt secrets file
ansible-vault encrypt extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Result**: File is now encrypted and safe to store (but still excluded from git).

---

## Step 3: Deploy AAP with Activation Key

### Run Deployment Playbook

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml \
  --vault-password-file ~/.vault_pass \
  -e @extra_vars/rhel-subscription-secrets.yml
```

**What happens**:
1. Playbook decrypts vault file using `~/.vault_pass`
2. Loads `rhsm_org_id` and `rhsm_activationkey` variables
3. Registers RHEL 9 VM using activation key (no username/password needed)
4. Proceeds with AAP installation

---

## Vault Management

### View Encrypted File

```bash
ansible-vault view extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

### Edit Encrypted File

```bash
ansible-vault edit extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

### Change Vault Password

```bash
ansible-vault rekey extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

### Decrypt (Not Recommended - Only for Troubleshooting)

```bash
# Decrypt
ansible-vault decrypt extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass

# After fixing, re-encrypt immediately!
ansible-vault encrypt extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

---

## Security Best Practices

### Vault Password Storage

| Environment | Method | Security Level |
|-------------|--------|----------------|
| **Local Dev** | `~/.vault_pass` file | Medium (chmod 600) |
| **CI/CD** | Environment variable | High (ephemeral) |
| **Production** | HashiCorp Vault | Very High |

### Activation Key Rotation

**Recommended**: Rotate activation keys every 90 days

```bash
# 1. Create new key in Customer Portal
# 2. Edit vault file
ansible-vault edit extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass

# 3. Update rhsm_activationkey value
# 4. Save and test
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml \
  --vault-password-file ~/.vault_pass \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --check

# 5. Delete old key in Customer Portal
```

### Git Safety

✅ `.gitignore` already excludes:
- `extra_vars/*-secrets.yml` (your encrypted file)
- `~/.vault_pass` (your vault password)

✅ Safe to commit:
- `extra_vars/rhel-subscription-secrets.yml.example` (template)

❌ Never commit:
- `extra_vars/rhel-subscription-secrets.yml` (even if encrypted)
- Vault password files

---

## Troubleshooting

### Issue: "Vault password incorrect"

```bash
# Check vault password
cat ~/.vault_pass

# Verify file is encrypted
head -1 extra_vars/rhel-subscription-secrets.yml
# Should show: $ANSIBLE_VAULT;1.1;AES256

# If corrupted, decrypt and re-encrypt
ansible-vault decrypt extra_vars/rhel-subscription-secrets.yml
ansible-vault encrypt extra_vars/rhel-subscription-secrets.yml
```

### Issue: "Activation key invalid"

```bash
# Verify key exists in Red Hat Customer Portal
# https://access.redhat.com/management/activation_keys

# Check if key has correct subscriptions attached
# Test registration manually:
ssh ansible@192.168.122.72
sudo subscription-manager register \
  --org=YOUR_ORG_ID \
  --activationkey=YOUR_KEY
```

### Issue: "No subscriptions attached"

```bash
# SSH to VM
ssh ansible@192.168.122.72

# Check subscription status
sudo subscription-manager status

# List consumed subscriptions
sudo subscription-manager list --consumed

# If empty, check activation key configuration:
# https://access.redhat.com/management/activation_keys
# Verify subscriptions are attached to the key
```

### Issue: "Variables not loaded"

```bash
# Verify vault file syntax
ansible-vault view extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass | yaml-lint -

# Check if variables are being passed
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml \
  --vault-password-file ~/.vault_pass \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --list-tasks -vv
```

---

## Alternative: Environment Variables (Not Recommended)

If you cannot use activation keys (e.g., no org admin access):

```bash
# Export activation key as environment variables
export RHSM_ORG_ID='1234567'
export RHSM_ACTIVATIONKEY='aap-rhel9-automation'

# Run playbook (will use env vars as fallback)
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml
```

**Warning**: Environment variables are less secure than vault files. Use only for testing.

---

## Complete Example Workflow

```bash
# 1. Create activation key in Red Hat Customer Portal
#    https://access.redhat.com/management/activation_keys
#    Note: Organization ID and Activation Key Name

# 2. Create vault file from template
cd /home/vpcuser/ocp4-disconnected-helper
cp extra_vars/rhel-subscription-secrets.yml.example \
   extra_vars/rhel-subscription-secrets.yml

# 3. Edit with your credentials
vi extra_vars/rhel-subscription-secrets.yml
# Set: rhsm_org_id, rhsm_activationkey, aap_admin_password

# 4. Create vault password
echo "my-secure-vault-password-2026" > ~/.vault_pass
chmod 600 ~/.vault_pass

# 5. Encrypt secrets file
ansible-vault encrypt extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass

# 6. Deploy AAP
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml \
  --vault-password-file ~/.vault_pass \
  -e @extra_vars/rhel-subscription-secrets.yml

# 7. Access AAP Web UI
# https://192.168.122.72
# Username: admin
# Password: <value from aap_admin_password>
```

**Total Time**: ~25 minutes (5 min setup + 20 min deployment)

---

## References

- **ADR 0027**: RHEL Subscription Activation Keys
- **ADR 0009**: Secret Management Strategy
- **Red Hat KB**: [Using Activation Keys](https://access.redhat.com/articles/1378093)
- **Ansible Vault**: [Documentation](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- **Customer Portal**: [Activation Keys Management](https://access.redhat.com/management/activation_keys)

---

## Quick Reference

| Action | Command |
|--------|---------|
| **Create vault file** | `cp extra_vars/rhel-subscription-secrets.yml.example extra_vars/rhel-subscription-secrets.yml` |
| **Edit vault file** | `ansible-vault edit extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass` |
| **View vault file** | `ansible-vault view extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass` |
| **Encrypt file** | `ansible-vault encrypt extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass` |
| **Deploy AAP** | `ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml --vault-password-file ~/.vault_pass -e @extra_vars/rhel-subscription-secrets.yml` |
| **Manage keys** | https://access.redhat.com/management/activation_keys |
