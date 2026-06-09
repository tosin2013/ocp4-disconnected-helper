# ADR 0025: VyOS Router as Network Infrastructure Prerequisite

**Status**: Accepted  
**Date**: 2026-06-03  
**Deciders**: Platform Team  
**Context**: Deployment failures due to missing network infrastructure  

## Context and Problem Statement

During implementation of ADR 0024 (Roles and Collections Architecture), we discovered that the KVM environment lacks proper network infrastructure:

- Libvirt default network is broken/missing
- No DNS services for VM name resolution
- No DHCP management for static IP assignment
- No VLAN segmentation for different network tiers
- No routing between VM networks and external networks

**Current Deployment Blockers**:
- Registry VM deployment fails due to SSH authentication issues
- VMs created outside libvirt management (orphaned processes)
- No proper network isolation between management, OCP, and storage traffic
- Manual `/etc/hosts` entries required for name resolution

## Decision Drivers

1. **Network Isolation**: Separate traffic types (management, OpenShift, storage, external)
2. **DNS/DHCP**: Automated network service management
3. **Production Readiness**: Enterprise-grade networking for disconnected environments
4. **Reproducibility**: Consistent network configuration across deployments
5. **Reference Architecture**: Align with proven OpenShift deployment patterns

## Considered Options

### Option 1: VyOS Router VM (CHOSEN)
**Pros**:
- Industry-standard network OS designed for virtualized environments
- Full VLAN support with proper segmentation
- Integrated DNS/DHCP services
- Firewall and NAT capabilities
- Proven in production OpenShift deployments
- Reference implementation available: https://tosin2013.github.io/openshift-agent-install/vyos-manual-configuration.html

**Cons**:
- Additional VM resource overhead (~1 vCPU, 1GB RAM)
- Requires initial setup and configuration
- One more component to manage

### Option 2: Fix Libvirt Default Network
**Pros**:
- Simpler, fewer components
- Native to libvirt/KVM

**Cons**:
- No VLAN segmentation
- Limited DNS/DHCP customization
- Not production-ready for enterprise deployments
- Doesn't solve current broken state issues
- Single flat network (no isolation)

### Option 3: Use Host Network Directly (eth0: 10.241.64.x)
**Pros**:
- No additional networking layer
- VMs get real routable IPs

**Cons**:
- No isolation from IBM Cloud internal network
- Security risk: VMs exposed to cloud provider network
- No control over DHCP/DNS
- Cannot segment traffic types

## Decision Outcome

**Chosen option**: **VyOS Router VM** as mandatory prerequisite for all KVM-based disconnected OpenShift deployments.

### VyOS Network Architecture (Hybrid Approach)

**Using upstream VLAN IDs with simplified IP scheme**

**Design Decision**: Hybrid approach combining upstream VLAN IDs (proven to work with reference libvirt network creation) with cleaner, more readable IP ranges for easier management.

```
┌─────────────────────────────────────────────────────────────────┐
│  IBM Cloud VSI (KVM Host)                                       │
│  eth0: 10.241.64.9/24 (IBM Cloud internal)                     │
│                                                                  │
│  ┌──────────────────────────────────────────────────────┐      │
│  │  VyOS Router VM (192.168.122.2)                      │      │
│  │  - eth0: 192.168.122.2/24 (external, NAT to KVM host)│      │
│  │  - eth1: 192.168.10.1/24  (base interface)           │      │
│  │    └─ vif 1924: 192.168.10.1/24 (Management VLAN)    │      │
│  │  - eth2: 192.168.20.1/24  (base interface)           │      │
│  │    └─ vif 1925: 192.168.20.1/24 (OpenShift VLAN)     │      │
│  │  - eth3: 192.168.30.1/24  (base interface)           │      │
│  │    └─ vif 1927: 192.168.30.1/24 (Storage VLAN)       │      │
│  │                                                        │      │
│  │  Services:                                             │      │
│  │  - DNS forwarder: 161.26.0.10 (IBM Cloud DNS)        │      │
│  │  - DHCP per network (static reservations)            │      │
│  │  - NAT/Firewall for all networks                     │      │
│  │  - Domain: ocp4.sandbox3377.opentlc.com              │      │
│  └──────────────────────────────────────────────────────┘      │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────┐      │
│  │  Libvirt Networks (created by vyos-router.sh)        │      │
│  │                                                        │      │
│  │  Network 1924 (Management): 192.168.10.0/24          │      │
│  │    - VyOS Gateway: 192.168.10.1                      │      │
│  │    - DHCP Range: 192.168.10.10 - 192.168.10.254     │      │
│  │    - Static Reservations:                             │      │
│  │      • registry-vm: 192.168.10.10 (52:54:00:10:00:10)│      │
│  │      • aap-vm: 192.168.10.20 (52:54:00:10:00:20)     │      │
│  │    - Use for: Registry, AAP, bastion, mgmt tools     │      │
│  │                                                        │      │
│  │  Network 1925 (OpenShift): 192.168.20.0/24           │      │
│  │    - VyOS Gateway: 192.168.20.1                      │      │
│  │    - DHCP Range: 192.168.20.10 - 192.168.20.254     │      │
│  │    - Static Reservations:                             │      │
│  │      • ocp-master-1: 192.168.20.11 (52:54:00:20:00:11)│     │
│  │      • ocp-master-2: 192.168.20.12 (52:54:00:20:00:12)│     │
│  │      • ocp-master-3: 192.168.20.13 (52:54:00:20:00:13)│     │
│  │      • ocp-worker-1: 192.168.20.21 (52:54:00:20:00:21)│     │
│  │      • ocp-worker-2: 192.168.20.22 (52:54:00:20:00:22)│     │
│  │    - Use for: OpenShift masters, workers, services   │      │
│  │                                                        │      │
│  │  Network 1927 (Storage): 192.168.30.0/24             │      │
│  │    - VyOS Gateway: 192.168.30.1                      │      │
│  │    - DHCP Range: 192.168.30.10 - 192.168.30.254     │      │
│  │    - Use for: NFS, persistent storage, backup        │      │
│  └──────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────┘
```

**Network Assignment Strategy**:
- **192.168.10.x (VLAN 1924 - Management)**: Registry VM, AAP VM, management tools
- **192.168.20.x (VLAN 1925 - OpenShift)**: OpenShift master and worker nodes
- **192.168.30.x (VLAN 1927 - Storage)**: NFS servers, persistent storage, backups

**MAC Address Pattern**: Deterministic scheme `52:54:00:NN:00:XX`
- `NN` = Network identifier (10=Management, 20=OpenShift, 30=Storage)
- `XX` = Host identifier (10-19=infrastructure, 11-13=masters, 21-29=workers)

### Implementation Plan

**Phase 1: VyOS Router Deployment** (prerequisite)
1. Download VyOS ISO (2026.05.30 nightly rolling)
2. Create VyOS VM via `hack/vyos-router.sh` (forked from reference)
3. Manual VyOS basic setup (eth0, SSH) via Cockpit console
4. Automated VLAN configuration via `hack/vyos-config-ocp4.sh`
5. Validate connectivity, DNS, and DHCP services

**Phase 2: Update Existing Roles**
1. Modify `common_vm` role to support VLAN-based networking
2. Update network configuration to use VyOS DNS (192.168.10.1, 192.168.20.1)
3. Configure deterministic MAC addresses for static DHCP reservations
4. Remove libvirt default network dependency

**Phase 3: Update Inventory**
1. Change IP ranges to hybrid network scheme
2. Registry VM: 192.168.10.10 (Management/1924 - static DHCP)
3. AAP VM: 192.168.10.20 (Management/1924 - static DHCP)
4. OpenShift masters: 192.168.20.11-13 (OpenShift/1925 - static DHCP)
5. OpenShift workers: 192.168.20.21-22 (OpenShift/1925 - static DHCP)

### Deployment Order (Critical)

```
1. VyOS Router         (FIRST - provides network services)
2. Registry VM         (depends on VyOS DNS/DHCP)
3. AAP VM              (depends on VyOS DNS/DHCP)
4. OpenShift Nodes     (depends on registry + VyOS)
```

**Never deploy VMs before VyOS is operational**

## Consequences

### Positive

- **Production-Ready Networking**: Enterprise-grade network segmentation
- **Security**: Traffic isolation between management, OCP, and storage
- **Automation**: DNS/DHCP removes manual IP/hostname management
- **Scalability**: Easy to add new VLANs or extend existing networks
- **Observability**: Centralized network services for monitoring
- **Reproducibility**: Consistent network config across environments

### Negative

- **Additional Complexity**: One more VM to manage and configure
- **Resource Overhead**: ~1 vCPU, 1GB RAM for VyOS router
- **Initial Setup Time**: VyOS configuration before other VMs can deploy
- **Learning Curve**: Team needs VyOS knowledge for troubleshooting

### Neutral

- **Reference Implementation**: Following proven OpenShift deployment pattern
- **Network Changes**: All VM IP addresses will change to VLAN-based ranges

## Compliance

- **ADR 0024 (Roles Architecture)**: VyOS deployment must be an Ansible role
- **ADR 0009 (Security)**: VLANs provide network segmentation required for production
- **ADR 0021 (AAP Migration)**: AAP VM depends on VyOS network infrastructure

## References

- **Primary Guide**: https://tosin2013.github.io/openshift-agent-install/vyos-manual-configuration.html
- **VyOS Documentation**: https://docs.vyos.io/
- **Issue Context**: Discovered during ADR 0024 implementation (registry deployment failures)

## Implementation Approach

**Using Proven Reference Implementation with Custom Network Scheme**

We are leveraging the battle-tested VyOS deployment script from the OpenShift Agent Install project, customized with our hybrid network approach:

- **Source**: https://raw.githubusercontent.com/tosin2013/openshift-agent-install/refs/heads/main/hack/vyos-router.sh
- **Forked to**: `hack/vyos-router.sh` (creates libvirt networks, provisions VM)
- **Wrapper**: `hack/deploy-vyos.sh` (sets our environment variables)
- **Custom Config**: `hack/vyos-config-ocp4.sh` (hybrid network implementation)

**Why Fork Instead of Ansible Role?**
1. **Proven in Production**: Script is actively maintained and used in real deployments
2. **Manual Configuration Required**: VyOS needs interactive console setup (can't be fully automated with cloud-init)
3. **Complexity**: Proper VyOS config involves 100+ commands - script generates them automatically
4. **Time to Value**: Script works today vs. weeks to build/test Ansible equivalent
5. **Upstream Updates**: Easy to pull improvements from reference implementation

**Why Hybrid Network Scheme?**
1. **Proven VLAN IDs**: Uses upstream VLAN numbers (1924, 1925, 1927) that work with reference libvirt network creation
2. **Readable IP Ranges**: Clean 192.168.10.x/20.x/30.x scheme instead of 192.168.50.x/52.x/56.x
3. **Easier Management**: Simple IP patterns reduce cognitive load and error potential
4. **Static DHCP**: Deterministic MAC addresses ensure consistent IP assignment

**Deployment Process**:
```bash
cd /home/vpcuser/ocp4-disconnected-helper
./hack/deploy-vyos.sh
```

This will:
1. Create libvirt networks (1924, 1925, 1926, 1927, 1928) using upstream script
2. Download VyOS 2026.05.30 nightly ISO
3. Create VyOS VM with virt-install (4GB RAM, 2 vCPUs, 20GB disk)
4. Display manual configuration instructions
5. Wait up to 30 minutes for router to become accessible

**Manual Steps** (via Cockpit console):
1. Access Cockpit: https://<KVM_HOST>:9090
2. Open VyOS console (Virtual Machines → vyos-router → Console)
3. Login: vyos / vyos
4. Run: `install image` (VM will restart, start it again manually)
5. Configure basic networking (eth0: 192.168.122.2/24, gateway, SSH)
6. Script automatically detects SSH access and applies `vyos-config-ocp4.sh`

**Custom VyOS Configuration** (automated via `vyos-config-ocp4.sh`):
- VLAN 1924 → 192.168.10.0/24 (Management network)
- VLAN 1925 → 192.168.20.0/24 (OpenShift network)
- VLAN 1927 → 192.168.30.0/24 (Storage network)
- Static DHCP reservations for all VMs (deterministic MACs)
- DNS forwarding to 161.26.0.10 (IBM Cloud DNS)
- NAT rules for external access from all VLANs
- Firewall rules allowing inter-VLAN communication

## Implementation Status

- [x] Fork vyos-router.sh to hack/ directory
- [x] Create deploy-vyos.sh wrapper with environment config
- [x] Create vyos-config-ocp4.sh with hybrid network scheme
- [x] Document manual configuration process
- [x] Execute VyOS deployment (June 3, 2026)
- [x] Validate router accessibility (SSH operational at 192.168.122.2)
- [x] Verify VLAN configuration (1924, 1925, 1927 operational)
- [x] Verify NAT/DNS/Firewall (all networks can reach external)
- [ ] Update inventory with VLAN-based IP ranges
- [ ] Test VM deployment on management VLAN
- [ ] Update common_vm role for VLAN support
- [ ] Validate end-to-end connectivity
- [ ] Document VyOS management procedures

## Deployment Results (June 3, 2026)

**VyOS Router**: Successfully deployed and configured at 192.168.122.2

**Network Configuration**:
- VLAN 1924 (Management): eth1 → 192.168.10.1/24 ✅
- VLAN 1925 (OpenShift): eth2 → 192.168.20.1/24 ✅
- VLAN 1927 (Storage): eth3 → 192.168.30.1/24 ✅

**Services Operational**:
- NAT: All VLANs can reach external networks (tested with ping 1.1.1.1) ✅
- DNS Forwarding: Listening on 192.168.10.1, 192.168.20.1, 192.168.30.1 ✅
- Firewall: INTERNAL_NETS group configured ✅
- SSH: Accessible at 192.168.122.2 port 22 ✅

**DHCP Configuration**:
- Management (192.168.10.0/24): Range 192.168.10.10-.254, subnet-id 1
- OpenShift (192.168.20.0/24): Range 192.168.20.10-.254, subnet-id 2
- Storage (192.168.30.0/24): Range 192.168.30.10-.254, subnet-id 3

**Note**: Static DHCP reservations will be configured when VMs are deployed with actual MAC addresses.

**Cockpit Access**: 
- Credentials stored in ~/cockpit-credentials.txt
- Username: vpcuser, Password: UPojeOALj7E8Y/UE

## Notes

This ADR was created during troubleshooting of registry VM deployment failures. The root cause was the absence of proper network infrastructure - libvirt default network was broken, no DNS/DHCP services existed, and VMs were being created in an unmanaged state. VyOS router deployment is now recognized as a **mandatory prerequisite** rather than an optional enhancement.

**Next Action**: Create `roles/vyos_router/` following ADR 0024 patterns.
