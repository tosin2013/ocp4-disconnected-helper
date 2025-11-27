# ADR 0007: 3-Node Compact Cluster Architecture

**Status:** Accepted  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 5.3 - Default Deployment Architecture

## Context

OpenShift clusters can be deployed in various configurations:
- **Standard**: 3 control plane + N worker nodes
- **Compact**: 3 nodes serving as both control plane and workers
- **Single Node OpenShift (SNO)**: 1 node for all workloads

For disconnected and edge environments, resource efficiency and simplicity are critical factors.

## Decision

Adopt **3-node compact cluster** as the default deployment architecture for appliance-based installations.

### Configuration
- **3 nodes** total
- Each node runs **control plane components** (etcd, API server, controllers)
- Each node also runs **worker workloads**
- Schedulable control plane nodes

## Rationale

### Why 3-Node Compact?

| Factor | 3-Node Compact | Standard (3+N) | SNO |
|--------|----------------|----------------|-----|
| Resource efficiency | High | Medium | Highest |
| High availability | Yes (etcd quorum) | Yes | No |
| Workload capacity | Medium | High | Low |
| Complexity | Low | Medium | Lowest |
| Edge suitability | Excellent | Poor | Good |

### Key Benefits
1. **Etcd quorum**: 3 nodes maintain HA for etcd
2. **Resource optimization**: No dedicated control plane nodes sitting idle
3. **Simplified management**: Fewer nodes to maintain
4. **Edge-appropriate**: Fits resource-constrained environments

## Consequences

### Positive
- **Cost effective**: Fewer physical/virtual machines required
- **Simplified operations**: Single node type to manage
- **HA maintained**: Survives single node failure
- **Faster deployment**: Fewer nodes to provision

### Negative
- **Limited scale**: Workload capacity constrained by 3 nodes
- **Resource contention**: Control plane and workloads share resources
- **Upgrade complexity**: Rolling upgrades affect both control plane and workers
- **Not for large workloads**: May need to scale out for production

## Implementation

### Appliance Configuration
```yaml
# appliance-config.yaml
apiVersion: v1alpha1
kind: ApplianceConfig
ocpRelease:
  version: "4.20.0"
  channel: stable
diskSizeGB: 150
cpuArchitecture: x86_64
# 3-node compact cluster
controlPlane:
  replicas: 3
  schedulable: true  # Enable workloads on control plane
compute:
  replicas: 0  # No separate workers
```

### Node Requirements
```yaml
# Minimum per node for compact cluster
resources:
  cpu: 8 cores
  memory: 32 GB
  disk: 120 GB (root) + storage for workloads
```

### Scaling Path
If workload demands exceed 3-node capacity:
1. Add worker nodes post-deployment
2. Or migrate to standard architecture with dedicated workers

## Related ADRs
- ADR 0005: OpenShift Appliance Builder Integration
- ADR 0006: Lifecycle Management Strategy
