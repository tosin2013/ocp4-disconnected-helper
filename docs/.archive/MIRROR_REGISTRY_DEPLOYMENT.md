# Mirror Registry Deployment Guide

**Last Updated**: 2026-06-03  
**Mirror Registry Version**: 1.3.9  
**ADR Reference**: ADR 0017 - Quay Mirror Registry

## Overview

This guide documents the proven deployment pattern for Red Hat Quay mirror-registry on dedicated VMs, incorporating learnings from Qubinode deployment scripts and production troubleshooting.

## Prerequisites

### System Requirements
- **OS**: CentOS Stream 9 or RHEL 9.4+
- **RAM**: 8GB minimum
- **CPUs**: 4 vCPUs
- **Disk**: 500GB+ for OCP image mirroring
- **Network**: Static IP configuration

### Required Packages
```bash
dnf install -y \
  podman \
  skopeo \
  buildah \
  httpd-tools \
  openssl \
  firewalld \
  acl \
  sshpass
```

## Critical System Configuration

### 1. Rootless Podman Workarounds

**Problem**: Mirror-registry runs as rootless podman and requires specific permission configurations for user namespace mapping.

**Solution**: Apply Qubinode-proven workarounds:

```bash
# Set setuid permissions on newgidmap/newuidmap
sudo chmod 4755 /usr/bin/newgidmap
sudo chmod 4755 /usr/bin/newuidmap
```

**Why**: These tools must be setuid root to allow non-root users to map user/group IDs in containers.

### 2. Network Configuration for Rootless Containers

**Problem**: Rootless containers need special sysctl settings for networking.

**Solution**:
```bash
# Allow rootless containers to bind to privileged ports
sudo sysctl -w net.ipv4.ip_unprivileged_port_start=0

# Allow rootless containers to use ping
sudo sysctl -w net.ipv4.ping_group_range="0 2000000"

# Make persistent
sudo tee /etc/sysctl.d/99-rootless-containers.conf <<EOF
net.ipv4.ip_unprivileged_port_start=0
net.ipv4.ping_group_range=0 2000000
EOF

sudo sysctl --system
```

**Why**: 
- `ip_unprivileged_port_start=0` allows binding to port 8443 without root
- `ping_group_range` enables ICMP in rootless containers

### 3. XDG Runtime Directory

**Problem**: Rootless podman requires XDG_RUNTIME_DIR to be set for container runtime state.

**Solution**:
```bash
# Create profile script
sudo tee /etc/profile.d/xdg_runtime_dir.sh <<EOF
export XDG_RUNTIME_DIR="\$HOME/.run/containers"
EOF

# Create directory for target user
mkdir -p ~/.run/containers
chmod 700 ~/.run/containers
```

**Why**: Podman stores runtime state in XDG_RUNTIME_DIR; without this, containers may fail to start.

## Deployment Methods

### Method 1: Ansible Playbook (Recommended)

```bash
# Add registry VM to inventory
cat >> inventory/ibm-cloud.yml <<EOF
  children:
    registry_vms:
      hosts:
        registry:
          ansible_host: "192.168.122.26"
          ansible_user: "root"
          ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
EOF

# Deploy mirror-registry
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/setup-mirror-registry.yml \
  -e "target_host=registry" \
  -e "mirror_registry_hostname=registry.ocp4.sandbox3377.opentlc.com" \
  -e "mirror_registry_data_dir=/registry"
```

### Method 2: Manual Installation

```bash
# Download mirror-registry
VERSION=1.3.9
curl -L -o mirror-registry.tar.gz \
  "https://developers.redhat.com/content-gateway/file/pub/openshift-v4/clients/mirror-registry/${VERSION}/mirror-registry.tar.gz"

tar xvf mirror-registry.tar.gz

# Install
./mirror-registry install \
  --quayHostname registry.ocp4.sandbox3377.opentlc.com \
  --quayRoot /registry \
  --initPassword <your-password>
```

## Installation Command Structure

### Correct Usage
```bash
./mirror-registry install \
  --quayHostname registry.example.com \
  --quayRoot /registry \
  --initPassword <password>
```

**Key Parameters**:
- `--quayRoot`: Path to data directory (e.g., `/registry`)
- `--initPassword`: Admin password for `init` user
- `--quayHostname`: FQDN for certificate generation

### Common Mistakes

❌ **WRONG**: `--quayRoot init`
```bash
# This creates invalid volume name "init/quay-config"
./mirror-registry install --quayRoot init --initPassword <password>
```

✅ **CORRECT**: `--quayRoot /path/to/data`
```bash
# This creates proper data directory
./mirror-registry install --quayRoot /registry --initPassword <password>
```

**Why**: The `--quayRoot` parameter expects a filesystem path, not a keyword. Using "init" causes podman to try creating a volume named "init/quay-config", which fails due to invalid characters.

## Post-Installation Validation

### 1. Container Health Check

**Comprehensive validation** (not just exit code):

```bash
# Verify all 3 required containers are running
podman ps --format "{{.Names}}\t{{.Status}}"

# Expected output:
# 9c45069710bf-infra    Up X minutes
# quay-postgres         Up X minutes
# quay-redis            Up X minutes
# quay-app              Up X minutes
```

**Check for container restarts** (sign of problems):
```bash
podman ps --format "{{.Names}}\t{{.Status}}" | grep -i restart
# Should return nothing
```

### 2. API Health Validation

```bash
# Test locally on registry VM
curl -k https://localhost:8443/health/instance | jq '.'

# Expected response:
{
  "data": {
    "services": {
      "auth": true,
      "database": true,
      "disk_space": true,
      "registry_gunicorn": true,
      "service_key": true,
      "web_gunicorn": true
    }
  },
  "status_code": 200
}
```

All services must be `true` for healthy registry.

### 3. Container Logs Check

If health check fails, check container logs:

```bash
# Check quay-app logs
podman logs quay-app 2>&1 | tail -50

# Common issues:
# - "WRONGPASS invalid username-password pair" → Redis password mismatch
# - "could not connect to postgres" → PostgreSQL not ready
# - "OSError: [Errno 13] Permission denied" → SELinux or volume permissions
```

## Known Issues and Solutions

### Issue 1: Redis Password Mismatch

**Symptoms**:
- `quay-app` container restarting repeatedly
- Logs show: `WRONGPASS invalid username-password pair or user is disabled`

**Root Cause**: Mirror-registry installation bug creates mismatched passwords between Redis container and Quay config.yaml

**Solution**:
```bash
# 1. Get actual Redis password
REDIS_PASSWORD=$(podman exec quay-redis env | grep REDIS_PASSWORD | cut -d= -f2)

# 2. Update config.yaml
CONFIG_FILE=/registry/quay-config/config.yaml
sed -i "s/password: .*/password: ${REDIS_PASSWORD}/" ${CONFIG_FILE}

# 3. Restart quay-app
systemctl --user restart quay-app
```

**Prevention**: Enhanced ansible playbook includes validation to detect this issue.

### Issue 2: Cloud-Init SSH Key Injection Failures

**Symptoms**:
- VM boots but SSH fails with "Permission denied (publickey)"
- Cloud-init logs show SSH key not applied

**Root Cause**: Cloud-init on CentOS Stream 9/10 has issues with SSH key injection in KVM environments

**Solution**: Use `virt-customize` to inject SSH keys post-provisioning:

```bash
# Shutdown VM
sudo virsh shutdown registry-vm

# Inject SSH key
sudo virt-customize -d registry-vm \
  --root-password password:redhat123 \
  --ssh-inject root:file:/home/vpcuser/.ssh/id_rsa.pub \
  --selinux-relabel

# Start VM
sudo virsh start registry-vm
```

**Prevention**: This issue is tracked in ADR 0023 as part of libvirt migration work.

### Issue 3: Static IP Not Applied

**Symptoms**:
- VM gets DHCP IP instead of configured static IP
- Cloud-init network-config ignored

**Root Cause**: Same cloud-init issues as SSH key injection

**Workaround**: Apply static IP via nmcli after boot:
```bash
ssh root@<dhcp-ip> <<'EOF'
nmcli con delete ens3 2>/dev/null || true
nmcli con add type ethernet con-name enp1s0-static ifname enp1s0 \
  ipv4.addresses 192.168.122.5/24 \
  ipv4.gateway 192.168.122.1 \
  ipv4.dns "192.168.122.1 8.8.8.8" \
  ipv4.method manual
nmcli con up enp1s0-static
EOF
```

## Security Considerations

### SSL Certificates

**Default**: Mirror-registry generates self-signed certificates
- Located in `/registry/quay-rootCA/`
- Certificate: `ssl.cert`
- Key: `ssl.key`

**Production**: Use Let's Encrypt signed certificates
```bash
ansible-playbook setup-mirror-registry.yml \
  -e "use_custom_certs=true" \
  -e "custom_cert_path=/etc/pki/registry/registry.crt" \
  -e "custom_key_path=/etc/pki/registry/registry.key"
```

**IMPORTANT**: Per project requirements, **DO NOT skip certificate validation**. Always use signed certificates for production deployments.

### Credentials Storage

Mirror-registry credentials are stored in:
- `/opt/mirror-registry/credentials.txt` (600 permissions)
- Pull secret snippet: `/opt/mirror-registry/pull-secret-snippet.json`

**Best Practice**: Use Ansible Vault for credential management:
```bash
ansible-vault encrypt_string 'your-password' --name 'mirror_registry_password'
```

## Container Architecture

Mirror-registry deploys 4 containers:

1. **quay-pod** (infra): Pod infrastructure container
2. **quay-postgres**: PostgreSQL database for Quay metadata
3. **quay-redis**: Redis for caching and job queues
4. **quay-app**: Quay application (registry API + UI)

**Data Storage**:
- PostgreSQL: Podman volume `quay-postgres-{random}`
- Quay storage: `/registry/quay-storage/`
- Config: `/registry/quay-config/config.yaml`

## Troubleshooting Commands

```bash
# Check all containers
podman ps -a

# Check container logs
podman logs quay-app --tail 100
podman logs quay-redis --tail 50
podman logs quay-postgres --tail 50

# Check systemd services
systemctl --user status quay-pod
systemctl --user status quay-app
systemctl --user status quay-redis
systemctl --user status quay-postgres

# Test registry login
podman login -u init registry.ocp4.sandbox3377.opentlc.com:8443

# Check disk space
df -h /registry
podman system df
```

## Performance Tuning

### Increase Storage for Large Mirrors

```bash
# Expand /registry partition
lvextend -L +200G /dev/mapper/vg-registry
xfs_growfs /registry
```

### Optimize Podman Storage

```bash
# Edit /etc/containers/storage.conf
[storage.options]
size = "500G"
```

## References

- **Qubinode Scripts**: 
  - https://github.com/Qubinode/qubinode-pipelines/blob/main/mirror-registry/deploy.sh
  - https://github.com/Qubinode/qubinode-pipelines/blob/main/mirror-registry/configure-quay.sh
- **ADR 0017**: Quay Mirror Registry
- **ADR 0023**: Pure Ansible with community.libvirt Migration
- **Red Hat Documentation**: https://access.redhat.com/documentation/en-us/red_hat_quay/

## Lessons Learned

### What Worked
1. ✅ Qubinode rootless podman workarounds (newgidmap/newuidmap)
2. ✅ Sysctl configuration for container networking
3. ✅ XDG_RUNTIME_DIR profile script
4. ✅ Comprehensive container health validation
5. ✅ Using `virt-customize` for SSH key injection

### What Didn't Work
1. ❌ Cloud-init SSH key injection on CentOS Stream 9/10
2. ❌ Cloud-init static IP configuration (needs manual nmcli)
3. ❌ Using `--quayRoot init` (invalid volume name)
4. ❌ Relying only on exit code for validation (misses Redis password issues)

### Future Improvements
- [ ] Investigate alternative cloud-init delivery methods (ConfigDrive vs NoCloud)
- [ ] Test Rocky Linux 9 for better cloud-init compatibility
- [ ] Automate Redis password validation in playbook
- [ ] Add monitoring/alerting for container health
- [ ] Implement automated backup for /registry directory

## Quick Reference

**Successful Deployment Checklist**:
- [x] System configured with rootless podman workarounds
- [x] Sysctl settings applied
- [x] XDG_RUNTIME_DIR configured
- [x] Mirror-registry installed with `--quayRoot /registry`
- [x] All 4 containers running (no restarts)
- [x] Health endpoint returns all services `true`
- [x] No Redis password mismatch errors in logs
- [x] Podman login successful
- [x] Credentials stored securely

**Default Access**:
- **URL**: https://<hostname>:8443
- **User**: init
- **Password**: (generated during install)
- **UI**: https://<hostname>:8443/
- **API**: https://<hostname>:8443/api/v1/
- **Health**: https://<hostname>:8443/health/instance
