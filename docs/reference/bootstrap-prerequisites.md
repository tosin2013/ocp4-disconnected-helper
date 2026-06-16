# Bootstrap Prerequisites Reference

Complete reference for bootstrap layer components that must exist before AAP workflows can execute.

---

## Bootstrap Architecture

**Definition**: Infrastructure components that AAP depends on to function.

**Why manual deployment**: AAP cannot deploy its own prerequisites (bootstrap paradox). These components must exist *before* AAP can orchestrate workflows.

See [Bootstrap vs Workflow Layers](../explanations/bootstrap-vs-workflow-layers.md) for architectural rationale.

---

## Component 1: VyOS Router

### Purpose

Network routing and DNS services for VM infrastructure.

### Requirements

| Requirement | Value |
|-------------|-------|
| **VM Resources** | 2 vCPU, 4 GB RAM, 20 GB disk |
| **Network** | 2 interfaces (external + internal) |
| **VyOS Version** | 1.4 (rolling release) |
| **VLAN Support** | Yes (VLANs 1924, 1925, 1927) |

### Configuration

**Network Interfaces**:
- `eth0` (192.168.122.2/24) - External (hypervisor virbr0 bridge)
- `eth1.1924` (192.168.10.1/24) - Management VLAN
- `eth1.1925` (192.168.20.1/24) - OpenShift VLAN
- `eth1.1927` (192.168.30.1/24) - Storage VLAN

**Services Provided**:
- NAT gateway for VMs
- DHCP server for VMs
- DNS forwarder to upstream DNS
- Firewall rules for VLAN isolation

### Deployment

**Playbook**: `playbooks/deploy-vyos.yml`

**Execution**:
```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-vyos.yml
```

**Estimated Time**: 5-10 minutes

### Verification

```bash
# Check VyOS is running
virsh list | grep vyos

# Test SSH access
ssh vyos@192.168.122.2 "show version"

# Verify VLAN interfaces
ssh vyos@192.168.122.2 "show interfaces"

# Test connectivity from VLAN
ssh vyos@192.168.122.2 "ping 1.1.1.1 source-address 192.168.10.1"
```

### Dependencies

**Before VyOS**:
- ✅ Hypervisor (IBM Cloud VSI) operational
- ✅ KVM/libvirt installed and configured
- ✅ virbr0 bridge (192.168.122.1/24) exists

**After VyOS**:
- ✅ DNS services available
- ✅ VM network connectivity possible
- ✅ AAP deployment can proceed

---

## Component 2: DNS Services

### Purpose

Name resolution for `aap.sandbox3377.opentlc.com` and other infrastructure FQDNs.

### Options

#### Option A: AWS Route53 (Cloud Deployments)

**When to use**: IBM Cloud or AWS deployments with public DNS

**Requirements**:
- AWS account with Route53 access
- Hosted zone for domain (e.g., `sandbox3377.opentlc.com`)
- AWS credentials configured (`~/.aws/credentials`)

**Deployment**:
```bash
ansible-playbook playbooks/setup-route53-dns.yml \
  -e route53_zone_id=Z1234567890ABC \
  -e aap_fqdn=aap.sandbox3377.opentlc.com \
  -e aap_ip=10.241.64.9
```

**Records Created**:
| Record | Type | Value | TTL |
|--------|------|-------|-----|
| `aap.sandbox3377.opentlc.com` | A | `10.241.64.9` | 300 |
| `registry.sandbox3377.opentlc.com` | A | `192.168.10.10` | 300 |

#### Option B: FreeIPA (On-Premise Deployments)

**When to use**: On-premise deployments with existing FreeIPA

**Requirements**:
- FreeIPA server accessible from hypervisor
- FreeIPA admin credentials
- Domain delegated to FreeIPA

**Deployment**:
```bash
ansible-playbook playbooks/setup-freeipa-dns.yml \
  -e freeipa_server=ipa.example.com \
  -e freeipa_admin_password=SecurePassword123!
```

#### Option C: VyOS dnsmasq (Minimal)

**When to use**: Lab/testing environments, no external DNS available

**Limitation**: Only works for VMs on VyOS-managed VLANs, not external access

**Configuration**: Included in `playbooks/deploy-vyos.yml`

### Verification

```bash
# Test DNS resolution
dig +short aap.sandbox3377.opentlc.com

# Expected: 10.241.64.9

# Test from VyOS
ssh vyos@192.168.122.2 "nslookup aap.sandbox3377.opentlc.com"
```

### Dependencies

**Before DNS**:
- ✅ VyOS router operational (Option C only)
- ✅ AWS credentials configured (Option A only)
- ✅ FreeIPA server accessible (Option B only)

**After DNS**:
- ✅ `aap.sandbox3377.opentlc.com` resolves correctly
- ✅ AAP deployment can use FQDN
- ✅ Let's Encrypt DNS-01 validation possible (Option A only)

---

## Component 3: Ansible Automation Platform 2.6

### Purpose

Workflow orchestration platform for registry infrastructure and image mirroring.

### Requirements

| Requirement | Value |
|-------------|-------|
| **OS** | RHEL 9.4+ or CentOS Stream 9 |
| **CPU** | 4 vCPU minimum, 8 recommended |
| **RAM** | 16 GB minimum, 32 GB recommended |
| **Disk** | 60 GB minimum, 100 GB recommended |
| **Network** | Access to `registry.redhat.io` for container images |
| **FQDN** | DNS A record for `aap.sandbox3377.opentlc.com` |

### Configuration

**Multi-Node Architecture**:
- 1 Controller node
- 1 Gateway node (Web UI)
- 1 PostgreSQL database

**Passwords** (see [ADR-0028](../adrs/0028-aap-multi-node-password-architecture.md)):
- `admin_password` - Controller API password
- `automationgateway_admin_password` - Gateway Web UI password
- `pg_password` - PostgreSQL database password

**Registry Credentials** (see [ADR-0031](../adrs/0031-aap-installer-registry-credentials.md)):
- Must be configured in installer inventory BEFORE running `setup.sh`
- Required for Control Plane Execution Environment

### Deployment

**Playbook**: `playbooks/deploy-aap-multi-node.yml`

**Execution**:
```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap-multi-node.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Estimated Time**: 15-25 minutes

### Verification

```bash
# Test Web UI access
curl -k https://aap.sandbox3377.opentlc.com/

# Expected: AAP login page HTML

# Test Controller API
curl -sk -u admin:"$ADMIN_PASSWORD" \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/ping/ | jq .version

# Expected: "4.7.12" or similar

# Test Gateway authentication
# Login at: https://aap.sandbox3377.opentlc.com
# Username: admin
# Password: $GATEWAY_PASSWORD (from automationgateway_admin_password)
```

### Dependencies

**Before AAP**:
- ✅ VyOS router operational (provides network routing)
- ✅ DNS configured (aap.sandbox3377.opentlc.com resolves)
- ✅ RHEL subscription or activation key available
- ✅ Red Hat Registry credentials available

**After AAP**:
- ✅ Workflow orchestration available
- ✅ Can deploy Workflow 1 (Registry Infrastructure)
- ✅ Can deploy Workflow 2 (Image Mirroring)

---

## Bootstrap Deployment Order

**Mandatory Sequence**:

```
Step 1: VyOS Router
  ↓
Step 2: DNS Services (Route53 or FreeIPA)
  ↓
Step 3: Ansible Automation Platform 2.6
  ↓
✓ Bootstrap Complete → Workflows can now execute
```

**Why this order**:
1. VyOS provides network routing needed for VM connectivity
2. DNS provides name resolution needed for AAP FQDN
3. AAP provides workflow orchestration needed for automated deployments

**Do NOT skip steps** - each component depends on the previous.

---

## Bootstrap Deployment Script

### Automated Bootstrap

```bash
#!/bin/bash
# scripts/bootstrap-infrastructure.sh

set -euo pipefail

echo "=== OpenShift Disconnected Helper - Bootstrap Deployment ==="
echo ""

# Step 1: Deploy VyOS
echo "Step 1/3: Deploying VyOS router..."
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-vyos.yml
echo "✓ VyOS deployed"
echo ""

# Step 2: Configure DNS
echo "Step 2/3: Configuring DNS services..."
if [ -f ~/.aws/credentials ]; then
  echo "AWS credentials found - using Route53"
  ansible-playbook playbooks/setup-route53-dns.yml \
    -e route53_zone_id="${ROUTE53_ZONE_ID:-Z1234567890ABC}" \
    -e aap_fqdn=aap.sandbox3377.opentlc.com \
    -e aap_ip=10.241.64.9
else
  echo "AWS credentials not found - using VyOS dnsmasq"
  echo "Warning: DNS will only work for VMs on VyOS VLANs"
fi
echo "✓ DNS configured"
echo ""

# Step 3: Deploy AAP
echo "Step 3/3: Deploying Ansible Automation Platform..."
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap-multi-node.yml \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
echo "✓ AAP deployed"
echo ""

echo "=== Bootstrap Complete ==="
echo ""
echo "Next steps:"
echo "1. Login to AAP Web UI: https://aap.sandbox3377.opentlc.com"
echo "   Username: admin"
echo "   Password: (automationgateway_admin_password from vault)"
echo ""
echo "2. Configure workflows:"
echo "   ansible-playbook playbooks/aap-configuration/configure-infrastructure-workflow.yml"
echo "   ansible-playbook playbooks/aap-configuration/configure-mirroring-workflow.yml"
echo ""
echo "3. Execute Workflow 1 from AAP Web UI: Resources → Templates → Workflow 1"
```

**Usage**:
```bash
chmod +x scripts/bootstrap-infrastructure.sh
./scripts/bootstrap-infrastructure.sh
```

---

## Bootstrap Validation

### Preflight Checks

Before starting bootstrap deployment:

```bash
# Check hypervisor resources
ansible-playbook playbooks/validate-hypervisor.yml

# Expected output:
# ✓ CPU: 48 cores available (8+ required)
# ✓ RAM: 188 GB available (32+ required)
# ✓ Disk: 500 GB available (200+ required)
# ✓ Libvirt: Operational
# ✓ KVM: Nested virtualization enabled
```

### Post-Deployment Validation

After bootstrap complete:

```bash
# Validate all bootstrap components
ansible-playbook playbooks/validate-bootstrap.yml

# Expected output:
# ✓ VyOS: Running, SSH accessible
# ✓ DNS: aap.sandbox3377.opentlc.com resolves to 10.241.64.9
# ✓ AAP: Web UI accessible at https://aap.sandbox3377.opentlc.com
# ✓ AAP API: Controller API responds to /ping/
# ✓ Network: VMs can reach internet via VyOS NAT
```

---

## Troubleshooting

### VyOS Deployment Fails

**Symptom**: `playbooks/deploy-vyos.yml` fails with "Cannot reach VyOS"

**Common Causes**:
1. Libvirt permission issues
2. virbr0 bridge not configured
3. Nested KVM not enabled

**Solution**:
```bash
# Check libvirt permissions
export LIBVIRT_DEFAULT_URI="qemu:///system"
virsh list --all

# Verify virbr0 bridge
ip addr show virbr0

# Check nested KVM
cat /sys/module/kvm_intel/parameters/nested
# Expected: Y or 1
```

### DNS Resolution Fails

**Symptom**: `dig aap.sandbox3377.opentlc.com` returns NXDOMAIN

**Common Causes**:
1. Route53 zone ID incorrect
2. AWS credentials missing
3. DNS propagation delay

**Solution**:
```bash
# Verify Route53 zone
aws route53 list-hosted-zones | jq -r '.HostedZones[] | "\(.Id) \(.Name)"'

# Check DNS propagation
dig @8.8.8.8 aap.sandbox3377.opentlc.com

# Fallback: Add to /etc/hosts temporarily
echo "10.241.64.9 aap.sandbox3377.opentlc.com" | sudo tee -a /etc/hosts
```

### AAP Deployment Fails

**Symptom**: `playbooks/deploy-aap-multi-node.yml` fails at "Run setup.sh"

**Common Causes**:
1. RHEL subscription not activated
2. Registry credentials missing from installer inventory
3. Insufficient disk space

**Solution**:
```bash
# Verify RHEL subscription
sudo subscription-manager status

# Check registry credentials in installer inventory
grep -E "(registry_url|registry_username)" \
  /opt/ansible-automation-platform/installer/inventory

# Check disk space
df -h /opt
```

---

## Cost and Time Estimates

| Component | Deployment Time | Monthly Cost (IBM Cloud) |
|-----------|-----------------|--------------------------|
| VyOS Router | 5-10 minutes | $0 (on hypervisor) |
| Route53 DNS | 2-5 minutes | $0.50 per hosted zone |
| AAP 2.6 | 15-25 minutes | $0 (on hypervisor) |
| **Total** | **25-40 minutes** | **$0.50/month** |

**Note**: Cost assumes AAP deployed on existing hypervisor VM, not dedicated infrastructure.

---

## Related Documentation

- [Bootstrap vs Workflow Layers](../explanations/bootstrap-vs-workflow-layers.md)
- [Getting Started with AAP Workflows](../tutorials/getting-started-with-aap-workflows.md)
- [ADR-0025: VyOS Router Network Infrastructure](../adrs/0025-vyos-router-network-prerequisite.md)
- [ADR-0028: AAP 2.6 Multi-Node Password Architecture](../adrs/0028-aap-multi-node-password-architecture.md)
- [ADR-0031: AAP Installer Registry Credentials](../adrs/0031-aap-installer-registry-credentials.md)
