# ADR 0027: Red Hat Subscription Management with Activation Keys

**Status:** Accepted  
**Date:** 2026-06-04  
**Deciders:** Platform Team  
**Related:** ADR 0009 (Secret Management), ADR 0026 (RHEL Base for AAP)

## Context

AAP 2.6 deployment requires RHEL 9 systems to be registered with Red Hat Subscription Management (RHSM) to access:
- Base RHEL 9 repositories (baseos, appstream)
- Ansible Automation Platform 2.6 repositories
- Container images from registry.redhat.io

**Authentication Methods**:
1. **Username/Password** - Interactive, credentials in environment variables
2. **Activation Keys** - Non-interactive, tied to organization ID

## Decision

**Use Red Hat Activation Keys for all automated RHEL registration**, not username/password.

### Storage Location

Activation keys shall be stored in **Ansible Vault** (encrypted):

```
extra_vars/rhel-subscription-secrets.yml  (encrypted with ansible-vault)
```

### Required Secrets

```yaml
# extra_vars/rhel-subscription-secrets.yml (encrypted)
rhsm_org_id: "1234567"
rhsm_activationkey: "aap-rhel9-key"
```

### Playbook Usage

```yaml
# playbooks/deploy-aap.yml
- name: Register with Red Hat (activation key)
  community.general.redhat_subscription:
    state: present
    org_id: "{{ rhsm_org_id }}"
    activationkey: "{{ rhsm_activationkey }}"
  when: "'Overall Status: Current' not in subscription_status.stdout"
  no_log: true
```

### Execution

```bash
# Run playbook with vault password
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml \
  --vault-password-file ~/.vault_pass \
  -e @extra_vars/rhel-subscription-secrets.yml
```

## Rationale

### Why Activation Keys Over Username/Password?

| Factor | Username/Password | Activation Key |
|--------|-------------------|----------------|
| **Security** | ❌ Exposes personal credentials | ✅ Scoped to organization |
| **Automation** | ⚠️ Requires MFA bypass | ✅ No MFA conflicts |
| **Audit Trail** | ⚠️ Personal account actions | ✅ Service-level tracking |
| **Rotation** | ❌ Breaks automation | ✅ Rotate key without code changes |
| **Revocation** | ❌ Disables entire account | ✅ Revoke key independently |
| **Best Practice** | ❌ Red Hat discourages | ✅ **Red Hat recommended** |

### Red Hat Best Practices

From [Red Hat Customer Portal](https://access.redhat.com/articles/1378093):
> "Activation keys are the recommended method for registering systems in automated or large-scale deployments. They provide better security, auditing, and lifecycle management compared to username/password authentication."

## Consequences

### Positive
- ✅ **No personal credentials in automation** - activation keys are service accounts
- ✅ **MFA-compatible** - activation keys bypass MFA requirements
- ✅ **Role-based access** - keys can be scoped to specific subscriptions
- ✅ **Better audit trail** - subscription usage tracked by key name
- ✅ **Easy rotation** - create new key, update vault, delete old key
- ✅ **Compliant with security standards** - no plaintext passwords

### Negative
- ⚠️ Requires Red Hat organization admin access to create keys
- ⚠️ One-time setup overhead (create key in Customer Portal)

## Implementation

### Step 1: Create Activation Key in Red Hat Customer Portal

1. **Login**: https://access.redhat.com/management/activation_keys
2. **Create New Key**:
   - Name: `aap-rhel9-automation`
   - Description: `AAP 2.6 RHEL 9 VM registration`
   - Service Level: `Premium` (or your org's SLA)
   - Usage: `Development/Test` or `Production`
3. **Attach Subscriptions**:
   - RHEL Server subscription
   - Ansible Automation Platform subscription
4. **Copy**:
   - Organization ID (e.g., `1234567`)
   - Activation Key (e.g., `aap-rhel9-automation`)

### Step 2: Create Vault File

```bash
# Create secrets file
cat > extra_vars/rhel-subscription-secrets.yml << 'EOF'
---
# Red Hat Subscription Management Credentials
# WARNING: This file should be encrypted with ansible-vault

rhsm_org_id: "YOUR_ORG_ID_HERE"
rhsm_activationkey: "YOUR_ACTIVATION_KEY_HERE"
EOF

# Encrypt with ansible-vault
ansible-vault encrypt extra_vars/rhel-subscription-secrets.yml

# Save vault password securely
echo "YOUR_VAULT_PASSWORD" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

### Step 3: Create Vault Password File (Optional but Recommended)

```bash
# Option 1: Vault password file (for automation)
echo "YOUR_VAULT_PASSWORD" > ~/.vault_pass
chmod 600 ~/.vault_pass

# Option 2: Environment variable
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass

# Option 3: Interactive (manual runs)
# Omit --vault-password-file, use --ask-vault-pass instead
```

### Step 4: Update Playbooks

All playbooks requiring RHEL registration should:

1. Load vault file: `-e @extra_vars/rhel-subscription-secrets.yml`
2. Use activation key method (already in `playbooks/deploy-aap.yml`)
3. Set `no_log: true` on registration tasks

### Step 5: Update Documentation

```bash
# playbooks/deploy-aap.yml execution becomes:
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml \
  --vault-password-file ~/.vault_pass \
  -e @extra_vars/rhel-subscription-secrets.yml
```

## File Structure

```
ocp4-disconnected-helper/
├── extra_vars/
│   ├── rhel-subscription-secrets.yml        # ✅ Encrypted (ansible-vault)
│   └── rhel-subscription-secrets.yml.example  # 📄 Template (plaintext, safe to commit)
├── .gitignore
│   └── extra_vars/*-secrets.yml             # ✅ Exclude actual secrets
└── playbooks/
    └── deploy-aap.yml                       # Uses vault variables
```

## Example Template (Safe to Commit)

```yaml
# extra_vars/rhel-subscription-secrets.yml.example
---
# Red Hat Subscription Management Credentials
# Copy this file to rhel-subscription-secrets.yml and fill in your values
# Then encrypt with: ansible-vault encrypt rhel-subscription-secrets.yml

# Organization ID from: https://access.redhat.com/management/activation_keys
rhsm_org_id: "YOUR_ORG_ID"

# Activation key name (create at URL above)
rhsm_activationkey: "YOUR_ACTIVATION_KEY"

# Optional: Override default auto-attach behavior
# rhsm_auto_attach: true

# Optional: Force re-registration (for testing)
# rhsm_force_register: false
```

## Migration from Username/Password

For existing deployments using username/password:

```bash
# Old method (deprecated)
export RHSM_USERNAME='user@example.com'
export RHSM_PASSWORD='password123'

# New method (recommended)
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml \
  --vault-password-file ~/.vault_pass \
  -e @extra_vars/rhel-subscription-secrets.yml
```

## Security Considerations

### Vault Password Storage

**Development/Lab**:
```bash
# File-based (convenient for local development)
echo "dev-vault-pass-2026" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

**Production/CI/CD**:
```bash
# Environment variable (no file on disk)
export ANSIBLE_VAULT_PASSWORD="$(cat /secure/path/vault-pass)"

# Or use external secret manager
export ANSIBLE_VAULT_PASSWORD="$(vault read -field=password secret/ansible/vault)"
```

### Activation Key Rotation

```bash
# 1. Create new key in Red Hat Customer Portal
# 2. Update vault file
ansible-vault edit extra_vars/rhel-subscription-secrets.yml

# 3. Test with new key
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml \
  --vault-password-file ~/.vault_pass \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --check

# 4. Deactivate old key in Customer Portal
```

## Troubleshooting

### Issue: Vault Decryption Failed

```bash
# Check vault password
cat ~/.vault_pass

# Verify vault file is encrypted
head -1 extra_vars/rhel-subscription-secrets.yml
# Should show: $ANSIBLE_VAULT;1.1;AES256

# Re-encrypt if needed
ansible-vault decrypt extra_vars/rhel-subscription-secrets.yml
ansible-vault encrypt extra_vars/rhel-subscription-secrets.yml
```

### Issue: Activation Key Invalid

```bash
# Verify key exists in Customer Portal
# https://access.redhat.com/management/activation_keys

# Test registration manually
ssh ansible@192.168.122.72
sudo subscription-manager register \
  --org=YOUR_ORG_ID \
  --activationkey=YOUR_KEY
```

### Issue: Subscriptions Not Attached

```bash
# Check available subscriptions
sudo subscription-manager list --available

# Manually attach (for troubleshooting only)
sudo subscription-manager attach --pool=POOL_ID

# Fix activation key subscription assignment in Customer Portal
```

## Related Documentation

- [Red Hat Activation Keys Guide](https://access.redhat.com/articles/1378093)
- [Subscription Manager Activation Keys](https://access.redhat.com/documentation/en-us/red_hat_subscription_management/1/html/rhsm/activation_keys)
- [Ansible Vault Documentation](https://docs.ansible.com/ansible/latest/user_guide/vault.html)
- [community.general.redhat_subscription Module](https://docs.ansible.com/ansible/latest/collections/community/general/redhat_subscription_module.html)

## Updates to Related ADRs

This ADR supersedes username/password authentication mentioned in:
- ✅ Update ADR 0009 to include RHEL subscription secrets
- ✅ Update ADR 0026 to reference activation key requirement
- ✅ Update `docs/AAP_DEPLOYMENT_GUIDE.md` with activation key instructions
- ✅ Update `docs/AAP_DEPLOYMENT_SUMMARY.md` to prefer activation keys

## References

- Red Hat KB: [Using Activation Keys](https://access.redhat.com/articles/1378093)
- Red Hat KB: [Subscription Manager Best Practices](https://access.redhat.com/solutions/3490881)
- Ansible Module: [community.general.redhat_subscription](https://docs.ansible.com/ansible/latest/collections/community/general/redhat_subscription_module.html)
