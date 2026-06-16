# OpenShift Cluster Topologies Reference

Comprehensive reference for OpenShift cluster topologies supported by the Agent-Based Installer.

---

## Overview

The Agent-Based Installer supports three deployment topologies, each optimized for different use cases and resource constraints.

| Topology | Nodes | Control Plane | Workers | Schedulable Control Plane | Use Case |
|----------|-------|---------------|---------|---------------------------|----------|
| **SNO** | 1 | 1 | 0 | ✅ Yes | Development, edge, resource-constrained |
| **Compact** | 3 | 3 | 0 | ✅ Yes | Small production, lab, POC |
| **HA** | 6+ | 3 | 2+ | ❌ No | Production, high availability |

---

## Single-Node OpenShift (SNO)

### Architecture

```
┌─────────────────────────────────────┐
│  Single Node                        │
│  ├─ Control Plane (etcd, API, etc.) │
│  └─ Worker (application pods)       │
│                                      │
│  Roles: control-plane,master,worker │
└─────────────────────────────────────┘
```

### Resource Requirements

**Minimum**:
- **RAM**: 32GB
- **vCPU**: 8 cores
- **Disk**: 130GB

**Recommended**:
- **RAM**: 48GB (for operator workloads)
- **vCPU**: 12 cores
- **Disk**: 200GB (with ODF/storage operators)

### Network Configuration

**Single IP for all services**:
- API endpoint: `api.<cluster>.<domain>` → `192.168.10.10`
- Ingress wildcard: `*.apps.<cluster>.<domain>` → `192.168.10.10`
- Rendezvous IP: `192.168.10.10` (same)

**No external load balancer required** - single node handles all traffic.

### Example Configuration

```yaml
# extra_vars/cluster-configs/sno-quay.yml
cluster_name: "ocp4-sno"
base_domain: "sandbox3377.opentlc.com"
cluster_topology: "sno"
control_plane_replicas: 1
compute_replicas: 0

# Single IP for all services
api_vip: "192.168.10.10"
ingress_vip: "192.168.10.10"
rendezvous_ip: "192.168.10.10"

# VM resources
vm_memory_mb: 32768  # 32GB
vm_vcpus: 8
vm_disk_size_gb: 130

registry_type: "quay"
registry_url: "registry.sandbox3377.opentlc.com:8443"
ocp_version: "4.21"
```

### Pros

✅ **Minimal resources** - Single node, no HA overhead  
✅ **Simple networking** - Single IP, no load balancer  
✅ **Fast deployment** - 35-70 minutes typical  
✅ **Edge-optimized** - Low power, small footprint  
✅ **Development-friendly** - Quick iteration, easy teardown  

### Cons

❌ **No high availability** - Single point of failure  
❌ **Limited scale** - ~100 pods recommended max  
❌ **Maintenance downtime** - Updates require node restart  
❌ **Resource contention** - Control plane + workloads share resources  

### Use Cases

- **Edge deployments**: Retail, IoT, remote sites
- **Development/testing**: Local OpenShift for developers
- **POC/demos**: Quick cluster provisioning
- **Resource-constrained environments**: Limited hardware
- **CI/CD runners**: Ephemeral test clusters

### Deployment Time

- **Preparation**: 5-10 minutes (ISO generation)
- **Bootstrap**: 20-40 minutes (cluster bootstrap)
- **Operators**: 10-20 minutes (all operators available)
- **Total**: **35-70 minutes**

---

## Compact (3-Node)

### Architecture

```
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  Master-0        │  │  Master-1        │  │  Master-2        │
│  ├─ Control      │  │  ├─ Control      │  │  ├─ Control      │
│  │  Plane        │  │  │  Plane        │  │  │  Plane        │
│  └─ Worker       │  │  └─ Worker       │  │  └─ Worker       │
│     (Schedulable)│  │     (Schedulable)│  │     (Schedulable)│
└──────────────────┘  └──────────────────┘  └──────────────────┘
         │                     │                     │
         └─────────────────────┴─────────────────────┘
                    etcd quorum (3 members)
```

### Resource Requirements

**Per Node**:
- **RAM**: 24GB
- **vCPU**: 6 cores
- **Disk**: 130GB

**Total Cluster**:
- **RAM**: 72GB (3 × 24GB)
- **vCPU**: 18 cores (3 × 6)
- **Disk**: 390GB (3 × 130GB)

### Network Configuration

**Separate VIPs for API and Ingress**:
- API endpoint: `api.<cluster>.<domain>` → `192.168.10.20`
- Ingress wildcard: `*.apps.<cluster>.<domain>` → `192.168.10.21`
- Rendezvous IP: `192.168.10.30` (first control plane node)

**Static IPs per node** (via NMState in agent-config.yaml):
```
master-0: 192.168.10.30 (MAC: 52:54:00:10:30:01)
master-1: 192.168.10.31 (MAC: 52:54:00:10:30:02)
master-2: 192.168.10.32 (MAC: 52:54:00:10:30:03)
```

**Internal load balancing** via keepalived (no external LB required).

### Example Configuration

```yaml
# extra_vars/cluster-configs/compact-3node-quay.yml
cluster_name: "ocp4-compact"
base_domain: "sandbox3377.opentlc.com"
cluster_topology: "compact"
control_plane_replicas: 3
compute_replicas: 0

# Separate VIPs
api_vip: "192.168.10.20"
ingress_vip: "192.168.10.21"
rendezvous_ip: "192.168.10.30"  # First control plane

# Per-node resources
vm_memory_mb: 24576  # 24GB
vm_vcpus: 6
vm_disk_size_gb: 130

# Node definitions
control_plane_nodes:
  - name: "master-0"
    ip: "192.168.10.30"
    mac: "52:54:00:10:30:01"
  - name: "master-1"
    ip: "192.168.10.31"
    mac: "52:54:00:10:30:02"
  - name: "master-2"
    ip: "192.168.10.32"
    mac: "52:54:00:10:30:03"
```

### Pros

✅ **High availability** - Survives single node failure  
✅ **etcd quorum** - 3-member cluster (2 failures tolerated for reads)  
✅ **No external LB** - Built-in keepalived for VIPs  
✅ **Cost-effective** - No dedicated worker nodes  
✅ **Production-ready** - For small workloads (< 200 pods)  

### Cons

❌ **Resource sharing** - Control plane + workloads compete  
❌ **Limited scale** - ~200 pods recommended max  
❌ **Update complexity** - Must drain nodes carefully  
❌ **Noisy neighbor** - Workload pods can impact control plane  

### Use Cases

- **Small production clusters**: < 50 application pods
- **Lab environments**: Realistic HA testing
- **POC with HA**: Demonstrate high availability
- **Department clusters**: Single-team workloads
- **Edge (HA)**: Remote sites needing redundancy

### Deployment Time

- **Preparation**: 5-10 minutes (ISO generation)
- **Bootstrap**: 20-40 minutes (cluster bootstrap)
- **Control plane**: 5-10 minutes (3 nodes join)
- **Operators**: 10-20 minutes (all operators available)
- **Total**: **40-80 minutes**

---

## HA (High Availability)

### Architecture

```
Control Plane (Non-Schedulable)          Workers (Schedulable)
┌──────────────┐ ┌──────────────┐ ┌──────────────┐   ┌──────────────┐ ┌──────────────┐
│  Master-0    │ │  Master-1    │ │  Master-2    │   │  Worker-0    │ │  Worker-1    │
│  Control     │ │  Control     │ │  Control     │   │  Workloads   │ │  Workloads   │
│  Plane Only  │ │  Plane Only  │ │  Plane Only  │   │  Only        │ │  Only        │
└──────────────┘ └──────────────┘ └──────────────┘   └──────────────┘ └──────────────┘
       │                 │                 │                 │                 │
       └─────────────────┴─────────────────┴─────────────────┴─────────────────┘
              etcd quorum (3)                    Application workloads (2+)

                                  ┌──────────────┐
                                  │  Worker-2    │
                                  │  Workloads   │
                                  │  Only        │
                                  └──────────────┘
```

### Resource Requirements

**Control Plane (per node)**:
- **RAM**: 24GB
- **vCPU**: 6 cores
- **Disk**: 130GB

**Workers (per node)**:
- **RAM**: 32GB (or more for heavy workloads)
- **vCPU**: 12 cores (or more)
- **Disk**: 200GB+

**Minimum HA Cluster (6 nodes)**:
- **Control Plane**: 72GB RAM (3 × 24GB), 18 vCPU
- **Workers**: 96GB RAM (3 × 32GB), 36 vCPU
- **Total**: **168GB RAM, 54 vCPU**

### Network Configuration

**Separate VIPs + External Load Balancer Required**:

**VIPs**:
- API endpoint: `api.<cluster>.<domain>` → `192.168.10.100` (via LB)
- Ingress wildcard: `*.apps.<cluster>.<domain>` → `192.168.10.101` (via LB)
- Rendezvous IP: `192.168.10.110` (first control plane node)

**Load Balancer Configuration**:

**API Load Balancer** (TCP 6443):
```
Backend: master-0:6443, master-1:6443, master-2:6443
Health check: TCP 6443
VIP: 192.168.10.100
```

**Ingress Load Balancer** (TCP 443, 80):
```
Backend: worker-0:443, worker-1:443, worker-2:443
Health check: TCP 443
VIP: 192.168.10.101
```

**Machine Config Server** (TCP 22623 - bootstrap only):
```
Backend: master-0:22623, master-1:22623, master-2:22623
```

**Static IPs per node**:
```
# Control Plane
master-0: 192.168.10.110 (MAC: 52:54:00:10:10:01)
master-1: 192.168.10.111 (MAC: 52:54:00:10:10:02)
master-2: 192.168.10.112 (MAC: 52:54:00:10:10:03)

# Workers
worker-0: 192.168.10.120 (MAC: 52:54:00:10:20:01)
worker-1: 192.168.10.121 (MAC: 52:54:00:10:20:02)
worker-2: 192.168.10.122 (MAC: 52:54:00:10:20:03)
```

### Example Configuration

```yaml
# extra_vars/cluster-configs/ha-cluster-quay.yml
cluster_name: "ocp4-ha"
base_domain: "sandbox3377.opentlc.com"
cluster_topology: "ha"
control_plane_replicas: 3
compute_replicas: 3

# VIPs (via external load balancer)
api_vip: "192.168.10.100"
ingress_vip: "192.168.10.101"
rendezvous_ip: "192.168.10.110"

# Control plane resources
vm_memory_mb_control: 24576  # 24GB
vm_vcpus_control: 6

# Worker resources
vm_memory_mb_worker: 32768  # 32GB
vm_vcpus_worker: 12
vm_disk_size_gb_worker: 200

# Control plane nodes
control_plane_nodes:
  - name: "master-0"
    ip: "192.168.10.110"
    mac: "52:54:00:10:10:01"
  - name: "master-1"
    ip: "192.168.10.111"
    mac: "52:54:00:10:10:02"
  - name: "master-2"
    ip: "192.168.10.112"
    mac: "52:54:00:10:10:03"

# Worker nodes
worker_nodes:
  - name: "worker-0"
    ip: "192.168.10.120"
    mac: "52:54:00:10:20:01"
  - name: "worker-1"
    ip: "192.168.10.121"
    mac: "52:54:00:10:20:02"
  - name: "worker-2"
    ip: "192.168.10.122"
    mac: "52:54:00:10:20:03"
```

### Pros

✅ **Production-grade** - Full redundancy and fault tolerance  
✅ **Dedicated workers** - Control plane isolated from workloads  
✅ **Scalable** - Add workers without impacting control plane  
✅ **Rolling updates** - Zero-downtime upgrades  
✅ **Resource isolation** - Workload surges don't affect cluster stability  

### Cons

❌ **Higher cost** - Minimum 6 nodes, 168GB+ RAM  
❌ **Complex networking** - External load balancer required  
❌ **Longer deployment** - 45-90 minutes  
❌ **More maintenance** - More nodes to manage  

### Use Cases

- **Production workloads**: Mission-critical applications
- **Multi-tenant clusters**: Multiple teams/projects
- **Large-scale deployments**: 500+ pods
- **Compliance requirements**: HA mandated by policy
- **SLA-driven**: < 99.9% uptime requirements

### Deployment Time

- **Preparation**: 5-10 minutes (ISO generation)
- **Bootstrap**: 20-40 minutes (cluster bootstrap)
- **Control plane**: 5-10 minutes (3 nodes join)
- **Workers**: 10-20 minutes (CSR approval + join)
- **Operators**: 10-20 minutes (all operators available)
- **Total**: **50-100 minutes**

---

## Topology Comparison

### Resource Summary

| Aspect | SNO | Compact | HA |
|--------|-----|---------|-----|
| **Minimum Nodes** | 1 | 3 | 6 |
| **Minimum RAM** | 32GB | 72GB | 168GB |
| **Minimum vCPU** | 8 | 18 | 54 |
| **Disk per Node** | 130GB | 130GB | 130-200GB |
| **Load Balancer** | ❌ No | ❌ No | ✅ Required |
| **Deployment Time** | 35-70m | 40-80m | 50-100m |

### Availability

| Feature | SNO | Compact | HA |
|---------|-----|---------|-----|
| **Node Failures Tolerated** | 0 | 1 | 2 (control), unlimited (workers) |
| **Update Downtime** | ✅ Yes | ⚠️ Brief | ❌ Zero |
| **etcd Quorum** | N/A (single) | 3 members | 3 members |
| **API Availability** | Single node | keepalived VIP | External LB |
| **Ingress Availability** | Single node | keepalived VIP | External LB |

### Scale

| Metric | SNO | Compact | HA |
|--------|-----|---------|-----|
| **Max Pods (Recommended)** | ~100 | ~200 | 1000+ |
| **Max Projects** | ~20 | ~50 | Unlimited |
| **Scalability** | Fixed (1 node) | Fixed (3 nodes) | Add workers |
| **Storage** | Local only | Local or network | Network recommended |

### Cost (Relative)

| Cost Factor | SNO | Compact | HA |
|-------------|-----|---------|-----|
| **Hardware** | 1× | 3× | 6× |
| **Network** | Simple | Simple | Complex (LB) |
| **Operations** | Low | Medium | High |
| **Licensing** | 1 node | 3 nodes | 6+ nodes |

---

## Choosing a Topology

### Decision Tree

```
Do you need high availability?
  ├─ No → Do you have resource constraints?
  │       ├─ Yes → SNO (1 node, 32GB)
  │       └─ No  → Compact (3 nodes, 72GB) for HA practice
  │
  └─ Yes → What's your workload scale?
          ├─ < 200 pods   → Compact (3 nodes, 72GB)
          └─ > 200 pods   → HA (6+ nodes, 168GB+)
```

### By Use Case

| Use Case | Recommended Topology | Justification |
|----------|---------------------|---------------|
| **Development/Testing** | SNO | Fast iteration, easy teardown |
| **Edge Computing** | SNO or Compact | Low resources, resilience varies |
| **POC/Demo** | SNO or Compact | Quick setup, realistic HA optional |
| **Small Production** | Compact | HA + cost-effective |
| **Enterprise Production** | HA | Full redundancy, scalability |
| **Multi-tenant** | HA | Resource isolation, scale |
| **CI/CD Runners** | SNO (ephemeral) | Fast provisioning |

### By Environment

| Environment | KVM/Nested | Bare Metal | Cloud IaaS |
|-------------|------------|------------|------------|
| **SNO** | ✅ Excellent | ✅ Good | ✅ Good |
| **Compact** | ⚠️ Resource-intensive | ✅ Excellent | ✅ Good |
| **HA** | ❌ Challenging | ✅ Excellent | ✅ Excellent |

**Notes**:
- **KVM/Nested**: SNO ideal, Compact feasible, HA resource-constrained
- **Bare Metal**: All topologies supported, HA recommended for production
- **Cloud IaaS**: All topologies, leverage cloud LB for HA

---

## Migration Between Topologies

**Supported Migration Paths**:
- ❌ SNO → Compact: Not supported (cluster reinstall required)
- ❌ SNO → HA: Not supported (cluster reinstall required)
- ❌ Compact → HA: Not supported (cluster reinstall required)
- ✅ HA → HA (add workers): Supported (scale workers only)

**To change topology**: Backup applications, redeploy cluster, restore applications.

---

## Related Documentation

- [Deploy OpenShift Cluster (Agent-Based)](../how-to/deploy-openshift-cluster-agent-based.md)
- [Tutorial: Your First OpenShift Cluster](../tutorials/your-first-openshift-cluster.md)
- [Configure DNS for OpenShift Clusters](../how-to/configure-dns-for-openshift-clusters.md)
- ADR-0035: Adopt OpenShift Agent-Based Installer

---

## References

- [OpenShift Cluster Topologies](https://docs.openshift.com/container-platform/4.21/architecture/architecture-installation.html)
- [Single-Node OpenShift](https://docs.openshift.com/container-platform/4.21/installing/installing_sno/install-sno-preparing-to-install-sno.html)
- [Agent-Based Installer](https://docs.openshift.com/container-platform/4.21/installing/installing_with_agent_based_installer/preparing-to-install-with-agent-based-installer.html)
