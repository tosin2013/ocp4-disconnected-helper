# AAP 2.6 Deployment Summary

**Status**: ✅ **Automation Complete** (Ready for Execution)  
**Date**: June 4, 2026  
**VM**: aap.ocp4.sandbox3377.opentlc.com (192.168.122.72)

---

## What Was Built

### 1. **End-to-End AAP Deployment Automation**

Created `playbooks/deploy-aap.yml` - a complete automated deployment using official Red Hat collections:

**Features**:
- ✅ Red Hat subscription registration (automatic)
- ✅ Repository enablement (RHEL 9 + AAP 2.6)
- ✅ Prerequisite installation (podman, ansible-core, python3)
- ✅ AAP installer download (automated)
- ✅ Inventory generation (all-in-one single node)
- ✅ Containerized installation (Podman-based)

**Collections Used**:
- `infra.aap_utilities:3.3.0` - Official Red Hat AAP deployment automation
- `infra.aap_configuration:3.3.0` - AAP configuration management
- `community.general:13.0.1` - Subscription management

**Roles Leveraged**:
- `infra.aap_utilities.aap_setup_download` - Download AAP installer
- `infra.aap_utilities.aap_setup_prepare` - Prepare inventory and environment
- `infra.aap_utilities.aap_setup_install` - Execute installation

---

## Infrastructure Status

### AAP VM Configuration

| Component | Details |
|-----------|---------|
| **Hostname** | aap.ocp4.sandbox3377.opentlc.com |
| **IP Address** | 192.168.122.72 (DHCP via KVM virbr0) |
| **Operating System** | RHEL 9.8 |
| **Base Image** | rhel-9.8-x86_64-kvm.qcow2 (1.29 GiB) |
| **Resources** | 4 vCPU, 16 GB RAM, 60 GB Disk |
| **SSH User** | ansible (sudo enabled) |
| **Subscription** | ⚠️ Not registered (requires credentials) |

### VM Provisioning

| Item | Status |
|------|--------|
| RHEL 9.8 KVM guest image | ✅ Downloaded (1.29 GiB) |
| VM provisioned | ✅ Running (ID: 37) |
| SSH access | ✅ Verified (ansible@192.168.122.72) |
| Cloud-init | ✅ Applied (hostname, user, packages) |
| Static IP | ⚠️ Not configured (using DHCP - registry pattern) |

---

## How to Deploy AAP 2.6

### Prerequisites

1. **Red Hat Subscription Credentials**
   - Username/Password OR Activation Key
   - Must have AAP 2.6 entitlements

2. **SSH Access to Hypervisor**
   ```bash
   ssh vpcuser@169.59.190.3
   cd /home/vpcuser/ocp4-disconnected-helper
   ```

### Deployment Steps

#### Option 1: Username/Password Authentication

```bash
export RHSM_USERNAME='your-redhat-username'
export RHSM_PASSWORD='your-redhat-password'
export AAP_ADMIN_PASSWORD='YourSecurePassword123!'

ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml
```

#### Option 2: Activation Key Authentication (Recommended)

```bash
export RHSM_ORG_ID='your-organization-id'
export RHSM_ACTIVATIONKEY='your-activation-key'
export AAP_ADMIN_PASSWORD='YourSecurePassword123!'

ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml
```

### What Happens During Deployment

1. **Pre-Flight Checks** (~1 minute)
   - Display deployment configuration
   - Check current subscription status

2. **Subscription Registration** (~2 minutes)
   - Register RHEL 9 with Red Hat Subscription Management
   - Auto-attach subscriptions
   - Enable required repositories:
     - `rhel-9-for-x86_64-baseos-rpms`
     - `rhel-9-for-x86_64-appstream-rpms`
     - `ansible-automation-platform-2.6-for-rhel-9-x86_64-rpms`

3. **Prerequisites Installation** (~3 minutes)
   - Install ansible-core, podman, python3, git, wget, curl
   - Create working directory `/home/ansible/aap`

4. **AAP Installer Download** (~5 minutes)
   - Download AAP 2.6 containerized installer from Red Hat CDN
   - Size: ~500 MB (online installer)

5. **Inventory Preparation** (~1 minute)
   - Generate AAP installation inventory
   - Configure all-in-one single node topology
   - Set admin credentials

6. **AAP Installation** (~10-15 minutes)
   - Pull container images via Podman
   - Deploy PostgreSQL database
   - Deploy Redis cache
   - Deploy Automation Controller
   - Configure systemd services

7. **Post-Installation** (~1 minute)
   - Display access credentials
   - Show service status

**Total Time**: ~20-25 minutes

---

## Post-Deployment Access

### Web UI

```
URL: https://aap.ocp4.sandbox3377.opentlc.com
     or
     https://192.168.122.72

Username: admin
Password: <value of AAP_ADMIN_PASSWORD>
```

### SSH Access

```bash
ssh ansible@192.168.122.72
```

### Container Management

```bash
# View running containers
podman ps

# Check AAP services
systemctl status automation-controller
systemctl status automation-controller-web
systemctl status postgresql
systemctl status redis

# View container logs
podman logs automation-controller-web
```

---

## Architecture Details

### Deployment Topology

**All-in-One Single Node**:
- Automation Controller (web UI, API, task engine)
- PostgreSQL 15 (metadata database)
- Redis (cache and message broker)
- All services run in Podman containers on single RHEL 9.8 VM

### Container Structure

```
┌─────────────────────────────────────────────────────┐
│  aap.ocp4.sandbox3377.opentlc.com (RHEL 9.8)       │
│                                                      │
│  ┌────────────────────────────────────────────┐    │
│  │  Podman Container Runtime                  │    │
│  │                                             │    │
│  │  ┌─────────────────────────────────────┐  │    │
│  │  │  automation-controller-web          │  │    │
│  │  │  (nginx + Django frontend)          │  │    │
│  │  │  Port: 443                          │  │    │
│  │  └─────────────────────────────────────┘  │    │
│  │                                             │    │
│  │  ┌─────────────────────────────────────┐  │    │
│  │  │  automation-controller-task         │  │    │
│  │  │  (AWX task engine)                  │  │    │
│  │  └─────────────────────────────────────┘  │    │
│  │                                             │    │
│  │  ┌─────────────────────────────────────┐  │    │
│  │  │  postgresql                         │  │    │
│  │  │  Port: 5432                         │  │    │
│  │  └─────────────────────────────────────┘  │    │
│  │                                             │    │
│  │  ┌─────────────────────────────────────┐  │    │
│  │  │  redis                              │  │    │
│  │  │  Port: 6379                         │  │    │
│  │  └─────────────────────────────────────┘  │    │
│  └────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

### Network Configuration

| Service | Port | Protocol | Purpose |
|---------|------|----------|---------|
| Web UI | 443 | HTTPS | AAP web interface |
| HTTP (redirect) | 80 | HTTP | Redirect to HTTPS |
| PostgreSQL | 5432 | TCP | Database (internal) |
| Redis | 6379 | TCP | Cache/message broker (internal) |

---

## Troubleshooting

### Issue: Subscription Registration Fails

**Symptom**: Error during `redhat_subscription` task

**Solution**:
```bash
# Verify credentials
echo $RHSM_USERNAME
echo $RHSM_ORG_ID

# Manual registration
ssh ansible@192.168.122.72
sudo subscription-manager register --username <user> --password <pass>
sudo subscription-manager attach --auto
```

### Issue: AAP Installer Download Fails

**Symptom**: Download timeout or 404 error

**Solution**:
```bash
# Use offline bundle instead
# 1. Download from Red Hat Customer Portal:
#    https://access.redhat.com/downloads/content/480
#    Select: Ansible Automation Platform 2.6 → Containerized Bundle
#
# 2. Upload to VM:
scp ansible-automation-platform-containerized-setup-bundle-*.tar.gz \
  ansible@192.168.122.72:/home/ansible/aap/

# 3. Update playbook variable:
aap_setup_down_type: "setup-bundle"
```

### Issue: Container Pull Failures

**Symptom**: Unable to pull images from registry.redhat.io

**Solution**:
```bash
# Verify subscription status
ssh ansible@192.168.122.72
sudo subscription-manager status

# Check podman authentication
podman login registry.redhat.io

# Manual image pull test
podman pull registry.redhat.io/ansible-automation-platform-26/controller-rhel9:latest
```

### Issue: Installation Hangs

**Symptom**: Playbook stuck on `aap_setup_install` role

**Solution**:
```bash
# SSH to VM and check logs
ssh ansible@192.168.122.72
cd /home/ansible/aap/ansible-automation-platform-containerized-setup-*/
tail -f /tmp/aap_install.log

# Check container status
podman ps -a

# Review installation logs
journalctl -u automation-controller -f
```

---

## Next Steps

### 1. **Execute Deployment**

Run the playbook with Red Hat credentials:
```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap.yml
```

### 2. **Configure AAP**

After installation:
- Create Organizations
- Add Inventories
- Configure Credentials
- Create Job Templates
- Set up Projects (Git repositories)

### 3. **Integrate with OpenShift**

Use AAP to automate OpenShift cluster deployment:
- Create inventory for OpenShift nodes
- Import openshift-ansible playbooks
- Configure OpenShift installation variables
- Run cluster deployment from AAP

### 4. **Production Hardening** (Future)

- [ ] Configure SSL/TLS with Let's Encrypt (HAProxy)
- [ ] Set up external PostgreSQL database
- [ ] Enable LDAP/AD authentication
- [ ] Configure backup and restore procedures
- [ ] Implement monitoring and alerting

---

## References

### Official Documentation

- [AAP 2.6 Containerized Installation Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html-single/containerized_installation/)
- [Installation and Upgrade Guide for AAP 2.6](https://www.redhat.com/en/blog/installation-and-upgrade-guide-ansible-automation-platform-26)
- [AAP 2.6 Release Notes](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/pdf/release_notes/)

### Ansible Collections

- [infra.aap_utilities on GitHub](https://github.com/redhat-cop/aap_utilities)
- [infra.aap_configuration on GitHub](https://github.com/redhat-cop/infra.aap_configuration)
- [Register RHEL with Ansible](https://www.redhat.com/en/blog/register-rhel-attach-subscription-ansible)

### Project Documentation

- [AAP Deployment Guide](AAP_DEPLOYMENT_GUIDE.md)
- [RHEL 9 Direct Download Guide](RHEL9_DIRECT_DOWNLOAD.md)
- [Getting Started](GETTING_STARTED.md)

---

## Commit History

| Commit | Description |
|--------|-------------|
| `f92baa4` | feat: Add end-to-end AAP 2.6 deployment with infra.aap_utilities |
| `6a3dbc7` | feat: Add automated scripts for RHEL 9 image download |
| `da6d4b9` | docs: Add RHEL 9 direct download guide (no SCP required) |
| `42f3cd1` | docs: Add RHEL 9 KVM guest image download guide |

---

## Summary

✅ **Deployment automation is complete and ready for execution.**

All components are in place:
- RHEL 9.8 VM provisioned and accessible
- End-to-end deployment playbook using official Red Hat collections
- Comprehensive documentation and troubleshooting guides

**To deploy**: Provide Red Hat subscription credentials and run the playbook. The entire AAP 2.6 containerized installation will complete automatically in ~20-25 minutes.
