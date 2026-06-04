# OpenShift Disconnected Helper - AI Agent Instructions

## Project Overview

This project automates the deployment of disconnected/air-gapped OpenShift 4 infrastructure on IBM Cloud using Ansible, KVM/libvirt, and VyOS networking. It's designed for enterprise customers who need to mirror OpenShift container images in environments without direct internet access.

**Architecture**: Nested KVM hypervisor on IBM Cloud VSI → VyOS router → Registry VMs → OpenShift clusters

## Project Memory Strategy

This project uses **PMB (Personal Memory Brain)** for persistent architectural and troubleshooting memory across sessions.

### Core Directives

1. **Always Check Memory First**: Before starting a new task or debugging an issue, use `pmb.recall("query")` to search for relevant context, past failures, and architectural constraints.

2. **Document Success**: When you successfully resolve a complex bug or deploy a new component, use `pmb.record_batch` to store the solution:
   ```python
   record_batch(items=[
     {"type": "fact_tree", 
      "main": "Brief description of solution",
      "subfacts": ["Step 1", "Step 2", "Root cause", "Fix applied"],
      "importance": 0.9}
   ])
   ```

3. **ADR Compliance**: Do not make architectural changes without verifying compliance against stored ADRs via PMB. Check `docs/adrs/` and recall relevant decisions.

4. **Store Lessons**: When you discover a project-specific gotcha or convention:
   ```python
   record_batch(items=[
     {"type": "lesson",
      "content": "This repo uses X pattern, never Y",
      "importance": 0.9}
   ])
   ```

5. **Update State**: At the end of significant work sessions, record progress:
   ```python
   record_batch(items=[
     {"type": "activity", 
      "kind": "completed",
      "content": "Summary of work completed",
      "importance": 0.7}
   ])
   ```

### Memory Topics to Track

- **troubleshooting**: Bug fixes and their root causes
- **deployment**: Successful deployment patterns and configurations
- **decisions-ocp4**: Architectural decisions specific to this project
- **context-ocp4**: Project-specific context and state
- **errors-resolved**: Resolved error patterns with solutions

## Technology Stack

### Infrastructure Layer
- **Hypervisor**: KVM/libvirt 11.10.0 + QEMU 10.1.0 (nested virtualization)
- **OS**: CentOS Stream 10 (RHEL 10 compatible)
- **Network**: VyOS router with VLAN segmentation (1924/1925/1927)

### Automation & Configuration
- **Automation**: Ansible 2.16.18 (Python 3.12)
- **Collections**: community.libvirt 2.2.0, ansible.posix 2.2.0
- **Structure**: Atomic roles pattern (ADR 0024 in progress)

### Container Platform
- **Runtime**: Podman 5.8.2 (no Docker)
- **Registry**: Quay mirror-registry (containerized)
- **OCP Tools**: oc 4.21.18, kubectl v1.34.1, oc-mirror 4.21.0

### Networking Architecture
- **VLAN 1924 (Management)**: 192.168.10.0/24 - Registry, AAP, bastion
- **VLAN 1925 (OpenShift)**: 192.168.20.0/24 - Masters and workers
- **VLAN 1927 (Storage)**: 192.168.30.0/24 - NFS, persistent storage
- **VyOS Router**: DNS, DHCP, NAT, firewall for all VLANs

## Critical Architectural Decisions (ADRs)

Review these before making changes:

- **ADR 0024**: Roles and collections architecture (atomic, reusable roles)
- **ADR 0025**: VyOS router as network infrastructure prerequisite
- **ADR 0009**: Secrets management (Ansible Vault → HashiCorp Vault migration)
- **ADR 0021**: Automation platform (Airflow deprecated → AAP 2.5)

See `docs/adrs/` for complete list.

## Known Issues & Solutions

### Cloud-init Static IP on CentOS Stream 9
**Issue**: Cloud-init network-config v2 doesn't reliably apply static IPs on CentOS Stream 9.

**Solution** (Resolved June 3, 2026):
1. Use `gateway4` instead of `routes` in network-config
2. Add `dhcp4: false` explicitly
3. Pass DNS servers as proper JSON: `{"vm_dns_servers":["IP1","IP2"]}`
4. Template must use `{{ vm_dns_servers | to_json }}` not array syntax

### Libvirt Permissions
**Issue**: Ansible fails with "Network not found" when running virsh commands.

**Solution**:
```bash
# Add user to libvirt group
sudo usermod -a -G libvirt vpcuser

# Create polkit rule
sudo tee /etc/polkit-1/rules.d/80-libvirt-vpcuser.rules << 'EOF'
polkit.addRule(function(action, subject) {
    if (action.id == "org.libvirt.unix.manage" &&
        subject.user == "vpcuser") {
            return polkit.Result.YES;
    }
});
EOF

# Set default URI
export LIBVIRT_DEFAULT_URI="qemu:///system"
echo 'export LIBVIRT_DEFAULT_URI="qemu:///system"' >> ~/.bashrc
```

### Mirror-Registry Download URL
**Current URL** (as of June 2026):
```
https://mirror.openshift.com/pub/cgw/mirror-registry/latest/mirror-registry-amd64.tar.gz
```

Old deprecated URL: `https://developers.redhat.com/content-gateway/...` (404 error)

## Known Failure Patterns — v1.0

### Registry Authentication with TLS Certificate Verification Failure
**Pattern**: `podman login` fails with "tls: failed to verify certificate: x509: certificate signed by unknown authority"

**Root Cause**: Mirror-registry v2 auto-generates self-signed CA that is NOT trusted by external systems (podman on hypervisor). When Route53/AWS credentials are available but `ssl_cert_provider: "selfsigned"` is set in inventory, deployment uses untrusted self-signed certs instead of Let's Encrypt.

**Prevention Rules**:
1. **Always check for AWS credentials** before setting ssl_cert_provider:
   ```bash
   ls ~/.aws/credentials && echo "Use letsencrypt" || echo "Use selfsigned"
   ```

2. **Never skip certificate validation** in production:
   - ❌ NO: `--skip-tls-verify`, `--insecure-registry`, bypassing validation
   - ✅ YES: Let's Encrypt (cloud) or properly-distributed self-signed CA (disconnected)

3. **Certificate setup MUST run before mirror-registry install**:
   - Sequence: `setup_certificates.yml` → `install_mirror_registry.yml`
   - Mirror-registry v2 requires `--sslCert` and `--sslKey` at install time
   - Post-install certificate injection is NOT supported

4. **Deployment context matters**:
   - IBM Cloud / AWS / GCP = Route53 available → use Let's Encrypt
   - True air-gapped on-premise = no Route53 → use self-signed CA
   - **Auto-detect**: Now automatic via defaults (checks `~/.aws/credentials` existence)

5. **Run preflight validation** before full deployment:
   ```bash
   ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml --tags validate
   ```

**Verification**:
After deployment, test authentication:
```bash
export XDG_RUNTIME_DIR=/run/user/$(id -u)
echo "$PASSWORD" | podman login --username init --password-stdin $REGISTRY_URL
```

**Incident Reference**: See PMB tag: `hardening, v1.0` (ULID: `0019e93110c6e_7c3ad77a`)

**Related ADRs**:
- ADR 0016: Trusted Certificate Management (dual-path: Let's Encrypt + self-signed)
- ADR 0017: Quay Mirror Registry (certificate injection via --sslCert/--sslKey)

## Development Workflow

### Main Entrypoint
```bash
# Deploy everything
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml

# Deploy only registry
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml --tags registry

# Deploy only AAP
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml --tags aap
```

### Deployment Structure
```
site.yml
├── deploy-registry.yml
│   └── registry_vm role
│       ├── common_vm (VM provisioning)
│       ├── install_mirror_registry.yml
│       ├── setup_auth.yml
│       └── verify.yml
└── deploy-aap.yml (planned)
```

### Role Design Principles (ADR 0024)
1. **Atomic**: Each role does one thing completely
2. **Idempotent**: Safe to run multiple times
3. **Delegated**: VM provisioning uses `delegate_to: localhost`
4. **Two-phase**: Provision (local/libvirt) → Configure (SSH)

## Testing & Verification

### Registry Deployment
```bash
# Check VM is running
export LIBVIRT_DEFAULT_URI="qemu:///system"
virsh list
virsh domifaddr registry

# Test SSH access
ssh admin@192.168.10.10 "hostname && ip addr show eth0"

# Verify registry health
curl -k https://192.168.10.10:8443/health/instance
```

### VyOS Router Verification
```bash
# Check VyOS is accessible
ssh vyos@192.168.122.2 "show version"

# Verify VLAN interfaces
ssh vyos@192.168.122.2 "show interfaces"

# Test connectivity from VLANs
ssh vyos@192.168.122.2 "ping 1.1.1.1 source-address 192.168.10.1"
```

## Security & Secrets

### Current (Development)
- Ansible Vault for sensitive variables
- SSH keys automatically injected via cloud-init
- Self-signed certificates for testing

### Planned (Production - ADR 0009)
- HashiCorp Vault for secrets management
- Let's Encrypt DNS-01 validation
- Mutual TLS for service-to-service

### Pull Secret Management
```bash
# Store Red Hat pull secret
cp ~/rh-pull-secret.json /root/pull-secret.json

# Combined pull secret (includes registry auth)
# Generated automatically by setup_auth.yml
```

## Common Commands

### VM Management
```bash
# List VMs
virsh list --all

# Console access (troubleshooting)
virsh console <vm-name>

# Destroy and undefine VM
virsh destroy <vm-name>
virsh undefine <vm-name>
rm -f /data/libvirt-images/<vm-name>*
```

### Ansible Debugging
```bash
# Verbose output
ansible-playbook -vvv ...

# Check mode (dry run)
ansible-playbook --check ...

# Specific host
ansible-playbook --limit registry ...

# Skip provisioning (re-run configuration only)
ansible-playbook --skip-tags provision ...
```

### Network Troubleshooting
```bash
# Check routes to VLANs
ip route | grep 192.168

# Add route to VLAN via VyOS
sudo ip route add 192.168.10.0/24 via 192.168.122.2

# Test connectivity
ping -c 3 192.168.10.1  # VyOS management gateway
ping -c 3 192.168.10.10 # Registry VM
```

## Important File Locations

### Configuration
- **Inventory**: `inventory/ibm-cloud.yml`
- **ADRs**: `docs/adrs/`
- **Roles**: `roles/common_vm/`, `roles/registry_vm/`
- **Templates**: `roles/*/templates/`

### Runtime Data
- **VM Images**: `/data/libvirt-images/`
- **Cloud-init ISOs**: `/data/libvirt-images/*-cloud-init.iso`
- **Mirror Storage**: `/data/ocp-mirror/`
- **Logs**: `/data/logs/`

### VM Paths (on registry VM)
- **Mirror-registry**: `/opt/mirror-registry/`
- **Credentials**: `/opt/mirror-registry/credentials.txt`
- **Storage**: `/opt/mirror-registry/quay-storage/`

## Documentation

- **Getting Started**: `docs/GETTING_STARTED.md`
- **Libvirt Permissions**: `docs/LIBVIRT_PERMISSIONS.md`
- **VyOS Deployment**: `docs/VYOS_DEPLOYMENT.md`
- **Troubleshooting**: `docs/TROUBLESHOOTING.md`
- **Architecture**: `docs/ROLES_ARCHITECTURE.md`

## References

- [OpenShift 4.21 Disconnected Documentation](https://docs.openshift.com/container-platform/4.21/installing/disconnected_install/installing-mirroring-creating-registry.html)
- [Mirror Registry GitHub](https://github.com/quay/mirror-registry)
- [VyOS Documentation](https://docs.vyos.io/)
- [Ansible Community Libvirt](https://docs.ansible.com/ansible/latest/collections/community/libvirt/)

## AI Agent Best Practices

1. **Read ADRs first**: Before proposing architectural changes, check `docs/adrs/`
2. **Use PMB recall**: Search for similar past issues before debugging
3. **Verify with tests**: After fixing network issues, test connectivity end-to-end
4. **Document solutions**: Store complex troubleshooting solutions in PMB
5. **Follow role patterns**: New roles should follow ADR 0024 structure
6. **Check inventory**: VM network settings are in `inventory/ibm-cloud.yml`
7. **Preserve security**: Never skip cert validation or disable security features
8. **Use playbooks**: Don't run raw virsh/ansible commands, use playbooks
