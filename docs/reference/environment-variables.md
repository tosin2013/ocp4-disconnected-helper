# Environment Variables Reference

Complete reference for all environment variables used across the project.

---

## Libvirt / KVM Environment

### LIBVIRT_DEFAULT_URI

**Purpose**: Default libvirt connection URI

**Required**: Yes (for non-root libvirt operations)

**Default**: Not set (requires manual configuration)

**Valid Values**:
- `qemu:///system` - System-level libvirt (recommended)
- `qemu:///session` - User-level libvirt
- `qemu+ssh://user@host/system` - Remote libvirt connection

**Set in**:
```bash
# Temporary (current session)
export LIBVIRT_DEFAULT_URI="qemu:///system"

# Permanent (all sessions)
echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.bashrc
source ~/.bashrc
```

**Validation**:
```bash
echo $LIBVIRT_DEFAULT_URI
# Expected: qemu:///system

virsh list --all
# Should work without "permission denied" errors
```

**Troubleshooting**: See [LIBVIRT_PERMISSIONS.md](../LIBVIRT_PERMISSIONS.md)

---

### XDG_RUNTIME_DIR

**Purpose**: User runtime directory for Podman rootless containers

**Required**: Yes (for non-root Podman operations)

**Default**: Not set for root, `/run/user/$UID` for non-root users

**Valid Values**: `/run/user/$(id -u)`

**Set in**:
```bash
# Temporary
export XDG_RUNTIME_DIR=/run/user/$(id -u)

# Permanent
echo 'export XDG_RUNTIME_DIR=/run/user/$(id -u)' >> ~/.bashrc
```

**When needed**: When running Podman as non-root user

**Validation**:
```bash
echo $XDG_RUNTIME_DIR
# Expected: /run/user/1000 (or your UID)

podman ps
# Should work without errors
```

---

## Ansible Environment

### ANSIBLE_CONFIG

**Purpose**: Path to Ansible configuration file

**Required**: No (defaults to `./ansible.cfg` in project root)

**Default**: `./ansible.cfg`

**Valid Values**: Path to valid `ansible.cfg` file

**Set in**:
```bash
export ANSIBLE_CONFIG=/path/to/custom/ansible.cfg
```

**Project configuration**: `/home/vpcuser/ocp4-disconnected-helper/ansible.cfg`

---

### ANSIBLE_INVENTORY

**Purpose**: Default inventory file

**Required**: No (can use `-i` flag instead)

**Default**: Not set

**Valid Values**: Path to inventory file or directory

**Set in**:
```bash
export ANSIBLE_INVENTORY=inventory/ibm-cloud.yml
```

**Usage**:
```bash
# With environment variable
export ANSIBLE_INVENTORY=inventory/ibm-cloud.yml
ansible-playbook playbooks/site.yml

# With -i flag (overrides environment variable)
ansible-playbook -i inventory/local.yml playbooks/site.yml
```

---

### ANSIBLE_VAULT_PASSWORD_FILE

**Purpose**: Path to Ansible Vault password file

**Required**: No (can use `--vault-password-file` flag instead)

**Default**: Not set

**Valid Values**: Path to file containing vault password

**Set in**:
```bash
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass
```

**Security**: File should be `chmod 600` (readable only by owner)

**Usage**:
```bash
# With environment variable
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass
ansible-playbook playbooks/site.yml

# With flag (overrides environment variable)
ansible-playbook playbooks/site.yml --vault-password-file ~/.vault_pass
```

---

### ANSIBLE_ROLES_PATH

**Purpose**: Colon-separated list of role search paths

**Required**: No (defaults to `./roles`)

**Default**: `./roles:/usr/share/ansible/roles:/etc/ansible/roles`

**Set in**:
```bash
export ANSIBLE_ROLES_PATH=./roles:~/custom-roles
```

---

### ANSIBLE_COLLECTIONS_PATH

**Purpose**: Colon-separated list of collection search paths

**Required**: No (defaults to `~/.ansible/collections`)

**Default**: `~/.ansible/collections:/usr/share/ansible/collections`

**Set in**:
```bash
export ANSIBLE_COLLECTIONS_PATH=~/.ansible/collections:./collections
```

---

## AWS Environment (Let's Encrypt DNS-01)

### AWS_ACCESS_KEY_ID

**Purpose**: AWS access key for Route53 DNS manipulation

**Required**: Yes (if using Let's Encrypt with DNS-01 validation)

**Default**: Not set

**Valid Values**: AWS IAM access key ID (20 characters, starts with `AKIA`)

**Set in**:
```bash
export AWS_ACCESS_KEY_ID='<YOUR-AWS-ACCESS-KEY-ID>'
```

**Security**: Use IAM user with minimal Route53 permissions

**Required Permissions**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:GetChange"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": "arn:aws:route53:::hostedzone/Z1234567890ABC"
    }
  ]
}
```

---

### AWS_SECRET_ACCESS_KEY

**Purpose**: AWS secret key for Route53 DNS manipulation

**Required**: Yes (if using Let's Encrypt with DNS-01 validation)

**Default**: Not set

**Valid Values**: AWS IAM secret access key (40 characters)

**Set in**:
```bash
export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

**Security**: Never commit to Git, store in Ansible Vault or environment

---

### AWS_DEFAULT_REGION

**Purpose**: Default AWS region for Route53 operations

**Required**: No (Route53 is global)

**Default**: Not set

**Valid Values**: Any valid AWS region (e.g., `us-east-1`, `eu-west-1`)

**Set in**:
```bash
export AWS_DEFAULT_REGION=us-east-1
```

---

## Red Hat Subscription Environment

### RH_USERNAME

**Purpose**: Red Hat subscription username

**Required**: No (prefer using Ansible Vault)

**Default**: Not set

**Valid Values**: Red Hat account username

**Set in**:
```bash
export RH_USERNAME=your-rh-username
```

**Security**: Prefer `extra_vars/rhel-subscription-secrets.yml` (Ansible Vault) over environment variables

---

### RH_PASSWORD

**Purpose**: Red Hat subscription password

**Required**: No (prefer using Ansible Vault)

**Default**: Not set

**Valid Values**: Red Hat account password

**Set in**:
```bash
export RH_PASSWORD=your-rh-password
```

**Security**: **NEVER export in plaintext**. Use Ansible Vault or activation keys instead.

---

### RH_REGISTRY_USERNAME

**Purpose**: Red Hat container registry service account username

**Required**: Yes (for downloading OpenShift images)

**Default**: Not set

**Valid Values**: Format: `<org-id>|<service-account-name>`

**Set in**:
```bash
export RH_REGISTRY_USERNAME='<YOUR-ORG-ID>|<YOUR-SERVICE-ACCOUNT>'
```

**Obtain from**: [Red Hat Registry Service Accounts](https://access.redhat.com/terms-based-registry/)

---

### RH_REGISTRY_PASSWORD

**Purpose**: Red Hat container registry service account token

**Required**: Yes (for downloading OpenShift images)

**Default**: Not set

**Valid Values**: JWT token from Red Hat service account

**Set in**:
```bash
export RH_REGISTRY_PASSWORD='eyJhbGciOiJSUzUxMi...'
```

**Security**: Store in Ansible Vault, not plaintext environment

---

## Registry Environment

### REGISTRY_URL

**Purpose**: Target container registry URL

**Required**: No (can pass via playbook `-e` flag)

**Default**: Not set

**Valid Values**: Format: `hostname:port`

**Set in**:
```bash
export REGISTRY_URL=registry.example.com:8443
```

**Usage**:
```bash
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e target_registry=$REGISTRY_URL
```

---

### REGISTRY_USERNAME

**Purpose**: Container registry username for authentication

**Required**: No (can pass via playbook `-e` flag)

**Default**: `init` (Quay default)

**Set in**:
```bash
export REGISTRY_USERNAME=init
```

---

### REGISTRY_PASSWORD

**Purpose**: Container registry password for authentication

**Required**: No (can pass via playbook `-e` flag)

**Default**: Not set

**Set in**:
```bash
export REGISTRY_PASSWORD=SecurePassword123!
```

**Security**: Use secure password generation:
```bash
export REGISTRY_PASSWORD=$(openssl rand -base64 24)
```

---

## AAP Environment

### AAP_URL

**Purpose**: Ansible Automation Platform URL

**Required**: No (can pass via playbook `-e` flag)

**Default**: Not set

**Valid Values**: Format: `https://aap.example.com`

**Set in**:
```bash
export AAP_URL=https://aap.sandbox3377.opentlc.com
```

---

### AAP_USERNAME

**Purpose**: AAP Controller API username

**Required**: Yes (for AAP API operations)

**Default**: `admin`

**Set in**:
```bash
export AAP_USERNAME=admin
```

---

### AAP_PASSWORD

**Purpose**: AAP Controller API password

**Required**: Yes (for AAP API operations)

**Default**: Not set

**Set in**:
```bash
export AAP_PASSWORD=ControllerPassword123!
```

**Important**: This is the **Controller password** (`admin_password`), NOT the Gateway password (`automationgateway_admin_password`). See [ADR-0028](../adrs/0028-aap-multi-node-password-architecture.md).

---

### GATEWAY_PASSWORD

**Purpose**: AAP Gateway Web UI password

**Required**: Yes (for AAP Web UI login)

**Default**: Not set

**Set in**:
```bash
export GATEWAY_PASSWORD=GatewayPassword456!
```

**Important**: This is the **Gateway password** (`automationgateway_admin_password`) for Web UI login, different from Controller API password.

---

## oc-mirror Environment

### OC_MIRROR_LOG_LEVEL

**Purpose**: oc-mirror verbosity level

**Required**: No

**Default**: `info`

**Valid Values**: `debug`, `info`, `warn`, `error`

**Set in**:
```bash
export OC_MIRROR_LOG_LEVEL=debug
```

---

### OC_MIRROR_TIMEOUT

**Purpose**: oc-mirror operation timeout (seconds)

**Required**: No

**Default**: `3600` (1 hour)

**Valid Values**: Positive integer

**Set in**:
```bash
export OC_MIRROR_TIMEOUT=7200  # 2 hours
```

---

## Path Environment

### PATH

**Purpose**: Executable search path

**Required**: Yes (always set by system)

**Additions for this project**:
```bash
# Add oc, kubectl, oc-mirror to PATH
export PATH=$PATH:/usr/local/bin:/opt/openshift-install
```

**Verify OpenShift tools**:
```bash
which oc
which kubectl
which oc-mirror
```

---

## Proxy Environment (Optional)

### HTTP_PROXY / HTTPS_PROXY

**Purpose**: HTTP/HTTPS proxy for internet access

**Required**: No (only if behind corporate proxy)

**Valid Values**: Format: `http://proxy.example.com:3128`

**Set in**:
```bash
export HTTP_PROXY=http://proxy.example.com:3128
export HTTPS_PROXY=http://proxy.example.com:3128
```

---

### NO_PROXY

**Purpose**: Bypass proxy for specific domains

**Required**: No (only if using HTTP_PROXY/HTTPS_PROXY)

**Valid Values**: Comma-separated list of domains/IPs

**Set in**:
```bash
export NO_PROXY=localhost,127.0.0.1,192.168.10.0/24,.example.com
```

---

## Project-Specific Environment

### PROJECT_ROOT

**Purpose**: Project root directory

**Required**: No (convenience variable)

**Default**: `/home/vpcuser/ocp4-disconnected-helper`

**Set in**:
```bash
export PROJECT_ROOT=/home/vpcuser/ocp4-disconnected-helper
cd $PROJECT_ROOT
```

---

### DATA_DIR

**Purpose**: Data storage directory

**Required**: No (convenience variable)

**Default**: `/data`

**Set in**:
```bash
export DATA_DIR=/data
ls $DATA_DIR/oc-mirror
```

---

## Environment Setup Script

### Recommended Setup

Create `~/.project_env` with all required variables:

```bash
#!/bin/bash
# ~/.project_env - OpenShift Disconnected Helper Environment

# Libvirt
export LIBVIRT_DEFAULT_URI="qemu:///system"

# Podman
export XDG_RUNTIME_DIR=/run/user/$(id -u)

# Ansible
export ANSIBLE_CONFIG=/home/vpcuser/ocp4-disconnected-helper/ansible.cfg
export ANSIBLE_VAULT_PASSWORD_FILE=~/.vault_pass

# AWS (Let's Encrypt)
# export AWS_ACCESS_KEY_ID='<YOUR-AWS-ACCESS-KEY-ID>'
# export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
# export AWS_DEFAULT_REGION=us-east-1

# AAP
export AAP_URL=https://aap.sandbox3377.opentlc.com
export AAP_USERNAME=admin
# Passwords loaded from Ansible Vault, not exported here

# Project
export PROJECT_ROOT=/home/vpcuser/ocp4-disconnected-helper
export DATA_DIR=/data

# PATH
export PATH=$PATH:/usr/local/bin:/opt/openshift-install

# Change to project directory
cd $PROJECT_ROOT

echo "✓ Environment loaded for ocp4-disconnected-helper"
```

**Usage**:
```bash
# Load environment
source ~/.project_env

# Or add to ~/.bashrc for automatic loading
echo 'source ~/.project_env' >> ~/.bashrc
```

---

## Environment Validation

### Validate All Required Variables

```bash
#!/bin/bash
# scripts/validate-environment.sh

errors=0

# Check Libvirt
if [ -z "$LIBVIRT_DEFAULT_URI" ]; then
  echo "✗ LIBVIRT_DEFAULT_URI not set"
  errors=$((errors+1))
else
  echo "✓ LIBVIRT_DEFAULT_URI=$LIBVIRT_DEFAULT_URI"
fi

# Check Podman
if [ -z "$XDG_RUNTIME_DIR" ]; then
  echo "✗ XDG_RUNTIME_DIR not set"
  errors=$((errors+1))
else
  echo "✓ XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
fi

# Check Ansible Vault
if [ ! -f "$ANSIBLE_VAULT_PASSWORD_FILE" ]; then
  echo "✗ ANSIBLE_VAULT_PASSWORD_FILE not found: $ANSIBLE_VAULT_PASSWORD_FILE"
  errors=$((errors+1))
else
  echo "✓ ANSIBLE_VAULT_PASSWORD_FILE exists"
fi

# Check AWS (optional for Let's Encrypt)
if [ -n "$AWS_ACCESS_KEY_ID" ]; then
  echo "✓ AWS_ACCESS_KEY_ID set (Let's Encrypt available)"
else
  echo "⚠ AWS_ACCESS_KEY_ID not set (Let's Encrypt unavailable)"
fi

if [ $errors -eq 0 ]; then
  echo ""
  echo "✓ All required environment variables configured"
  exit 0
else
  echo ""
  echo "✗ $errors missing environment variables"
  exit 1
fi
```

**Run validation**:
```bash
chmod +x scripts/validate-environment.sh
./scripts/validate-environment.sh
```

---

## Security Best Practices

1. **Never commit environment variables to Git**:
   - Use `.gitignore` for `~/.project_env`
   - Use Ansible Vault for secrets

2. **Use Ansible Vault for passwords**:
   ```bash
   # Store in vault, not environment
   ansible-vault encrypt_string 'SecurePassword123!' --name 'registry_password'
   ```

3. **Rotate credentials regularly**:
   - Red Hat service accounts: Every 90 days
   - Registry passwords: Every 60 days
   - AAP passwords: Every 90 days

4. **Use service accounts over personal credentials**:
   - Red Hat Registry: Use service accounts, not personal account
   - AAP: Create dedicated automation accounts

5. **Limit credential scope**:
   - AWS IAM: Only Route53 permissions needed
   - Red Hat: Only pull permissions, not push

---

## Related Documentation

- [Playbook Parameter Reference](playbook-parameters.md)
- [Bootstrap Prerequisites Reference](bootstrap-prerequisites.md)
- [ADR-0009: Secret Management](../adrs/0009-secret-management.md)
- [LIBVIRT_PERMISSIONS.md](../LIBVIRT_PERMISSIONS.md)
