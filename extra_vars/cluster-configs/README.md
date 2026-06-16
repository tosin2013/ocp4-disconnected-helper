# OpenShift Cluster Configuration Examples

This directory contains declarative YAML configurations for OpenShift cluster deployment using the Agent-Based Installer.

## Topology Examples

### SNO (Single-Node OpenShift)

**File**: `sno-quay.yml`, `sno-harbor.yml`, `sno-jfrog.yml`

**Resources**:
- 1 node (combined control plane + worker)
- 8 vCPU minimum
- 32GB RAM minimum
- 130GB disk

**Use Cases**:
- Development/testing
- Edge deployments
- Resource-constrained environments

### 3-Node Compact (Coming Soon)

**Resources**:
- 3 control plane nodes (schedulable)
- 0 dedicated workers
- 6 vCPU per node
- 24GB RAM per node

**Use Cases**:
- Small production clusters
- Lab environments
- Proof of concept

### HA Cluster (Coming Soon)

**Resources**:
- 3 control plane nodes
- 2+ worker nodes
- 6 vCPU (control) / 12+ vCPU (workers)
- 24GB RAM (control) / 32-48GB (workers)

**Use Cases**:
- Production deployments
- High availability requirements
- Large-scale workloads

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

# Deploy SNO cluster with Harbor registry
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @extra_vars/cluster-configs/sno-harbor.yml

# Deploy SNO cluster with JFrog registry
ansible-playbook playbooks/deploy-openshift-cluster.yml \
  -e @extra_vars/cluster-configs/sno-jfrog.yml
```

## Required Variables

All configs must define:
- `cluster_name`
- `base_domain`
- `cluster_topology`
- `ocp_version`
- `registry_type`
- `registry_url`
- `pull_secret_path`

## Community Contributions

To add support for a new registry type:

1. Create `roles/openshift_cluster_deploy/vars/<registry-type>.yml`
2. Define `registry_mirror_paths` with your registry's path structure
3. Create example configs in this directory
4. Test with `playbooks/test-registry-abstraction.yml`
5. Submit PR with working configuration

See `vars/harbor.yml` and `vars/jfrog.yml` for examples.
