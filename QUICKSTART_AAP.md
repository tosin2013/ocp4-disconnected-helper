# AAP 2.6 Deployment - Quick Start

**5-Step Process** | **Total Time: ~25 minutes** | **Status: ✅ Ready**

---

## Prerequisites

- [x] RHEL 9.8 VM running (aap.ocp4.sandbox3377.opentlc.com)
- [x] SSH access: `ssh ansible@192.168.122.72`
- [x] Ansible collections installed (infra.aap_utilities:3.3.0)
- [ ] Red Hat activation key (create below)

---

## Step 1: Create Activation Key (1 min)

1. Go to: https://access.redhat.com/management/activation_keys
2. Click **New**
3. Fill in:
   - Name: `aap-rhel9-automation`
   - Service Level: `Premium`
   - Usage: `Development/Test`
4. Attach subscriptions:
   - ✅ Red Hat Enterprise Linux Server
   - ✅ Ansible Automation Platform
5. **Copy**:
   - Organization ID (e.g., `1234567`)
   - Activation Key Name (e.g., `aap-rhel9-automation`)

---

## Step 2: Create Vault File (1 min)

```bash
cd /home/vpcuser/ocp4-disconnected-helper

# Copy template
cp extra_vars/rhel-subscription-secrets.yml.example \
   extra_vars/rhel-subscription-secrets.yml

# Edit with your values
vi extra_vars/rhel-subscription-secrets.yml
```

**Fill in**:
```yaml
rhsm_org_id: "YOUR_ORG_ID"              # From step 1
rhsm_activationkey: "YOUR_KEY_NAME"     # From step 1
aap_admin_password: "ChangeMe123!"      # Set AAP admin password
aap_pg_password: "ChangeMe123!"         # Set PostgreSQL password
```

---

## Step 3: Encrypt Vault File (30 sec)

```bash
# Create vault password file
echo "your-secure-vault-password" > ~/.vault_pass
chmod 600 ~/.vault_pass

# Encrypt secrets file
ansible-vault encrypt extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Verify**:
```bash
# Should show: $ANSIBLE_VAULT;1.1;AES256
head -1 extra_vars/rhel-subscription-secrets.yml
```

---

## Step 4: Deploy AAP (20-25 min)

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml \
  --vault-password-file ~/.vault_pass \
  -e @extra_vars/rhel-subscription-secrets.yml
```

**What happens**:
1. ✅ Registers RHEL 9 with Red Hat (1 min)
2. ✅ Enables repositories (30 sec)
3. ✅ Installs prerequisites (2 min)
4. ✅ Downloads AAP installer (5 min)
5. ✅ Prepares installation inventory (1 min)
6. ✅ Runs containerized installation (10-15 min)
7. ✅ Displays access credentials

---

## Step 5: Access AAP Web UI (30 sec)

**URL**: https://192.168.122.72  
**Username**: `admin`  
**Password**: `<your aap_admin_password from vault>`

---

## Troubleshooting

### Check VM Status
```bash
export LIBVIRT_DEFAULT_URI="qemu:///system"
virsh list | grep aap
ssh ansible@192.168.122.72 "hostname && cat /etc/redhat-release"
```

### View Vault Contents
```bash
ansible-vault view extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

### Edit Vault File
```bash
ansible-vault edit extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

### Check Subscription Status
```bash
ssh ansible@192.168.122.72
sudo subscription-manager status
```

### View Container Status
```bash
ssh ansible@192.168.122.72
podman ps
systemctl status automation-controller
```

---

## Complete Documentation

- **Setup Guide**: `docs/ACTIVATION_KEY_SETUP.md`
- **Deployment Guide**: `docs/AAP_DEPLOYMENT_GUIDE.md`
- **Summary**: `docs/AAP_DEPLOYMENT_SUMMARY.md`
- **ADR**: `docs/adrs/0027-rhel-subscription-activation-keys.md`

---

## Quick Commands Reference

| Task | Command |
|------|---------|
| **Create vault file** | `cp extra_vars/rhel-subscription-secrets.yml.example extra_vars/rhel-subscription-secrets.yml` |
| **Encrypt vault** | `ansible-vault encrypt extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass` |
| **View vault** | `ansible-vault view extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass` |
| **Edit vault** | `ansible-vault edit extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass` |
| **Deploy AAP** | `ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml --vault-password-file ~/.vault_pass -e @extra_vars/rhel-subscription-secrets.yml` |
| **SSH to VM** | `ssh ansible@192.168.122.72` |
| **Check containers** | `ssh ansible@192.168.122.72 "podman ps"` |

---

## Support

- **Red Hat Portal**: https://access.redhat.com
- **Activation Keys**: https://access.redhat.com/management/activation_keys
- **AAP 2.6 Docs**: https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/
- **GitHub Repo**: https://github.com/tosin2013/ocp4-disconnected-helper

---

**Ready to deploy!** 🚀
