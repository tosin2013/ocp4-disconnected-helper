# How to Generate Agent-Based Installer ISO

This guide explains how to generate bootable ISO images for OpenShift cluster deployment using the Agent-Based Installer.

## Overview

The Agent-Based Installer creates a single bootable ISO that contains:
- OpenShift installation binaries
- Cluster configuration (install-config.yaml)
- Agent configuration (agent-config.yaml)
- Network configuration (NMState for static IPs)
- Container image manifests (ImageDigestMirrorSet)

VMs boot from this ISO and automatically begin the installation process.

---

## Prerequisites

### 1. OpenShift Install Binary

Download the `openshift-install` binary matching your target OCP version:

```bash
# Set version
OCP_VERSION="4.21.0"

# Download
cd /tmp
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz

# Extract
tar -xzf openshift-install-linux.tar.gz

# Install
sudo mv openshift-install /usr/local/bin/
sudo chmod +x /usr/local/bin/openshift-install

# Verify
openshift-install version
```

**Expected output**:
```
openshift-install 4.21.0
built from commit ... [truncated]
release image quay.io/openshift-release-dev/ocp-release@sha256:...
```

### 2. Pull Secret

Download your Red Hat pull secret from: https://console.redhat.com/openshift/install/pull-secret

```bash
# Save to file
cat > /root/pull-secret.json << 'EOF'
{"auths":{"cloud.openshift.com":{"auth":"...","email":"..."}}}
EOF

chmod 600 /root/pull-secret.json
```

### 3. Cluster Configuration

Choose a cluster topology configuration:
- **SNO**: `extra_vars/cluster-configs/sno-quay.yml`
- **Compact**: `extra_vars/cluster-configs/compact-3node-quay.yml`
- **HA**: `extra_vars/cluster-configs/ha-cluster-quay.yml`

---

## ISO Generation Process

The role executes these steps automatically:

### Phase 1: Validate Prerequisites
- Check openshift-install binary exists
- Validate pull secret JSON format
- Check cluster topology configuration
- Validate resource minimums

### Phase 2: Prepare Installation Directory
- Create installation directory (e.g., `/root/openshift-install-sno-quay`)
- Remove stale artifacts (.openshift_install.log, auth/)

### Phase 3: Generate Manifests
- Create `install-config.yaml` from template
- Create `agent-config.yaml` with network config
- Create `ImageDigestMirrorSet` for registry mirrors
- Backup install-config.yaml (consumed by openshift-install)

### Phase 4: Generate ISO
```bash
openshift-install agent create image \
  --dir /root/openshift-install-sno-quay \
  --log-level=info
```

**This command**:
1. Consumes install-config.yaml and agent-config.yaml
2. Embeds manifests into the ISO
3. Generates `agent.x86_64.iso` (~1.2GB)
4. Creates auth/kubeconfig and auth/kubeadmin-password

### Phase 5: Copy ISO to Output Directory
```bash
cp /root/openshift-install-sno-quay/agent.x86_64.iso \
   /data/iso/ocp4-sno-agent.x86_64.iso
```

---

## Usage

### Automated ISO Generation

```bash
# Generate ISO for SNO cluster with Quay
ansible-playbook playbooks/test-iso-generation.yml

# Or use specific cluster config
ansible-playbook roles/openshift_cluster_deploy/tasks/create_iso.yml \
  -e @extra_vars/cluster-configs/compact-3node-quay.yml
```

### Manual ISO Generation

If you prefer to run openshift-install directly:

```bash
# 1. Create installation directory
mkdir -p /root/openshift-install-manual
cd /root/openshift-install-manual

# 2. Create install-config.yaml
cat > install-config.yaml << 'EOF'
apiVersion: v1
baseDomain: sandbox3377.opentlc.com
metadata:
  name: ocp4-manual
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  replicas: 0
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  replicas: 1
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '$(cat /root/pull-secret.json)'
sshKey: '$(cat ~/.ssh/id_rsa.pub)'
EOF

# 3. Create agent-config.yaml
cat > agent-config.yaml << 'EOF'
apiVersion: v1alpha1
kind: AgentConfig
metadata:
  name: ocp4-manual
rendezvousIP: 192.168.10.10
EOF

# 4. Generate ISO
openshift-install agent create image --dir . --log-level=info

# 5. ISO is created as: agent.x86_64.iso
ls -lh agent.x86_64.iso
```

---

## ISO Contents

After generation, the ISO contains:

| File/Directory | Purpose |
|----------------|---------|
| `coreos/` | Red Hat CoreOS kernel and initramfs |
| `openshift/` | OpenShift manifests and configuration |
| `agent-tls/` | TLS certificates for agent communication |
| `cluster-manifests/` | Embedded cluster configuration |

The ISO is **self-contained** - no external network access required during installation (disconnected mode).

---

## Verifying the ISO

### Check ISO Size
```bash
ls -lh /data/iso/ocp4-sno-agent.x86_64.iso
# Expected: ~1.0-1.5 GB
```

### Mount and Inspect
```bash
mkdir -p /mnt/iso
sudo mount -o loop /data/iso/ocp4-sno-agent.x86_64.iso /mnt/iso

# Check contents
ls -l /mnt/iso/

# Unmount
sudo umount /mnt/iso
```

### Test Boot (KVM/QEMU)
```bash
qemu-system-x86_64 \
  -m 4096 \
  -smp 2 \
  -cdrom /data/iso/ocp4-sno-agent.x86_64.iso \
  -boot d \
  -nographic
```

Press Ctrl+A, X to exit QEMU.

---

## Installation Artifacts

After ISO generation, check the installation directory:

```bash
tree /root/openshift-install-sno-quay/
```

**Expected structure**:
```
/root/openshift-install-sno-quay/
├── agent.x86_64.iso           # Bootable ISO (1.2GB)
├── auth/
│   ├── kubeconfig            # Cluster access credentials
│   └── kubeadmin-password    # Admin password
├── .openshift_install.log    # Installation log
└── .openshift_install_state.json  # State tracker
```

**Important**: Save `auth/kubeconfig` and `auth/kubeadmin-password` - you'll need them after cluster installation completes.

---

## Troubleshooting

### Error: "openshift-install: command not found"

**Solution**: Install the binary (see Prerequisites)

```bash
which openshift-install
# If empty, install it
```

### Error: "failed to fetch Install Config: failed to load asset 'Install Config': invalid InstallConfig"

**Cause**: Invalid install-config.yaml syntax

**Solution**: Validate YAML with yamllint:
```bash
yamllint /root/openshift-install-sno-quay/install-config.yaml
```

### Error: "failed to parse agent-config.yaml"

**Cause**: Missing or invalid agent-config.yaml

**Solution**: Check rendezvousIP is set:
```yaml
rendezvousIP: 192.168.10.10  # Must match first control plane node IP
```

### ISO Generation Takes Too Long (>10 minutes)

**Cause**: Slow disk I/O or downloading container images

**Solution**:
1. Check disk space: `df -h /root`
2. Check network connectivity (if not fully disconnected)
3. Monitor progress: `tail -f /root/openshift-install-sno-quay/.openshift_install.log`

### Error: "failed to create image: exit status 1"

**Cause**: Manifest validation failure

**Solution**: Enable verbose logging:
```bash
openshift-install agent create image \
  --dir /root/openshift-install-sno-quay \
  --log-level=debug
```

Review `.openshift_install.log` for specific errors.

---

## Next Steps

After ISO generation:

1. **Provision VMs**: Use the ISO to boot VMs (see Phase 5: VM Provisioning)
2. **Configure DNS**: Ensure DNS records exist for API and apps
3. **Monitor Installation**: Watch cluster bootstrap and installation progress
4. **Access Cluster**: Use auth/kubeconfig to connect

---

## See Also

- [OpenShift Agent-Based Installer Documentation](https://docs.openshift.com/container-platform/4.21/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)
- [Agent-Based Installer Examples](https://github.com/openshift/installer/tree/master/docs/user/agent)
- ADR-0035: Adopt OpenShift Agent-Based Installer
