# OpenShift Disconnected Helper - AI Agent Instructions

## Project Overview

This project automates the deployment of disconnected/air-gapped OpenShift 4 infrastructure on IBM Cloud using Ansible, KVM/libvirt, and VyOS networking. It's designed for enterprise customers who need to mirror OpenShift container images in environments without direct internet access.

**Architecture**: Nested KVM hypervisor on IBM Cloud VSI → VyOS router → Registry VMs → OpenShift clusters

## Security Rules - MANDATORY

### Rule 1: NEVER Commit Credentials to Git

**Absolutely forbidden in any file committed to Git:**
- Real service account credentials (Red Hat, AWS, Azure, Quay)
- JWT tokens, API keys, passwords
- Private keys, certificates (except `.example` files)
- AAP installer inventory files with real credentials

**Always use placeholders in documentation:**
```
❌ registry_username='12216224|ansible-execution-environment'
✅ registry_username='<YOUR-ORG-ID>|<YOUR-SERVICE-ACCOUNT-NAME>'
```

**Pre-commit hook protection:** The `.git/hooks/pre-commit` script automatically blocks commits containing credentials. If it triggers:
1. Replace real credentials with placeholders
2. Store real credentials in Ansible Vault or environment variables
3. Never use `--no-verify` to bypass the check

**Safe credential storage locations:**
- Ansible Vault: `extra_vars/rhel-subscription-secrets.yml` (encrypted)
- Environment variables: `export RH_REGISTRY_USERNAME='...'`
- AAP installer inventory: `/opt/ansible-automation-platform/installer/inventory` (chmod 600, not in Git)

**Related:** ADR-0031, `.gitignore` rules, `docs/SECURITY.md`

---

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

### AAP 2.6 Project Sync Failure - Control Plane EE Registry Authentication
**Pattern**: AAP project sync fails with "Project update failed" or "unable to retrieve auth token: unauthorized"

**Root Cause**: Control Plane Execution Environment is a **system-managed resource** that cannot be configured with registry credentials after deployment via Web UI or API. Registry credentials for `registry.redhat.io` must be in the AAP installer inventory file **before running `setup.sh`** during initial deployment.

**Prevention Rules**:
1. **Always configure registry credentials in installer inventory** before running `setup.sh`:
   ```bash
   # Edit /opt/ansible-automation-platform/installer/inventory
   # Add to [all:vars] section:
   registry_url='registry.redhat.io'
   registry_username='<org-id>|<service-account-name>'
   registry_password='<service-account-token>'
   ```

2. **Run preflight validation** before AAP deployment:
   ```bash
   ./scripts/preflight-aap-registry-check.sh
   ```

3. **Never attempt to configure Control Plane EE via Web UI or API** post-deployment:
   - ❌ NO: ansible.controller.execution_environment API (returns HTTP 403 Forbidden)
   - ❌ NO: Web UI → Administration → Execution Environments → Control Plane EE (read-only)
   - ✅ YES: Installer inventory + setup.sh (only method that works)

4. **Custom EEs are supplemental, not a replacement**:
   - Custom EEs are for job template execution (with extra collections/tools)
   - Control Plane EE is for project syncs (system-managed, needs separate config)
   - Both need registry credentials, but via different methods

5. **Credential rotation requires re-running setup.sh**:
   - Update credentials in installer inventory
   - Re-run `./setup.sh -i inventory` (5-10 minute process)
   - All AAP containers (Gateway, Controller, Database) reconfigure automatically

**Verification**:
After deployment with credentials configured:
```bash
# Test project sync
curl -sk -u admin:<password> \
  "https://aap.example.com/api/controller/v2/project_updates/?order_by=-id" | \
  jq -r '.results[0].status'
# Expected: "successful"
```

**Incident Reference**: See PMB tag: `hardening, v2.6` (ULID: `0019eacef79b0_1bc6597a`)

**Related ADRs**:
- ADR 0031: AAP 2.6 Installer Registry Credential Configuration (mandatory requirement)
- ADR 0029: Custom Execution Environment (supplemental for job templates)
- ADR 0028: AAP 2.6 Multi-Node Password Architecture
- ADR 0021: Deprecate Airflow and Adopt AAP

**Related Files**:
- `scripts/preflight-aap-registry-check.sh`: Preflight validation for registry credentials
- `playbooks/deploy-aap-multi-node.yml`: Includes preflight check before setup.sh
- `docs/AAP_DEPLOYMENT_GUIDE.md`: Step-by-step deployment with credential configuration
- `docs/hardening/aap-control-plane-ee-registry-v2.6-2026-06-09.md`: Complete incident analysis

---

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

---

### oc-mirror Playbook Returns Cached Failure ("Port 55000 Already Bound")
**Pattern**: `ansible-playbook download-to-disk-v2.yml` fails immediately (<5 seconds) with error: `[ERROR] [Executor] 55000 is already bound and cannot be used`

**Root Cause**: Stale Ansible async cache at `/root/.ansible_async/` (or `~/.ansible_async/`) returning cached failure from a previous playbook run. The playbook does NOT actually execute - it returns the cached result immediately with the original job ID (e.g., `j571283734101.416643`).

**Prevention Rules**:
1. **Always clear async cache after failed oc-mirror runs**:
   ```bash
   sudo rm -rf /root/.ansible_async/*
   # Or use the cleanup script:
   sudo ./scripts/clear-async-cache.sh
   ```

2. **Detect cached failures by execution time**:
   - Real oc-mirror runs take 1-60 minutes depending on image count
   - Cached failures return in <5 seconds
   - If playbook fails instantly with network/port errors, suspect async cache

3. **Verify port is actually free before assuming process conflict**:
   ```bash
   sudo ss -tlnp | grep 55000
   ps aux | grep oc-mirror
   ```
   If port is free and no process is running, it's async cache, not a real conflict.

4. **Check for preflight warning** (playbooks/download-to-disk-v2.yml v1.1+):
   The playbook warns about stale async cache during preflight. Heed the warning and clear cache before proceeding.

**Verification**:
After clearing async cache, playbook should:
- Take >30 seconds to start (installing prerequisites)
- Show oc-mirror progress messages
- Complete successfully with "✓ N / N images mirrored successfully"

**Incident Reference**: See PMB tag: `hardening, v1.0`, incident summary ULID: `0019e9367f9c1_8e5c2a4b`

**Related ADRs**:
- ADR 0003: oc-mirror v2 for Image Mirroring (updated with Ansible async constraints)
- ADR 0022: Standalone Architecture (pure Ansible with async for long-running operations)
- ADR 0023: Pure Ansible with community.libvirt

**Related Docs**:
- `docs/TROUBLESHOOTING.md`: Full troubleshooting steps
- `docs/hardening/oc-mirror-async-cache-v1.0-2026-06-04.md`: Complete incident analysis

---

### AAP 2.6 Multi-Node Login Failure ("Invalid username or password")
**Pattern**: Web UI login at https://aap.sandbox3377.opentlc.com returns "Invalid username or password" despite entering correct credentials. API authentication with same credentials works.

**Root Cause**: AAP 2.6 multi-node architecture uses **two separate admin passwords**:
- `automationgateway_admin_password` - For **Web UI login** (Gateway component)
- `admin_password` - For **Controller API authentication** (Controller component)

**Prevention Rules**:
1. **Always use Gateway password for Web UI login**:
   ```
   URL: https://aap.sandbox3377.opentlc.com
   Username: admin
   Password: <automationgateway_admin_password from secrets file>
   ```

2. **Use Controller password for API authentication**:
   ```bash
   curl -u admin:<admin_password> https://aap.../api/controller/v2/ping/
   ```

3. **Run password validation before deployment**:
   ```bash
   ansible-playbook -i inventory/ibm-cloud.yml playbooks/validate-aap-passwords.yml \
     -e@extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass
   ```

4. **Set different passwords for Gateway and Controller** (security best practice):
   - Do NOT use the same password for both components
   - Validation playbook enforces this separation

5. **Check deployment summary for password reference**:
   The deployment playbook displays which password to use for Web UI vs API

**Verification**:
After deployment, test both authentication contexts:
```bash
# Test Web UI (Gateway) - Open in browser
https://aap.sandbox3377.opentlc.com
# Login: admin / <automationgateway_admin_password>

# Test Controller API
curl -u admin:<admin_password> https://aap.../api/controller/v2/ping/
```

**Incident Reference**: See PMB tag: `hardening, v1.0` (ULID: `0019e9806e6c4_72f49a83`)

**Related ADRs**:
- ADR 0028: AAP 2.6 Multi-Node Password Architecture (password taxonomy and validation)
- ADR 0021: Deprecate Airflow and Adopt AAP (decision to use AAP 2.6)
- ADR 0009: Secrets Management (password storage via Ansible Vault)

**Related Files**:
- `extra_vars/rhel-subscription-secrets.yml.example`: Password architecture documentation
- `playbooks/validate-aap-passwords.yml`: Preflight password validation
- `docs/hardening/aap-multi-node-password-v1.0-2026-06-05.md`: Complete incident analysis

---

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

### Operator Validation Workflow (ADR 0034)
```bash
# 1. Discover operators using CLI tool
./scripts/discover-operators.sh --search storage

# 2. Create extra_vars with operators
# (Use preset from extra_vars/operators/ or create custom)

# 3. Validate operator selection BEFORE mirroring
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml

# 4. Mirror operators (after successful validation)
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/operators/storage-operators.yml

ansible-playbook playbooks/push-to-registry-v2.yml \
  -e @extra_vars/operators/storage-operators.yml
```

**Key Features**:
- ✅ Pre-flight validation catches typos before expensive mirroring
- ✅ Fuzzy matching suggests correct operator names
- ✅ Catalog cache (24h TTL) for fast validation
- ✅ Discovery tool for operator browsing
- ✅ Curated presets for common use cases (storage, observability, networking)
- ✅ AAP workflow integration as preflight node

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
