# OpenShift Cluster Configuration Examples

This directory contains declarative YAML configurations for OpenShift cluster deployment using the Agent-Based Installer.

## Topology Examples

### SNO (Single-Node OpenShift)

**Files**: `sno-quay.yml`, `sno-harbor.yml`, `sno-jfrog.yml`

**Resources**:
- 1 node (combined control plane + worker)
- 8 vCPU minimum
- 32GB RAM minimum
- 130GB disk

**Use Cases**:
- Development/testing
- Edge deployments
- Resource-constrained environments

**VIP Configuration**:
- Single IP for API, Ingress, and Rendezvous

---

### 3-Node Compact

**Files**: `compact-3node-quay.yml`, `compact-3node-harbor.yml`, `compact-3node-jfrog.yml`

**Resources**:
- 3 control plane nodes (schedulable)
- 0 dedicated workers
- 6 vCPU per node
- 24GB RAM per node
- Total: 18 vCPU, 72GB RAM

**Use Cases**:
- Small production clusters
- Lab environments
- Proof of concept

**VIP Configuration**:
- Separate VIPs for API and Ingress
- First control plane node as rendezvous IP

**Network Configuration**:
- Static IP per node via NMState
- MAC address binding for consistent provisioning

---

### HA Cluster

**Files**: `ha-cluster-quay.yml`, `ha-cluster-harbor.yml`

**Resources**:
- 3 control plane nodes (not schedulable)
- 3+ worker nodes (dedicated for workloads)
- Control: 6 vCPU, 24GB RAM per node
- Workers: 12 vCPU, 32GB RAM per node
- Total: 18 vCPU (control) + 36 vCPU (workers) = 54+ vCPU

**Use Cases**:
- Production deployments
- High availability requirements
- Large-scale workloads

**VIP Configuration**:
- Separate VIPs for API, Ingress, and Rendezvous
- Load balancing across control plane nodes

**Network Configuration**:
- Static IP per node (6 total)
- MAC address binding
- Supports VLAN and bonding configurations

## Multi-Registry Support

All configuration examples include variants for:

- **Quay** (Primary) - Project maintained
- **Harbor** (Community) - Project-based structure  
- **JFrog** (Community) - Docker-local repositories

## Usage

```bash
# Deploy SNO cluster with Quay registry
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @extra_vars/cluster-configs/sno-quay.yml

# Deploy 3-node compact cluster with Quay
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @extra_vars/cluster-configs/compact-3node-quay.yml

# Deploy HA cluster with Harbor registry
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @extra_vars/cluster-configs/ha-cluster-harbor.yml

# Test topology validation (without deployment)
ansible-playbook playbooks/test-topology-validation.yml
```

## Required Variables

### Common (All Topologies)
- `cluster_name` - Cluster identifier
- `base_domain` - DNS base domain
- `cluster_topology` - `sno` | `compact` | `ha`
- `ocp_version` - OpenShift version (e.g., "4.21")
- `registry_type` - `quay` | `harbor` | `jfrog`
- `registry_url` - Mirror registry URL
- `pull_secret_path` - Path to pull secret JSON

### SNO Specific
- `api_vip` - Single IP for API, Ingress, Rendezvous
- `vm_memory_mb` - Minimum 32768 (32GB)
- `vm_vcpus` - Minimum 8

### Compact/HA Specific
- `api_vip` - Separate VIP for API
- `ingress_vip` - Separate VIP for Ingress
- `rendezvous_ip` - First control plane node IP
- `control_plane_nodes` - List of 3 nodes with `name`, `ip`, `mac`

### HA Specific (Additional)
- `worker_nodes` - List of 2+ nodes with `name`, `ip`, `mac`
- `vm_memory_mb_control` - Control plane node memory
- `vm_vcpus_control` - Control plane node vCPU
- `vm_memory_mb_worker` - Worker node memory
- `vm_vcpus_worker` - Worker node vCPU

## Community Contributions

To add support for a new registry type:

1. Create `roles/openshift_cluster_deploy/vars/<registry-type>.yml`
2. Define `registry_mirror_paths` with your registry's path structure
3. Create example configs in this directory
4. Test with `playbooks/test-registry-abstraction.yml`
5. Submit PR with working configuration

See `vars/harbor.yml` and `vars/jfrog.yml` for examples.
