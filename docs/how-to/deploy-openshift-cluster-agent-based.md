# How to Deploy OpenShift Cluster with Agent-Based Installer

Complete guide for deploying OpenShift clusters using the Agent-Based Installer in both **KVM/libvirt** and **bare metal** environments.

---

## Overview

The Agent-Based Installer creates a **bootable ISO** containing all cluster configuration and installation files. This approach works across environments:

- **KVM/libvirt**: VMs boot from ISO, automated provisioning via Ansible
- **Bare Metal**: Physical servers boot from ISO (USB, iDRAC, BMC)
- **Disconnected**: All container images pulled from local mirror registry

**Supported Topologies**:
- **SNO (Single-Node)**: 1 node, 32GB RAM, 8 vCPU
- **Compact (3-node)**: 3 control plane (schedulable), 24GB RAM each
- **HA (6+ nodes)**: 3 control plane + 2+ workers

---

## Prerequisites

### Common (All Environments)

1. **OpenShift Install Binary**:
   ```bash
   OCP_VERSION="4.21.0"
   cd /tmp
   wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-install-linux.tar.gz
   tar -xzf openshift-install-linux.tar.gz
   sudo mv openshift-install /usr/local/bin/
   openshift-install version
   ```

2. **Pull Secret**:
   - Download from: https://console.redhat.com/openshift/install/pull-secret
   - Save to `/root/pull-secret.json` (or path in cluster config)

3. **Mirror Registry** (Disconnected):
   - Quay mirror-registry deployed and accessible
   - Container images mirrored via oc-mirror
   - See: [Configure Operator Catalog for Disconnected](configure-operator-catalog-for-disconnected.md)

4. **DNS Configuration**:
   - **KVM**: Automated via dnsmasq or Route53
   - **Bare Metal**: Manual DNS records required (see DNS section)

### KVM/libvirt Environment (Automated)

5. **Hypervisor Resources**:
   - SNO: 32GB RAM, 8 vCPU available
   - Compact: 72GB RAM (3 × 24GB), 18 vCPU
   - HA: 144GB+ RAM, 54+ vCPU

6. **libvirt/KVM Installed**:
   ```bash
   sudo dnf install -y libvirt qemu-kvm
   sudo systemctl enable --now libvirtd
   virsh version
   ```

7. **Ansible Collections**:
   ```bash
   ansible-galaxy collection install community.libvirt
   ansible-galaxy collection install ansible.posix
   ```

### Bare Metal Environment (Manual)

5. **Physical Servers**:
   - IPMI/iDRAC/BMC access for remote boot
   - Network boot (PXE) or USB boot capability
   - UEFI firmware (recommended) or legacy BIOS

6. **Network Configuration**:
   - Static IP allocation plan
   - MAC addresses documented
   - VLAN configuration (if required)

7. **Boot Media**:
   - USB drive (8GB+) for ISO, OR
   - iDRAC/BMC virtual media mount, OR
   - Network boot server (PXE/iPXE)

---

## Deployment Methods

### Method 1: KVM/libvirt (Fully Automated)

**Complete automation with Ansible** - VMs provisioned, ISO mounted, installation monitored.

#### Step 1: Select Cluster Configuration

Choose a cluster topology configuration file:

```bash
# SNO with Quay registry
CLUSTER_CONFIG="extra_vars/cluster-configs/sno-quay.yml"

# 3-node Compact with Harbor registry
CLUSTER_CONFIG="extra_vars/cluster-configs/compact-3node-harbor.yml"

# HA with JFrog registry
CLUSTER_CONFIG="extra_vars/cluster-configs/ha-cluster-jfrog.yml"
```

#### Step 2: Review Configuration

```bash
cat $CLUSTER_CONFIG
```

Verify:
- `cluster_name`: Unique cluster identifier
- `base_domain`: DNS domain
- `registry_url`: Mirror registry URL
- `api_vip`, `ingress_vip`: Available IP addresses
- `control_plane_nodes`, `worker_nodes`: IP/MAC addresses (multi-node)

#### Step 3: Deploy Cluster

**Full deployment** (all phases):
```bash
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @${CLUSTER_CONFIG}
```

**Phase-specific deployment**:
```bash
# Validation only
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @${CLUSTER_CONFIG} \
  --tags phase0

# ISO generation only
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @${CLUSTER_CONFIG} \
  --tags phase1,phase2,phase3

# DNS + VMs + Monitoring
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @${CLUSTER_CONFIG} \
  --tags phase4,phase5,phase6
```

#### Step 4: Monitor Installation

**Automated monitoring** (included in phase6):
- Bootstrap completion (20-40 minutes)
- Control plane ready (5-10 minutes)
- Worker nodes join (HA only, 5-15 minutes)
- Cluster operators available (10-20 minutes)

**Manual monitoring**:
```bash
# Check VMs running
virsh list

# Watch installation logs
tail -f /root/openshift-install-<cluster>/.openshift_install.log

# Check cluster status (after bootstrap)
export KUBECONFIG=/data/ocp-credentials/<cluster>-kubeconfig
oc get nodes
oc get co  # Cluster operators
```

#### Step 5: Access Cluster

Credentials exported to `/data/ocp-credentials/`:

```bash
export KUBECONFIG=/data/ocp-credentials/<cluster>-kubeconfig
oc whoami
oc get nodes

# Web Console
cat /data/ocp-credentials/<cluster>-access-instructions.txt
# Open: https://console-openshift-console.apps.<cluster>.<domain>
# Login: kubeadmin / <password from file>
```

---

### Method 2: Bare Metal (Manual Boot + Automated Monitoring)

**Ansible generates ISO, you boot physical servers, Ansible monitors installation.**

#### Step 1: Generate Bootable ISO

Create cluster configuration for bare metal:

```bash
# Copy example and customize
cp extra_vars/cluster-configs/compact-3node-quay.yml \
   extra_vars/cluster-configs/my-baremetal-cluster.yml

# Edit configuration
vi extra_vars/cluster-configs/my-baremetal-cluster.yml
```

**Critical bare metal settings**:

```yaml
# Disable VM provisioning (manual bare metal boot)
provision_vms: false

# Node definitions with actual hardware MAC addresses
control_plane_nodes:
  - name: "master-0"
    ip: "192.168.10.30"
    mac: "AA:BB:CC:DD:EE:01"  # ← Physical NIC MAC address
  - name: "master-1"
    ip: "192.168.10.31"
    mac: "AA:BB:CC:DD:EE:02"
  - name: "master-2"
    ip: "192.168.10.32"
    mac: "AA:BB:CC:DD:EE:03"

# Workers (HA only)
worker_nodes:
  - name: "worker-0"
    ip: "192.168.10.40"
    mac: "AA:BB:CC:DD:EE:10"
  # ... more workers
```

**Generate ISO**:
```bash
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @extra_vars/cluster-configs/my-baremetal-cluster.yml \
  --tags phase1,phase2,phase3
```

**Output**: `/data/iso/my-baremetal-cluster-agent.x86_64.iso` (~1.2GB)

#### Step 2: Configure DNS (Manual)

**Option A: External DNS Server** (Recommended for production):

Add A records for:
```
api.<cluster>.<domain>           → <api_vip>
*.apps.<cluster>.<domain>        → <ingress_vip>
master-0.<cluster>.<domain>      → <node_0_ip>
master-1.<cluster>.<domain>      → <node_1_ip>
master-2.<cluster>.<domain>      → <node_2_ip>
# ... worker nodes
```

**Option B: dnsmasq (Development)**:
```bash
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @extra_vars/cluster-configs/my-baremetal-cluster.yml \
  --tags phase4
```

**Verify DNS**:
```bash
dig +short api.my-baremetal-cluster.example.com
# Should return: <api_vip>

dig +short test.apps.my-baremetal-cluster.example.com
# Should return: <ingress_vip>
```

#### Step 3: Boot Physical Servers from ISO

**Option A: USB Boot**:
```bash
# Copy ISO to USB drive (replace /dev/sdX with your USB device)
sudo dd if=/data/iso/my-baremetal-cluster-agent.x86_64.iso \
        of=/dev/sdX bs=4M status=progress
sync

# Insert USB into each server and boot
# Set boot order: USB first, then disk
```

**Option B: iDRAC/BMC Virtual Media**:
```bash
# Dell iDRAC example
racadm -r <idrac-ip> -u root -p <password> remoteimage -c
racadm -r <idrac-ip> -u root -p <password> remoteimage -m \
       nfs://<nfs-server>/path/to/my-baremetal-cluster-agent.x86_64.iso
racadm -r <idrac-ip> -u root -p <password> set iDRAC.VirtualMedia.BootOnce 1
racadm -r <idrac-ip> -u root -p <password> serveraction powercycle

# HPE iLO example
hponcfg -f mount_iso.xml
# (XML config with ISO path and boot settings)

# Repeat for each physical server
```

**Option C: Network Boot (PXE/iPXE)**:
- Extract kernel and initramfs from ISO
- Configure PXE/iPXE server to serve boot files
- Boot servers via network (beyond scope of this guide)

#### Step 4: Verify Servers Boot

**Physical server console** (iDRAC/iLO/KVM):
- Servers boot from ISO
- CoreOS installer starts
- Network configuration applied (static IPs from agent-config.yaml)
- Installation begins automatically

**Expected behavior**:
- Servers reboot after initial install
- Bootstrap node provisions control plane
- Control plane nodes join cluster
- Worker nodes join after control plane ready

#### Step 5: Monitor Installation (From Bastion/Hypervisor)

```bash
# Monitor from Ansible control node
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @extra_vars/cluster-configs/my-baremetal-cluster.yml \
  --tags phase6
```

**Manual monitoring**:
```bash
# Watch installation logs
tail -f /root/openshift-install-my-baremetal-cluster/.openshift_install.log

# Wait for bootstrap complete
openshift-install wait-for bootstrap-complete \
  --dir /root/openshift-install-my-baremetal-cluster

# After bootstrap, power off bootstrap node (if using one)
# Then wait for install complete
openshift-install wait-for install-complete \
  --dir /root/openshift-install-my-baremetal-cluster
```

#### Step 6: Access Cluster

Same as KVM deployment:
```bash
export KUBECONFIG=/data/ocp-credentials/my-baremetal-cluster-kubeconfig
oc get nodes
oc get co
```

---

## AAP Workflow Deployment (Web UI)

**Prerequisite**: AAP 2.5+ deployed with Workflow 3 configured.

See: [Configure AAP Workflow 3](../aap-configuration/configure-workflow-3-openshift-cluster.yml)

### Deploy via AAP Web UI

1. **Navigate to AAP**:
   - Open: `https://aap.<domain>`
   - Login: admin / <gateway_password>

2. **Launch Workflow**:
   - Templates → "Deploy OpenShift Cluster (Agent-Based)"
   - Click "Launch"

3. **Fill Survey**:
   ```
   Cluster Name: ocp4-prod
   Base Domain: example.com
   Cluster Topology: ha
   Registry Type: quay
   Registry URL: registry.example.com:8443
   OpenShift Version: 4.21
   DNS Provider: route53
   API VIP: 192.168.10.100
   Ingress VIP: 192.168.10.101
   ```

4. **Submit & Monitor**:
   - Workflow executes 5 nodes sequentially
   - Monitor progress in AAP UI
   - Total time: 45-90 minutes

5. **Access Cluster**:
   - Credentials in `/data/ocp-credentials/<cluster>-*`
   - Follow "Access Cluster" steps above

---

## Environment-Specific Notes

### KVM/libvirt (This Repository's Primary Use Case)

**Advantages**:
- ✅ Full automation via Ansible
- ✅ VM provisioning included
- ✅ Ideal for development/testing
- ✅ Nested virtualization on IBM Cloud

**Networking**:
- Uses libvirt `virbr0` bridge (192.168.122.1/24)
- VMs get static IPs on VLANs (1924, 1925, 1927)
- VyOS router provides DNS/DHCP/NAT

**Storage**:
- VM disks: `/data/libvirt-images/`
- ISO output: `/data/iso/`
- Credentials: `/data/ocp-credentials/`

**Limitations**:
- Nested virtualization performance penalty
- Resource-constrained (IBM Cloud VSI limits)
- Not for production workloads

### Bare Metal (External Infrastructure)

**Advantages**:
- ✅ Production-grade performance
- ✅ No virtualization overhead
- ✅ Full hardware control
- ✅ Enterprise compliance ready

**Networking**:
- Requires external DNS server
- Physical switch VLAN configuration
- Static IP allocation plan
- Load balancer for API/Ingress (HA)

**Storage**:
- Local disks or SAN/NAS
- Consider persistent volume providers (NFS, Ceph, ODF)

**Additional Requirements**:
- **IPMI/BMC Access**: Remote power management
- **Network Boot** (optional): PXE server for automation
- **Load Balancer** (HA): HAProxy, F5, or cloud LB for API/Ingress
- **Out-of-Band Network**: Separate management network for IPMI

**What You Need to Provide**:
1. **Physical servers** meeting resource requirements
2. **MAC addresses** for all NICs
3. **IP allocation** for API VIP, Ingress VIP, and nodes
4. **DNS records** (A records for API, wildcard for apps, node FQDNs)
5. **Boot method** (USB drives, BMC virtual media, or PXE)
6. **Load balancer** (HA only): Configure backends for API (6443) and Ingress (443)

**Bare Metal Workflow**:
```
You (Manual)                    Ansible (Automated)
════════════════                ═══════════════════════
1. Provide MAC addresses    →   Generate cluster config
2. Provide IP allocation    →   Generate manifests
3. Configure DNS records    →   Create bootable ISO
4. Boot servers from ISO    →   Monitor installation
5. Verify network/power     →   Approve CSRs (workers)
                            →   Export credentials
```

---

## Topology Comparison

| Topology | Use Case | Nodes | Resources | Time | Load Balancer |
|----------|----------|-------|-----------|------|---------------|
| **SNO** | Dev/Test, Edge | 1 | 32GB, 8 vCPU | 35-70m | Built-in (single IP) |
| **Compact** | Small Prod, Lab | 3 | 72GB, 18 vCPU | 35-70m | Built-in (keepalived) |
| **HA** | Production | 6+ | 144GB+, 54+ vCPU | 45-90m | External required |

**Recommendations**:
- **SNO**: Development, edge deployments, resource-constrained
- **Compact**: Small production (< 50 pods), lab environments
- **HA**: Production workloads, high availability requirements

---

## Troubleshooting

### ISO Generation Fails

**Error**: `openshift-install: command not found`

**Solution**: Install openshift-install binary (see Prerequisites)

---

### VMs Don't Boot (KVM Only)

**Error**: VM stuck at boot, no network

**Solution**:
```bash
# Check VM exists
virsh list --all

# Check VM console
virsh console <vm-name>

# Verify ISO mounted
virsh domblklist <vm-name>

# Check libvirt network
virsh net-list
virsh net-info default
```

---

### Bare Metal Servers Won't Boot from ISO

**Check**:
1. Boot order: USB/CD first in BIOS/UEFI
2. Secure Boot: Disable if enabled
3. UEFI vs BIOS: ISO supports both, verify mode
4. Virtual media: Check BMC connection, re-mount ISO

---

### DNS Resolution Fails

**Test DNS**:
```bash
dig +short api.<cluster>.<domain>
dig +short test.apps.<cluster>.<domain>

# Should return VIP addresses
```

**Fix**:
- **dnsmasq**: Restart service, check `/etc/dnsmasq.d/openshift-<cluster>.conf`
- **Route53**: Verify AWS credentials, check hosted zone
- **Manual**: Add A records to your DNS server

---

### Bootstrap Timeout

**Error**: Bootstrap doesn't complete after 40 minutes

**Debug**:
```bash
# Check bootstrap node accessible
ssh core@<bootstrap-ip>

# Check bootstrap services
ssh core@<bootstrap-ip> journalctl -u bootkube -u kubelet

# Check control plane nodes
oc get nodes  # Should show masters NotReady during bootstrap
```

**Common Causes**:
- Network connectivity issues (firewall, routing)
- Pull secret invalid or registry unreachable
- Control plane nodes not booting
- Insufficient resources (OOM, CPU throttling)

---

### Cluster Operators Degraded

**Check operator status**:
```bash
oc get co
oc describe co <operator-name>
```

**Common operators to check**:
- `authentication`: OAuth/htpasswd configuration
- `image-registry`: Registry storage configuration
- `ingress`: Router pods running
- `monitoring`: Prometheus/Grafana pods

**Fix degraded operators**:
```bash
# Check operator pods
oc get pods -n openshift-<operator-namespace>

# Review operator logs
oc logs -n openshift-<operator-namespace> <pod-name>

# Common fixes
# - Add persistent volume for registry
# - Configure OAuth identity provider
# - Verify load balancer connectivity
```

---

## Next Steps

After cluster deployment:

1. **Configure Authentication**:
   - Delete kubeadmin (security)
   - Configure htpasswd, LDAP, or OAuth
   - Create admin users and RBAC

2. **Deploy Operators**:
   - Install from mirror registry catalog
   - See: [Add Custom Operators](add-custom-operators.md)

3. **Configure Storage**:
   - Install storage operator (ODF, NFS, Ceph)
   - Create storage classes
   - Configure persistent volumes

4. **Enable Monitoring**:
   - Configure Prometheus retention
   - Set up alerting (email, Slack, PagerDuty)
   - Create Grafana dashboards

5. **Secure Cluster**:
   - Network policies
   - Pod security standards
   - Image signature verification
   - Compliance operator (if required)

---

## Related Documentation

- [Generate Agent-Based Installer ISO](generate-agent-based-installer-iso.md)
- [Configure DNS for OpenShift Clusters](configure-dns-for-openshift-clusters.md)
- [Configure Operator Catalog for Disconnected](configure-operator-catalog-for-disconnected.md)
- [Deploy VyOS Router](deploy-vyos-router.md) (KVM networking)
- [AAP Deployment Guide](deploy-aap-multi-node.md)

---

## References

- [OpenShift Agent-Based Installer Documentation](https://docs.openshift.com/container-platform/4.21/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)
- [Agent-Based Installer Examples](https://github.com/openshift/installer/tree/master/docs/user/agent)
- ADR-0035: Adopt OpenShift Agent-Based Installer
- ADR-0024: Roles and Collections Architecture
