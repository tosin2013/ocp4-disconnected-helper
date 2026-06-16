# VyOS Router Deployment Guide

**Reference**: ADR 0025 - VyOS Router as Network Infrastructure Prerequisite  
**Source**: https://tosin2013.github.io/openshift-agent-install/vyos-manual-configuration.html

## Overview

VyOS router provides essential network infrastructure for KVM-based OpenShift disconnected deployments:
- **DNS**: Name resolution for all VMs
- **DHCP**: Automated IP assignment per VLAN
- **VLANs**: Network segmentation (management, OCP, storage)
- **NAT/Firewall**: Security and external connectivity

**This is a mandatory prerequisite** - deploy VyOS BEFORE any other VMs.

## Quick Start

```bash
cd /home/vpcuser/ocp4-disconnected-helper
./hack/deploy-vyos.sh
```

## Deployment Process

### Phase 1: Automated VM Creation (5-10 minutes)

The `deploy-vyos.sh` script will:
1. ✅ Check prerequisites (virt-install, libvirtd, cockpit)
2. ✅ Create libvirt networks (1924, 1925, 1926, 1927, 1928)
3. ✅ Download VyOS 2026.05.30 nightly ISO (~500MB)
4. ✅ Create vyos-router VM (4GB RAM, 2 vCPUs, 20GB disk)
5. ⏳ Display manual configuration instructions
6. ⏳ Wait for router to become accessible (up to 30 minutes)

### Phase 2: Manual Configuration (10-15 minutes)

**Access Cockpit Console**:
1. Open browser: `https://<KVM_HOST_IP>:9090`
2. Login with your system credentials
3. Navigate: **Virtual Machines** → **vyos-router** → **Console** tab

**VyOS Initial Setup**:
```bash
# Login credentials
Username: vyos
Password: vyos

# Step 1: Install VyOS to disk
install image
# Answer prompts:
#   - Install image? Yes
#   - Partition? Auto
#   - Install image? Yes
#   - Default console? No changes
#   - Password for vyos: <set password>
#   - Confirm: <same password>
# VM will shutdown - manually start it again from Cockpit
```

**Start VM Again**:
- In Cockpit: Click **Run** button on vyos-router
- Wait for VM to boot (~1 minute)
- Return to **Console** tab

**Basic Network Configuration**:
```bash
# Login again with: vyos / <password you set>

configure

# Configure external interface
set interfaces ethernet eth0 address 192.168.122.2/24
set interfaces ethernet eth0 description 'Internet-Facing'

# Set default gateway
set protocols static route 0.0.0.0/0 next-hop 192.168.122.1

# Enable SSH for automation
set service ssh port 22
set service ssh listen-address 0.0.0.0

# Save configuration
commit
save
exit
```

**Test Basic Connectivity**:
```bash
# From KVM host
ping 192.168.122.2
ssh vyos@192.168.122.2
```

### Phase 3: Automated VLAN Configuration (5 minutes)

Once SSH is working, the script will automatically apply full VyOS configuration:

```bash
# This happens automatically after router is accessible
# Script downloads: vyos-config.sh
# Then SSHs and runs: vbash /tmp/vyos-config.sh
```

The automated config (`vyos-config-ocp4.sh`) creates:
- **VLAN 1924** (Management): 192.168.10.0/24
  - VyOS Gateway: 192.168.10.1
  - DHCP Range: 192.168.10.10 - 192.168.10.254
  - Static Reservations:
    - registry-vm: 192.168.10.10 (MAC: 52:54:00:10:00:10)
    - aap-vm: 192.168.10.20 (MAC: 52:54:00:10:00:20)
  - DNS domain: ocp4.sandbox3377.opentlc.com
- **VLAN 1925** (OpenShift): 192.168.20.0/24
  - VyOS Gateway: 192.168.20.1
  - DHCP Range: 192.168.20.10 - 192.168.20.254
  - Static Reservations:
    - ocp-master-1: 192.168.20.11 (MAC: 52:54:00:20:00:11)
    - ocp-master-2: 192.168.20.12 (MAC: 52:54:00:20:00:12)
    - ocp-master-3: 192.168.20.13 (MAC: 52:54:00:20:00:13)
    - ocp-worker-1: 192.168.20.21 (MAC: 52:54:00:20:00:21)
    - ocp-worker-2: 192.168.20.22 (MAC: 52:54:00:20:00:22)
- **VLAN 1927** (Storage): 192.168.30.0/24
  - VyOS Gateway: 192.168.30.1
  - DHCP Range: 192.168.30.10 - 192.168.30.254
- **DNS Forwarder**: 161.26.0.10 (IBM Cloud DNS)
- **NAT**: All VLANs masquerade via eth0
- **Firewall**: Rules allowing inter-VLAN communication and external access

## Verification

```bash
# Check VyOS is running
virsh list --all | grep vyos

# Check networks are created
virsh net-list --all

# SSH to VyOS
ssh vyos@192.168.122.2

# Inside VyOS, check config
show configuration
show interfaces
show dhcp server statistics
```

## Troubleshooting

### VM Won't Start
```bash
# Check libvirt logs
sudo journalctl -u libvirtd -f

# Check VM status
virsh dominfo vyos-router

# Force start
virsh start vyos-router
```

### Can't Access Cockpit
```bash
# Check cockpit status
systemctl status cockpit.socket

# Restart if needed
sudo systemctl restart cockpit.socket

# Check firewall
sudo firewall-cmd --list-all
```

### SSH Not Working
```bash
# From VyOS console, check SSH service
show service ssh

# Reconfigure if needed
configure
set service ssh
commit
save
```

### Script Times Out
- The script waits 30 minutes for router at 192.168.122.2
- If manual config takes longer, script will exit
- You can manually complete VyOS setup
- Then manually run: `bash /tmp/vyos-config.sh` on VyOS

## Post-Deployment

Once VyOS is deployed and accessible:

### Update Inventory

Edit `inventory/ibm-cloud.yml`:
```yaml
# Change registry IP to VLAN 10
registry:
  ansible_host: "192.168.10.10"  # Was 192.168.122.24
  
# Add AAP to VLAN 10
aap:
  ansible_host: "192.168.10.20"
```

### Deploy Registry VM

```bash
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml --tags registry
```

Registry VM will now:
- Boot on management VLAN (192.168.10.x)
- Get IP via VyOS DHCP
- Resolve DNS via VyOS
- Route to external via VyOS NAT

## Files Created

- `hack/vyos-router.sh` - Main deployment script (forked from upstream)
- `hack/deploy-vyos.sh` - Wrapper with environment config
- `hack/vyos-config-ocp4.sh` - Custom VyOS configuration (hybrid network scheme)
- `/tmp/vyos-manual-config-instructions.txt` - Console setup guide (generated by deploy-vyos.sh)

## References

- **Upstream Guide**: https://tosin2013.github.io/openshift-agent-install/vyos-manual-configuration.html
- **VyOS Docs**: https://docs.vyos.io/
- **Source Script**: https://github.com/tosin2013/openshift-agent-install/blob/main/hack/vyos-router.sh
- **ADR 0025**: docs/adrs/0025-vyos-router-network-prerequisite.md

## Next Steps

After VyOS deployment:
1. ✅ Update inventory with VLAN IPs
2. ✅ Deploy registry VM on VLAN 10
3. ✅ Deploy AAP VM on VLAN 10
4. ✅ Deploy OpenShift nodes on VLAN 20
