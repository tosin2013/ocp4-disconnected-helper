# Ansible Automation Platform Deployment Guide

**Last Updated**: 2026-06-04  
**AAP Versions Covered**: 2.5, 2.6  
**Target OS**: RHEL 9.2+

---

## Table of Contents

1. [AAP Version Selection](#aap-version-selection)
2. [RHEL 9 Base Image Acquisition](#rhel-9-base-image-acquisition)
3. [AAP 2.6 Containerized Installation](#aap-26-containerized-installation)
4. [VM Provisioning with cloud-init](#vm-provisioning-with-cloud-init)
5. [Post-Installation Configuration](#post-installation-configuration)
6. [Troubleshooting](#troubleshooting)

---

## AAP Version Selection

### AAP 2.6 (Recommended) vs AAP 2.5

| Feature | AAP 2.5 | AAP 2.6 |
|---------|---------|---------|
| **Release Date** | 2024-11 | 2025-10-08 |
| **RHEL Support** | RHEL 8.8+, RHEL 9.2+ | RHEL 9.2+, RHEL 10 |
| **Installation Method** | Containerized + RPM | **Containerized only** (RHEL 9) |
| **Ansible Core** | 2.16+ | 2.16+ |
| **RPM Installer** | Deprecated | **Last version** (RHEL 9 only) |
| **Lifecycle** | Standard | Extended support |

**Recommendation**: Use **AAP 2.6** for:
- New deployments on RHEL 9/10
- Containerized-first architecture
- Future-proof installations (RPM deprecated)

**References**:
- [AAP 2.6 System Requirements](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/rpm_installation/platform-system-requirements)
- [AAP 2.6 Installation Guide](https://www.redhat.com/en/blog/installation-and-upgrade-guide-ansible-automation-platform-26)

---

## RHEL 9 Base Image Acquisition

### Prerequisites

- Red Hat subscription (active)
- Access to [Red Hat Customer Portal](https://access.redhat.com)

### Download RHEL 9 KVM Guest Image

#### Method 1: Red Hat Customer Portal (Web UI)

1. **Login**: Navigate to https://access.redhat.com/downloads/content/rhel
2. **Select Version**: Red Hat Enterprise Linux 9.X
3. **Choose Image**: "Red Hat Enterprise Linux 9.X KVM Guest Image"
4. **Download**: Save `rhel-9.X-x86_64-kvm.qcow2` (approx 1.2 GB)

#### Method 2: Command Line (with credentials)

```bash
# Set credentials
export RH_USERNAME="your-rh-username"
export RH_PASSWORD="your-rh-password"

# Download latest RHEL 9 KVM guest image
# Note: Exact URL requires authentication token from Red Hat
curl -u "${RH_USERNAME}:${RH_PASSWORD}" \
  -o /var/lib/libvirt/images/rhel9-kvm-guest.qcow2 \
  'https://access.redhat.com/downloads/content/.../rhel-9-x86_64-kvm.qcow2'
```

#### Method 3: Pre-Downloaded Image Transfer

```bash
# On workstation with Red Hat access
scp rhel-9.X-x86_64-kvm.qcow2 vpcuser@hypervisor:/tmp/

# On hypervisor
sudo mv /tmp/rhel-9.X-x86_64-kvm.qcow2 /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
sudo chown qemu:qemu /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
sudo chmod 644 /var/lib/libvirt/images/rhel9-kvm-guest.qcow2
```

### RHEL 9 KVM Guest Image Characteristics

Per [Red Hat Documentation](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html-single/configuring_and_managing_cloud-init_for_rhel_9/index):

| Property | Value |
|----------|-------|
| **cloud-init** | Pre-installed and enabled |
| **Default User** | `cloud-user` (with sudo access) |
| **Root Account** | Locked (SSH key required) |
| **Metadata Service** | EC2-compatible |
| **Disk Format** | qcow2 (compressed) |
| **Typical Size** | 1.2-1.5 GB compressed |

---

## AAP 2.6 Containerized Installation

### System Requirements

Per [AAP 2.6 Planning Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/planning_your_installation/platform-system-requirements):

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **CPU** | 4 cores | 8+ cores |
| **RAM** | 16 GB | 32 GB+ |
| **Disk** | 60 GB | 100 GB+ |
| **OS** | RHEL 9.2+ | RHEL 9.4+ |

### Installation Methods

#### Online Installation (Connected Environment)

```bash
# 1. Register RHEL system
sudo subscription-manager register --username <rh-username> --password <rh-password>
sudo subscription-manager attach --pool=<pool-id>

# 2. Enable required repositories
sudo subscription-manager repos \
  --enable=ansible-automation-platform-2.6-for-rhel-9-x86_64-rpms

# 3. Download installer
mkdir -p ~/aap-installer
cd ~/aap-installer
curl -O https://access.redhat.com/.../ansible-automation-platform-containerized-setup-2.6-1.tar.gz

# 4. Extract and run setup
tar -xzf ansible-automation-platform-containerized-setup-2.6-1.tar.gz
cd ansible-automation-platform-containerized-setup-2.6-1
./setup.sh
```

#### Bundle Installation (Disconnected/Air-Gapped)

**Download Bundle** (on connected workstation):

```bash
# Download from Red Hat Customer Portal
# File: ansible-automation-platform-containerized-setup-bundle-2.6-1.1-x86_64.tar.gz
# Size: ~15-20 GB (includes all container images)

# Transfer to disconnected environment
scp ansible-automation-platform-containerized-setup-bundle-2.6-1.1-x86_64.tar.gz \
  cloud-user@<aap-vm-ip>:/home/cloud-user/
```

**Install on Disconnected System**:

```bash
# 1. Extract bundle
tar -xzf ansible-automation-platform-containerized-setup-bundle-2.6-1.1-x86_64.tar.gz
cd ansible-automation-platform-containerized-setup-bundle-2.6-1.1

# 2. Run offline installer
./setup.sh -e bundle_install=true
```

**References**:
- [AAP 2.6 Containerized Installation Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html-single/containerized_installation/index)
- [AAP Bundle Installation Tutorial](https://www.n0tes.fr/2025/11/19/AAP-Bundle-Container-Install/)

### Installation Configuration

**Create `inventory` file** before running `setup.sh`:

```ini
[automationcontroller]
aap-vm.example.com ansible_connection=local

[all:vars]
# Admin credentials
admin_password='SecurePassword123!'

# Database
postgresql_admin_password='PostgresPassword!'

# Registry (for bundle installations)
registry_url='registry.example.com:8443'
registry_username='admin'
registry_password='RegistryPassword!'

# Network
controller_hostname='aap-vm.example.com'
controller_external_url='https://aap-vm.example.com'
```

---

## VM Provisioning with cloud-init

### Overview

The `playbooks/provision-aap-vm.yml` playbook automates AAP VM creation with RHEL 9 base image and cloud-init configuration.

### Prerequisites

1. **RHEL 9 KVM Guest Image** at `/var/lib/libvirt/images/rhel9-kvm-guest.qcow2`
2. **Ansible collections**: `community.libvirt` installed
3. **xorriso**: Installed (`dnf install -y xorriso`)
4. **SSH keys**: Generated at `~/.ssh/id_rsa.pub`

### Provision AAP VM

```bash
# Deploy AAP VM with defaults
ansible-playbook -i inventory/ibm-cloud.yml playbooks/provision-aap-vm.yml

# Expected output:
# - VM Name: aap-vm
# - IP Address: 192.168.122.30 (static)
# - Memory: 16 GB
# - CPUs: 4
# - Disk: 60 GB
```

### cloud-init Configuration

The playbook generates three cloud-init files:

#### 1. user-data (User and Package Setup)

```yaml
#cloud-config
hostname: aap
fqdn: aap.example.com
manage_etc_hosts: true

users:
  - name: cloud-user
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - ssh-rsa AAAAB3...

packages:
  - podman
  - podman-docker
  - firewalld
  - python3
  - python3-pip

runcmd:
  - systemctl enable --now firewalld
  - firewall-cmd --permanent --add-service=https
  - firewall-cmd --permanent --add-port=5432/tcp  # PostgreSQL
  - firewall-cmd --reload
```

#### 2. meta-data (Instance Identification)

```yaml
instance-id: aap-vm-001
local-hostname: aap
```

#### 3. network-config (Static IP Configuration)

```yaml
version: 2
ethernets:
  enp1s0:
    addresses:
      - 192.168.122.30/24
    gateway4: 192.168.122.1
    nameservers:
      addresses:
        - 192.168.122.1
        - 8.8.8.8
```

### Verify VM Provisioning

```bash
# Check VM is running
sudo virsh list

# Get VM IP address
sudo virsh domifaddr aap-vm

# SSH to VM
ssh cloud-user@192.168.122.30

# On VM: Verify cloud-init completed
cloud-init status --wait
```

**References**:
- [RHEL 9 cloud-init Configuration Guide](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html-single/configuring_and_managing_cloud-init_for_rhel_9/index)
- [Deploying KVM Guest Images](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/composing_a_customized_rhel_system_image/preparing-and-deploying-kvm-guest-images-with-image-builder_composing-a-customized-rhel-system-image)

---

## Post-Installation Configuration

### 1. Register RHEL System

```bash
ssh cloud-user@192.168.122.30

# Register with Red Hat
sudo subscription-manager register \
  --username <rh-username> \
  --password <rh-password>

# Attach subscription
sudo subscription-manager attach --pool=<pool-id>

# Enable AAP repositories
sudo subscription-manager repos \
  --enable=ansible-automation-platform-2.6-for-rhel-9-x86_64-rpms
```

### 2. Install AAP 2.6 Containerized

```bash
# Download installer (if online)
mkdir -p ~/aap-installer && cd ~/aap-installer
curl -O https://access.redhat.com/.../ansible-automation-platform-containerized-setup-2.6-1.tar.gz
tar -xzf ansible-automation-platform-containerized-setup-2.6-1.tar.gz

# OR transfer bundle (if offline)
# scp from hypervisor to VM

# Configure inventory
cd ansible-automation-platform-containerized-setup-2.6-1
cp inventory.example inventory
vi inventory  # Set passwords and hostnames

# Run installation
./setup.sh
```

### 3. Access AAP Web UI

```bash
# Get controller URL
echo "AAP URL: https://$(hostname -f)"

# Login credentials (from inventory file)
# Username: admin
# Password: <admin_password from inventory>
```

### 4. Configure Firewall (if needed)

```bash
# AAP uses standard HTTPS (443)
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-port=5432/tcp  # PostgreSQL (if external)
sudo firewall-cmd --reload
```

---

## Troubleshooting

### Issue: RHEL Image Not Found

**Symptom**:
```
❌ RHEL 9 KVM Guest Image required but not found!
```

**Solution**:
1. Download RHEL 9 KVM guest image from Red Hat Customer Portal
2. Place at `/var/lib/libvirt/images/rhel9-kvm-guest.qcow2`
3. Or set `rhel9_kvm_guest_image_url` in inventory

### Issue: cloud-init Failed

**Symptom**:
```
cloud-init status --wait
status: error
```

**Solution**:
```bash
# Check cloud-init logs
sudo cat /var/log/cloud-init.log
sudo cat /var/log/cloud-init-output.log

# Common causes:
# 1. Network config syntax error
# 2. Missing cloud-init ISO
# 3. SSH key format issue
```

### Issue: AAP Installation Fails - Missing Dependencies

**Symptom**:
```
ERROR: podman not found
```

**Solution**:
```bash
# cloud-init should have installed podman
# If missing, install manually:
sudo dnf install -y podman podman-docker
```

### Issue: Static IP Not Applied

**Symptom**: VM gets DHCP IP instead of static 192.168.122.30

**Solution**:
```bash
# Check network-config in cloud-init ISO
# Ensure gateway4 is used (not routes)
# See ADR 0026 for CentOS Stream 9 cloud-init bug workaround
```

### Issue: Cannot Access AAP Web UI

**Symptom**: `curl https://aap-vm.example.com` times out

**Solution**:
```bash
# 1. Check AAP services are running
sudo podman ps

# 2. Check firewall allows HTTPS
sudo firewall-cmd --list-all

# 3. Verify AAP controller is listening
sudo ss -tlnp | grep 443
```

---

## Next Steps

After successful AAP deployment:

1. **Configure Organizations and Teams**
2. **Import Automation Content** (playbooks, roles, collections)
3. **Set Up Execution Environments**
4. **Create Job Templates**
5. **Configure LDAP/SSO Authentication** (optional)
6. **Set Up High Availability** (optional - multi-node)

---

## References

### Official Red Hat Documentation

- [AAP 2.6 System Requirements](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/rpm_installation/platform-system-requirements)
- [AAP 2.6 Containerized Installation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html-single/containerized_installation/index)
- [AAP 2.6 Planning Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/planning_your_installation/platform-system-requirements)
- [RHEL 9 cloud-init Configuration](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html-single/configuring_and_managing_cloud-init_for_rhel_9/index)
- [Deploying RHEL 9 KVM Guest Images](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/composing_a_customized_rhel_system_image/preparing-and-deploying-kvm-guest-images-with-image-builder_composing-a-customized-rhel-system-image)

### Community Resources

- [AAP 2.6 Installation Guide Blog](https://www.redhat.com/en/blog/installation-and-upgrade-guide-ansible-automation-platform-26)
- [AAP Bundle Installation Tutorial](https://www.n0tes.fr/2025/11/19/AAP-Bundle-Container-Install/)
- [How to Build QCOW2 Images for RHEL](https://oneuptime.com/blog/post/2026-03-04-build-qcow2-virtual-machine-images-rhel/view)

### Related ADRs

- **ADR 0021**: Deprecate Airflow and Adopt AAP
- **ADR 0026**: Use RHEL 9 Base Image for AAP
- **ADR 0023**: Pure Ansible with community.libvirt
