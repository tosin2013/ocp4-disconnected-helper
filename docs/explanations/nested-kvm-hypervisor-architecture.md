# Understanding Nested KVM Hypervisor Architecture

Why this project uses nested virtualization (VM running VMs) and the trade-offs involved.

---

## The Nested Virtualization Concept

**Architecture**:
```
IBM Cloud Physical Server
  └─ CentOS Stream 10 VM (48 vCPU, 188 GB RAM) ← This is a VM
      └─ KVM/libvirt Hypervisor ← Running inside the VM
          ├─ VyOS Router VM
          ├─ Registry VM
          └─ AAP VM (planned)
```

**Key insight**: The hypervisor itself is a virtual machine

---

## Why Nested Virtualization?

### Reason 1: IBM Cloud Environment Constraint

**IBM Cloud limitation**: No bare-metal access in lab environment

**Options**:
1. Use containers only (no VMs) → Can't test OpenShift cluster deployment
2. Request bare-metal server → Expensive, requires justification
3. Use nested virtualization → Works within constraints

**Choice**: Nested KVM (option 3)

### Reason 2: Realistic OpenShift Testing

**OpenShift requires**:
- Multiple VMs (master nodes, worker nodes)
- Dedicated network segments (VLANs)
- VM lifecycle management (create, destroy, scale)

**Containers insufficient**:
- Can't provision VMs from containers
- Can't test bare-metal installation
- Can't test network isolation

**Nested KVM provides**: Full VM management inside cloud VM

### Reason 3: Cost Optimization

**Alternative**: 5 separate IBM Cloud VMs
- VyOS VM: 2 vCPU, 4 GB RAM
- Registry VM: 4 vCPU, 16 GB RAM
- AAP VM: 4 vCPU, 16 GB RAM
- Master nodes: 3 × 8 vCPU, 16 GB RAM = 24 vCPU, 48 GB RAM
- **Total**: 34 vCPU, 84 GB RAM across 5 VMs

**Nested approach**: 1 IBM Cloud VM
- Hypervisor VM: 48 vCPU, 188 GB RAM
- All VMs run inside hypervisor
- **Total**: 48 vCPU, 188 GB RAM (1 VM billed)

**Savings**: 4 fewer VMs billed monthly

---

## Technical Implementation

### Nested KVM Requirements

**Kernel parameter**:
```bash
cat /sys/module/kvm_intel/parameters/nested
# Must return: Y or 1
```

**CPU feature exposure**:
```bash
virsh capabilities | grep 'vmx'
# Must show VMX flag available
```

**libvirt configuration**:
```xml
<domain type='kvm'>
  <cpu mode='host-passthrough'>
    <feature policy='require' name='vmx'/>
  </cpu>
</domain>
```

### Performance Characteristics

**CPU overhead**:
- L1 VM (hypervisor): ~5% overhead
- L2 VM (nested guest): ~10-15% overhead
- **Total**: ~15-20% performance penalty vs bare-metal

**Memory overhead**:
- Minimal (memory pages passed through)
- No significant penalty

**Network overhead**:
- virbr0 bridge: ~5% latency increase
- VLAN tagging: Minimal overhead

---

## Architecture Layers

### Layer 1: IBM Cloud Physical Infrastructure

**Resources**: Physical server, storage, networking  
**Hypervisor**: IBM Cloud proprietary hypervisor  
**Guest OS**: CentOS Stream 10 (our "hypervisor VM")

### Layer 2: CentOS Stream 10 VM (Hypervisor)

**Role**: KVM/libvirt hypervisor host  
**Resources**: 48 vCPU, 188 GB RAM, 500 GB disk  
**Hypervisor**: KVM/QEMU 10.1.0  
**Guests**: VyOS, Registry, AAP VMs

### Layer 3: Nested VMs

**VyOS Router**:
- 2 vCPU, 4 GB RAM
- Role: Network routing, NAT, DHCP, DNS

**Registry VM**:
- 4 vCPU, 16 GB RAM
- Role: Container registry (Quay/Harbor/JFrog)

**AAP VM** (planned):
- 4 vCPU, 16 GB RAM
- Role: Workflow orchestration

**OpenShift Cluster** (future):
- 3 master nodes: 8 vCPU, 16 GB RAM each
- 2 worker nodes: 8 vCPU, 32 GB RAM each

---

## Trade-offs

### Advantages

✅ **Cloud-native**: Works within IBM Cloud VM constraints  
✅ **Cost-effective**: Single VM billing vs multiple VMs  
✅ **Realistic testing**: Can deploy full OpenShift clusters  
✅ **Isolated networking**: VLAN segmentation via VyOS  
✅ **Portable**: Can migrate entire environment (export hypervisor VM)

### Disadvantages

❌ **Performance overhead**: 15-20% slower than bare-metal  
❌ **Complexity**: Two hypervisor layers to debug  
❌ **Resource limits**: Bounded by L1 VM resources  
❌ **Nested limitations**: Some features require nested-nesting (not supported)

---

## Performance Comparison

| Workload | Bare-Metal | Nested KVM | Performance Loss |
|----------|-----------|------------|------------------|
| **CPU-intensive** (image compression) | 100% | 80-85% | 15-20% |
| **Memory-intensive** (database) | 100% | 95-98% | 2-5% |
| **Disk I/O** (oc-mirror) | 100% | 70-80% | 20-30% |
| **Network** (image push) | 100% | 90-95% | 5-10% |

**Bottleneck**: Disk I/O (image mirroring most affected)

---

## Nested Virtualization Gotchas

### Gotcha 1: VMX Feature Not Exposed

**Symptom**: L2 VMs fail to start with "KVM not available"

**Cause**: L1 hypervisor not exposing VMX CPU feature

**Solution**:
```bash
# On L1 hypervisor (IBM Cloud)
virsh edit hypervisor-vm
# Add: <feature policy='require' name='vmx'/>
```

### Gotcha 2: Disk Performance

**Symptom**: oc-mirror very slow (>2 hours for 8 operators)

**Cause**: Nested storage virtualization overhead

**Solution**: Use virtio-scsi with io='threads'
```xml
<disk type='file' device='disk'>
  <driver name='qemu' type='qcow2' io='threads'/>
  <target dev='vda' bus='virtio'/>
</disk>
```

### Gotcha 3: Network Bridge Conflicts

**Symptom**: L2 VMs can't reach internet

**Cause**: Overlapping bridge networks (virbr0 on L1 and L2)

**Solution**: Use different subnets
- L1 virbr0: 192.168.122.0/24
- L2 virbr0: 192.168.123.0/24

---

## When NOT to Use Nested Virtualization

**Avoid nested KVM when**:
- ❌ Production workloads (use bare-metal)
- ❌ Performance-critical applications (>20% overhead unacceptable)
- ❌ Bare-metal access available (no reason to nest)
- ❌ Hypervisor doesn't support VMX passthrough

**Use nested KVM when**:
- ✅ Lab/testing environments
- ✅ Cloud VMs with nested virtualization support
- ✅ Cost optimization important
- ✅ VM portability required

---

## Alternatives Considered

### Alternative 1: Containers Only (Docker/Podman)

**Why rejected**:
- ❌ Can't provision VMs for OpenShift nodes
- ❌ Can't test bare-metal installation
- ❌ Limited network isolation

### Alternative 2: Kubernetes-in-Docker (KinD)

**Why rejected**:
- ❌ Not real OpenShift (missing operators, networking)
- ❌ Can't test disconnected installation
- ❌ Different from production architecture

### Alternative 3: Multiple IBM Cloud VMs

**Why rejected**:
- ❌ Higher cost (5 VMs vs 1 VM)
- ❌ More complex networking (cross-VM communication)
- ❌ Less portable (can't export entire environment)

---

## Future: Bare-Metal Migration

**When moving to bare-metal**:
1. Export nested VMs from hypervisor
2. Import VMs to bare-metal hypervisor
3. Adjust CPU cores (remove VMX passthrough)
4. Reconfigure networking (remove nested bridge)
5. Benchmark performance improvement

**Expected improvement**: 15-20% faster, 20-30% better disk I/O

---

## Related Documentation

- [GETTING_STARTED.md](../GETTING_STARTED.md) - Hypervisor setup
- [LIBVIRT_PERMISSIONS.md](../LIBVIRT_PERMISSIONS.md) - Libvirt configuration
- [ADR-0010: CentOS Stream 10 Target](../adrs/0010-centos-stream-10-target.md)

---

## Summary

**Nested KVM architecture**: VM running inside VM (IBM Cloud VM → KVM hypervisor → nested VMs)

**Why used**: Cloud environment constraint + cost optimization + realistic OpenShift testing

**Trade-off**: 15-20% performance loss for significant cost savings and portability

**Key insight**: Nested virtualization is a **pragmatic solution** for cloud-based development/testing, not optimal for production.
