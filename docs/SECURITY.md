# Security Guidelines

## Credential Management

### Never Commit Credentials to Git

**Prohibited content in Git commits:**
- Service account credentials (Red Hat, AWS, Azure, Quay, IBM Cloud)
- JWT tokens, API keys, authentication tokens
- Passwords (admin, database, registry, vault)
- Private keys, TLS certificates (except `.example` suffixes)
- Pull secrets, kubeconfig files
- AAP installer inventory files with real credentials

### Pre-Commit Protection

A Git pre-commit hook (`.git/hooks/pre-commit`) automatically scans for credential patterns before allowing commits.

**Detected patterns:**
- Red Hat service accounts: `[0-9]{8}|[a-zA-Z0-9_-]+`
- JWT tokens: `eyJ[a-zA-Z0-9_-]*...`
- Passwords: `password='actual-value'`
- AWS keys: `AKIA[0-9A-Z]{16}`
- Private keys: `BEGIN PRIVATE KEY`

**If the hook blocks your commit:**
1. **Replace credentials with placeholders:**
   ```
   # Bad (real credential)
   registry_username='12216224|ansible-execution-environment'

   # Good (placeholder)
   registry_username='<YOUR-ORG-ID>|<YOUR-SERVICE-ACCOUNT-NAME>'
   ```

2. **Store real credentials securely** (see below)

3. **Do NOT bypass with `--no-verify`** (except in documented emergencies)

### Safe Credential Storage

#### 1. Ansible Vault (Recommended for Automation)

**Encrypt sensitive variables:**
```bash
# Create encrypted vault file
ansible-vault create extra_vars/rhel-subscription-secrets.yml

# Edit encrypted file
ansible-vault edit extra_vars/rhel-subscription-secrets.yml

# Use in playbooks
ansible-playbook playbook.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Vault password file protection:**
```bash
# Create vault password file
echo "your-vault-password" > ~/.vault_pass
chmod 600 ~/.vault_pass
```

**Never commit:**
- Unencrypted `*-secrets.yml` files
- `.vault_pass` or `.vault_password` files

#### 2. Environment Variables (For Local Development)

```bash
# In ~/.bashrc or ~/.zshrc
export RH_REGISTRY_USERNAME='12216224|ansible-execution-environment'
export RH_REGISTRY_PASSWORD='eyJhbGci...'
export AAP_ADMIN_PASSWORD='...'

# Use in playbooks
registry_username: "{{ lookup('env', 'RH_REGISTRY_USERNAME') }}"
```

#### 3. AAP Installer Inventory (Deployment-Time Only)

**File:** `/opt/ansible-automation-platform/installer/inventory`

**Protection:**
```bash
# Set restrictive permissions
chmod 600 /opt/ansible-automation-platform/installer/inventory
chown ansible:ansible /opt/ansible-automation-platform/installer/inventory
```

**Never commit to Git:**
- Added to `.gitignore`: `**/installer/inventory`
- Only commit `.example` versions with placeholders

### Credential Rotation

**Red Hat Service Accounts:**
- Rotation schedule: Every 90-180 days
- Process:
  1. Generate new service account at https://access.redhat.com/terms-based-registry/
  2. Update Ansible Vault: `ansible-vault edit extra_vars/rhel-subscription-secrets.yml`
  3. Update AAP installer inventory
  4. Re-run AAP setup: `./setup.sh -i inventory`
  5. Verify project syncs work
  6. Revoke old service account

**AAP Passwords:**
- Rotation schedule: Every 90 days (or per security policy)
- Process documented in ADR-0028

## File Permissions

**Sensitive files must have restrictive permissions:**

```bash
# Vault password files
chmod 600 ~/.vault_pass

# SSH private keys
chmod 600 ~/.ssh/id_rsa

# AAP installer inventory
chmod 600 /opt/ansible-automation-platform/installer/inventory

# Ansible Vault files (even encrypted)
chmod 600 extra_vars/*-secrets.yml
```

## .gitignore Rules

The project `.gitignore` blocks common credential file patterns:

```gitignore
# Credentials - NEVER commit
.vault_password
*.vault_password
pull-secret.json
*pull-secret*
*.pem
*.key
*.crt
!*.crt.example

# Ansible Vault secrets
extra_vars/*-secrets.yml
!extra_vars/*-secrets.yml.example

# AAP installer inventory
**/installer/inventory
!**/installer/inventory.example
```

**Always commit `.example` versions** with placeholders for documentation.

## Incident Response

### If Credentials Are Committed

**Immediate actions:**

1. **Assume credentials are compromised** (public repository or not)

2. **Rotate credentials immediately:**
   ```bash
   # Revoke Red Hat service account
   # Visit: https://access.redhat.com/terms-based-registry/
   
   # Generate new service account
   # Update Ansible Vault and AAP inventory
   ```

3. **Remove from Git history:**
   ```bash
   # Use BFG Repo-Cleaner or git-filter-repo
   git filter-repo --path extra_vars/rhel-subscription-secrets.yml --invert-paths
   
   # Force push (if already pushed to remote)
   git push --force
   ```

4. **Notify security team** if credentials had access to production systems

5. **Review audit logs** for unauthorized access using compromised credentials

## Security Checklist

Before every deployment:

- [ ] All credentials in Ansible Vault or environment variables
- [ ] AAP installer inventory has `chmod 600` permissions
- [ ] `.vault_pass` file is NOT in Git
- [ ] Pre-commit hook is executable (`chmod +x .git/hooks/pre-commit`)
- [ ] No `*-secrets.yml` files in `git status` (unless `.example`)
- [ ] All documentation uses placeholder credentials
- [ ] Service account credentials rotated within last 90 days

## References

- **ADR-0031**: AAP Installer Registry Credential Configuration
- **ADR-0028**: AAP Multi-Node Password Architecture
- **ADR-0009**: Secrets Management Strategy
- [Ansible Vault Documentation](https://docs.ansible.com/ansible/latest/vault_guide/)
- [Red Hat Terms-Based Registry](https://access.redhat.com/terms-based-registry/)

## Contact

For security concerns or questions:
- Review ADRs in `docs/adrs/`
- Check PMB for incident history: `pmb.recall("security credentials")`
- Consult project maintainer
