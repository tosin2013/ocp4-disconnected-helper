# VyOS Router Deployment Results

**Date**: June 3, 2026 18:08 UTC  
**Status**: ✅ Operational  
**Reference**: ADR 0025 - VyOS Router as Network Infrastructure Prerequisite

## Deployment Summary

VyOS router successfully deployed with hybrid network approach combining upstream VLAN IDs (1924, 1925, 1927) with simplified IP ranges (192.168.10.x, 20.x, 30.x).

## Network Configuration

### Management Network (VLAN 1924)
- **Interface**: eth1, eth1.1924
- **Gateway**: 192.168.10.1/24
- **DHCP Range**: 192.168.10.10 - 192.168.10.254
- **Purpose**: Registry VM, AAP VM, bastion, management tools
- **Status**: ✅ Operational

### OpenShift Network (VLAN 1925)
- **Interface**: eth2, eth2.1925
- **Gateway**: 192.168.20.1/24
- **DHCP Range**: 192.168.20.10 - 192.168.20.254
- **Purpose**: OpenShift master nodes, worker nodes
- **Status**: ✅ Operational

### Storage Network (VLAN 1927)
- **Interface**: eth3, eth3.1927
- **Gateway**: 192.168.30.1/24
- **DHCP Range**: 192.168.30.10 - 192.168.30.254
- **Purpose**: NFS servers, persistent storage
- **Status**: ✅ Operational

### External Network
- **Interface**: eth0
- **Address**: 192.168.122.2/24
- **Gateway**: 192.168.122.1
- **Purpose**: NAT to KVM host and external internet
- **Status**: ✅ Operational

## Services Verification

### NAT (Network Address Translation)
```
✅ Rule 10: 192.168.122.2 → masquerade via eth0
✅ Rule 11: 192.168.10.0/24 → masquerade via eth0 (Management)
✅ Rule 12: 192.168.20.0/24 → masquerade via eth0 (OpenShift)
✅ Rule 13: 192.168.30.0/24 → masquerade via eth0 (Storage)
```

**Test Results**: All networks successfully ping 1.1.1.1 (Cloudflare DNS)

### DNS Forwarding
```
✅ Listen Address: 192.168.10.1 (Management)
✅ Listen Address: 192.168.20.1 (OpenShift)
✅ Listen Address: 192.168.30.1 (Storage)
✅ Upstream: 192.168.122.1 (KVM host dnsmasq)
```

### Firewall
```
✅ Network Group: INTERNAL_NETS
   - 192.168.10.0/24
   - 192.168.20.0/24
   - 192.168.30.0/24
```

### DHCP Server
- **Status**: Configured but not started (awaiting VM connections)
- **Subnets**: 3 configured (Management, OpenShift, Storage)
- **Reservations**: Will be added dynamically as VMs are deployed

## Access Information

### SSH Access
```bash
ssh vyos@192.168.122.2
# Password: vyos
```

### Cockpit Access (Web Console)
```
URL: https://10.241.64.9:9090
Username: vpcuser
Password: UPojeOALj7E8Y/UE
```

Credentials file: `~/cockpit-credentials.txt`

## Libvirt Networks

All libvirt networks created and active:

```
Name      State    Autostart   Persistent
--------------------------------------------
1924      active   yes         yes
1925      active   yes         yes
1926      active   yes         yes  (unused - for future expansion)
1927      active   yes         yes
1928      active   yes         yes  (unused - for future expansion)
default   active   yes         yes
```

## Configuration Files

- **Main Script**: `hack/vyos-router.sh` (forked from tosin2013/openshift-agent-install)
- **Wrapper**: `hack/deploy-vyos.sh` (environment configuration)
- **Custom Config**: `hack/vyos-config-ocp4.sh` (hybrid network implementation)
- **Deployment Log**: `/tmp/vyos-deployment-*.log`

## Known Limitations

1. **Static DHCP Reservations**: Not configured during initial deployment
   - Reason: Requires actual VM MAC addresses
   - Solution: Will be added when VMs are provisioned with deterministic MACs

2. **DHCP Service Not Started**: DHCP server configured but not started
   - Reason: VyOS won't start DHCP until at least one client connects
   - Solution: Will auto-start when first VM boots on a VLAN

## Next Steps

1. ✅ VyOS router operational
2. ⏭️ Update inventory with VLAN-based IP ranges
3. ⏭️ Deploy registry VM on Management VLAN (192.168.10.10)
4. ⏭️ Deploy AAP VM on Management VLAN (192.168.10.20)
5. ⏭️ Deploy OpenShift nodes on OpenShift VLAN (192.168.20.11-22)

## Troubleshooting

### Check VyOS Status
```bash
sudo virsh list --all | grep vyos
```

### Access VyOS Console
```bash
sudo virsh console vyos-router
# Press Ctrl+] to exit
```

### Verify Network Interfaces
```bash
ssh vyos@192.168.122.2
show interfaces
show nat source
show dhcp server statistics
```

### Check Libvirt Networks
```bash
virsh net-list --all
virsh net-dhcp-leases 1924
virsh net-dhcp-leases 1925
virsh net-dhcp-leases 1927
```

## References

- ADR 0025: docs/adrs/0025-vyos-router-network-prerequisite.md
- Deployment Guide: docs/VYOS_DEPLOYMENT.md
- Upstream Reference: https://tosin2013.github.io/openshift-agent-install/vyos-manual-configuration.html
