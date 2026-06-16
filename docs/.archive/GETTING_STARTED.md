# Getting Started with ocp4-disconnected-helper

**Quick Start Guide** | From Zero to Production in 30 Minutes

---

## Who Should Use This Guide

- **New Developers**: Setting up local development environment
- **Platform Engineers**: Deploying disconnected OpenShift clusters
- **DevOps Teams**: Automating OpenShift infrastructure

---

## Prerequisites (5 minutes)

### Hardware

- **CPU**: 8+ cores (16+ recommended)
- **RAM**: 32GB minimum (128GB for full OCP cluster)
- **Disk**: 200GB SSD (500GB recommended)
- **Network**: Internet connectivity for initial setup

### Software

- **OS**: RHEL/CentOS Stream/Rocky Linux 9.4+
- **Access**: Sudo/root privileges
- **Credentials**: Red Hat account with pull secret

---

## Quick Setup (10 minutes)

### Step 1: Install Base System

```bash
# For RHEL - register and enable repos
sudo subscription-manager register
sudo subscription-manager attach --auto

# For CentOS Stream - verify repos
sudo dnf repolist
```

### Step 2: Clone and Setup

```bash
# Clone repository
git clone https://github.com/tosin2013/ocp4-disconnected-helper.git
cd ocp4-disconnected-helper

# Run automated setup
sudo ansible-playbook playbooks/setup-dependencies.yml

# Expected output:
# ✅ ansible-core 2.15+ installed
# ✅ libvirt configured and running
# ✅ Ansible collections installed
# ✅ Directory structure created
```

### Step 3: Download Red Hat Pull Secret

```bash
# Visit: https://console.redhat.com/openshift/install/pull-secret
# Download pull-secret.json to:
mv ~/Downloads/pull-secret.txt ~/pull-secret.json
```

---

## Your First Deployment (15 minutes)

### Option A: Mirror Registry Only (Lightweight)

```bash
# 1. Provision registry VM
ansible-playbook -i inventory/local-dev.yml \
  playbooks/provision-registry-vm.yml

# 2. Install mirror-registry
ansible-playbook -i inventory/local-dev.yml \
  playbooks/setup-mirror-registry.yml

# 3. Setup authentication
ansible-playbook -i inventory/local-dev.yml \
  playbooks/setup-registry-authentication.yml

# 4. Mirror OCP images
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/mirror-v2-example.yml

# Expected: 194 images (~22GB) downloaded in ~10 minutes
```

### Option B: Full Platform (with AAP Orchestration)

```bash
# 1. Provision infrastructure VMs
ansible-playbook -i inventory/local-dev.yml \
  playbooks/provision-registry-vm.yml

ansible-playbook -i inventory/local-dev.yml \
  playbooks/provision-haproxy-vm.yml

ansible-playbook -i inventory/local-dev.yml \
  playbooks/provision-aap-vm.yml

# 2. Configure services
ansible-playbook -i inventory/local-dev.yml \
  playbooks/setup-mirror-registry.yml

ansible-playbook -i inventory/local-dev.yml \
  playbooks/setup-haproxy.yml

ansible-playbook -i inventory/local-dev.yml \
  playbooks/setup-aap-containerized.yml

# 3. Access AAP UI
# https://<aap-vm-ip>
# Username: admin
# Password: (set during setup)
```

---

## Verify Installation

```bash
# Check VMs
virsh list --all

# Expected output:
# registry-vm    running
# haproxy-vm     running
# aap-controller running

# Test registry
curl -k https://registry.ocp4.local.dev:8443/health/instance

# Test SSH access
ssh cloud-user@192.168.122.26  # registry-vm
```

---

## Next Steps

### For Developers

📖 **Read**: [Developer Guide](developer-guide.md)  
🧪 **Learn**: [Architecture Decision Records](adrs/)  
💻 **Explore**: [Playbooks](../playbooks/)

### For Platform Engineers

📋 **Plan**: [RELEASE_PLAN](../RELEASE_PLAN.md)  
📦 **Deploy**: [Deployment Guides](.)  
🔧 **Configure**: [Inventory Examples](../inventory/)

### For DevOps Teams

🚀 **Automate**: [AAP Setup](aap-setup.md)  
📊 **Monitor**: [Troubleshooting Guide](../troubleshooting.md)  
🔄 **CI/CD**: [Bootstrap Scripts](../bootstrap.sh)

---

## Common Use Cases

### Use Case 1: Air-Gapped OpenShift Installation

```bash
# 1. Mirror images on connected system
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/mirror-production.yml

# 2. Transport to air-gapped environment
# - Copy ~/.oc-mirror/.cache to USB/external drive
# - Move to air-gapped network

# 3. Push to air-gapped registry
ansible-playbook -i inventory/air-gapped.yml \
  playbooks/push-to-registry-v2.yml
```

### Use Case 2: OpenShift Upgrade Mirroring

```bash
# Mirror new OCP version
cat > extra_vars/upgrade-4.22.yml <<EOF
openshift_releases:
  - name: stable-4.22
    minVersion: 4.22.0
    maxVersion: 4.22.0
EOF

ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/upgrade-4.22.yml
```

### Use Case 3: Operator Catalog Mirroring

```bash
# Add operators to mirror config
cat > extra_vars/operators.yml <<EOF
openshift_releases:
  - name: stable-4.21
    minVersion: 4.21.0
    maxVersion: 4.21.0

operators:
  - name: local-storage-operator
  - name: ocs-operator
  - name: serverless-operator
EOF

ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/operators.yml
```

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    KVM Host (RHEL 9.4+)                 │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │
│  │ Registry VM  │  │ HAProxy VM   │  │ AAP VM       │ │
│  │              │  │              │  │              │ │
│  │ mirror-      │  │ SSL/TLS      │  │ Job          │ │
│  │ registry     │  │ termination  │  │ Templates    │ │
│  │ (Quay)       │  │              │  │              │ │
│  │              │  │ Backend      │  │ Workflows    │ │
│  │ Port 8443    │  │ routing      │  │              │ │
│  └──────────────┘  └──────────────┘  └──────────────┘ │
│                                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │        OCP Cluster VMs (Optional)               │  │
│  │  Master-0, Master-1, Master-2                   │  │
│  │  Worker-0, Worker-1                             │  │
│  └─────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │  Internet            │
              │  (Red Hat CDN)       │
              │  registry.redhat.io  │
              └──────────────────────┘
```

**Data Flow**:
1. **Download**: oc-mirror fetches images from Red Hat CDN → local cache
2. **Mirror**: Images pushed from cache → mirror-registry (Quay)
3. **Access**: HAProxy provides SSL termination and routing
4. **Orchestration**: AAP (Tier 2) manages workflows

---

## Key Features

### ✅ v4.21.0 Architecture

- **Self-Contained**: No qubinode_navigator dependency
- **Pure Ansible**: community.libvirt for VM provisioning
- **Idempotent**: Run playbooks multiple times safely
- **Cloud-Init**: Automated VM configuration on first boot
- **oc-mirror v2**: Latest Red Hat image mirroring tool
- **AAP Integration**: Optional enterprise orchestration

### 🚀 Developer Experience

- **30-minute setup**: From bare metal to running registry
- **Development/Production Parity**: Same playbooks, different inventory
- **Comprehensive Docs**: Guides, ADRs, troubleshooting
- **Active Support**: GitHub issues and discussions

---

## Troubleshooting Quick Fixes

### Issue: Libvirt won't start

```bash
sudo systemctl status libvirtd
sudo systemctl start libvirtd
sudo usermod -a -G libvirt $(whoami)
# Log out and back in
```

### Issue: VM won't boot

```bash
virsh list --all
virsh destroy <vm-name>
virsh start <vm-name>
sudo journalctl -u libvirtd -f
```

### Issue: Cannot SSH to VM

```bash
# Check VM IP
virsh net-dhcp-leases default

# Test connectivity
ping -c 4 <vm-ip>

# Check SSH key injection
virsh console <vm-name>
# Login with cloud-user and check ~/.ssh/authorized_keys
```

### Issue: oc-mirror fails

```bash
# Verify pull secret
jq . ~/pull-secret.json

# Check disk space
df -h ~/.oc-mirror

# Test registry connectivity
podman login registry.redhat.io --authfile ~/pull-secret.json
```

---

## Getting Help

### Documentation

- [Developer Guide](developer-guide.md) - Comprehensive development workflows
- [PREREQUISITES](PREREQUISITES.md) - System requirements and setup
- [Troubleshooting](../troubleshooting.md) - Common issues and solutions
- [ADRs](adrs/) - Architecture decisions and rationale

### Community

- **GitHub Issues**: https://github.com/tosin2013/ocp4-disconnected-helper/issues
- **Discussions**: https://github.com/tosin2013/ocp4-disconnected-helper/discussions
- **Pull Requests**: Contributions welcome!

### Red Hat Support

- **OpenShift Documentation**: https://docs.openshift.com
- **Knowledge Base**: https://access.redhat.com/solutions
- **Support Cases**: https://access.redhat.com/support

---

## What's Next?

Based on your use case:

**Learning Mode**:
- Follow [Developer Guide](developer-guide.md) section by section
- Experiment with VM provisioning
- Test image mirroring workflows

**Production Deployment**:
- Review [RELEASE_PLAN](../RELEASE_PLAN.md) for architecture
- Configure inventory for your environment
- Run [playbooks](../playbooks/) in sequence

**Contributing**:
- Read [Contributing Guidelines](developer-guide.md#contributing)
- Check open [issues](https://github.com/tosin2013/ocp4-disconnected-helper/issues)
- Submit pull requests

---

**Project Status**: ✅ Stable (v4.21.0)  
**Last Updated**: 2026-06-03  
**Maintainer**: Platform Team

**Start your OpenShift disconnected journey today!** 🚀

## Prerequisites Setup (Required)

### Libvirt Permissions
Before running any playbooks, configure libvirt permissions:

```bash
# Add user to libvirt group
sudo usermod -a -G libvirt vpcuser

# Configure polkit
cat > /tmp/libvirt-vpcuser.rules << 'RULES'
polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" &&
        subject.user == "vpcuser") {
            return polkit.Result.YES;
    }
});
RULES
sudo cp /tmp/libvirt-vpcuser.rules /etc/polkit-1/rules.d/80-libvirt-vpcuser.rules
sudo systemctl restart polkit

# Set default libvirt URI
echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.bashrc
source ~/.bashrc
```

See [docs/LIBVIRT_PERMISSIONS.md](LIBVIRT_PERMISSIONS.md) for details.
