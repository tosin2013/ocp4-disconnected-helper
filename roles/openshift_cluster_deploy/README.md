# OpenShift Cluster Deploy Role

**ADR**: ADR-0035 - Adopt OpenShift Agent-Based Installer for Cluster Deployment Automation

## Overview

This Ansible role automates OpenShift cluster deployment using the Agent-Based Installer with support for:

- **Three deployment topologies**: SNO (Single-Node), 3-node compact, HA cluster
- **Three registry types**: Quay (primary), Harbor (community), JFrog (community)
- **Two DNS strategies**: dnsmasq (local dev), Route53 (production)
- **Disconnected/air-gapped environments**: Uses mirrored registries

## Architecture

Follows **ADR 0024 atomic roles pattern** with 8-phase orchestration:

1. **Phase 0**: Validate prerequisites
2. **Phase 1**: Prepare installation directory
3. **Phase 2**: Generate cluster manifests
4. **Phase 3**: Create bootable ISO
5. **Phase 4**: Configure DNS
6. **Phase 5**: Provision VMs (optional)
7. **Phase 6**: Monitor installation
8. **Phase 7**: Configure cluster access

## Quick Start

### Prerequisites

- OpenShift 4.19+ installer binary at `/usr/local/bin/openshift-install`
- Pull secret at `/root/pull-secret.json`
- Mirror registry deployed (Workflow 1)
- Operators mirrored (Workflow 2)

### Example Playbook

```yaml
---
- name: Deploy OpenShift Cluster
  hosts: localhost
  gather_facts: false
  roles:
    - role: openshift_cluster_deploy
      cluster_name: "ocp4"
      base_domain: "example.com"
      cluster_topology: "sno"  # or 'compact' or 'ha'
      registry_type: "quay"    # or 'harbor' or 'jfrog'
      registry_url: "registry.example.com:8443"
      ocp_version: "4.21"
```

### Topology Examples

#### SNO (Single-Node OpenShift)
```yaml
cluster_topology: "sno"
control_plane_replicas: 1
compute_replicas: 0
vm_memory_mb: 32768
vm_vcpus: 8
```

#### 3-Node Compact
```yaml
cluster_topology: "compact"
control_plane_replicas: 3
compute_replicas: 0
vm_memory_mb: 24576
vm_vcpus: 6
```

#### HA Cluster
```yaml
cluster_topology: "ha"
control_plane_replicas: 3
compute_replicas: 2
vm_memory_mb: 24576  # control plane
vm_vcpus: 6
```

## Multi-Registry Support

### Quay (Primary - Maintained by Project)
```yaml
registry_type: "quay"
registry_url: "registry.example.com:8443"
```

Uses `vars/quay.yml` for Quay-specific paths.

### Harbor (Community Contribution)
```yaml
registry_type: "harbor"
registry_url: "harbor.example.com"
```

Uses `vars/harbor.yml` for Harbor project-based structure.

### JFrog Artifactory (Community Contribution)
```yaml
registry_type: "jfrog"
registry_url: "jfrog.example.com"
```

Uses `vars/jfrog.yml` for JFrog docker registry paths.

## DNS Configuration

### dnsmasq (Local Development)
```yaml
dns_provider: "dnsmasq"
```

Configures local dnsmasq with cluster DNS records.

### Route53 (Production)
```yaml
dns_provider: "route53"
aws_access_key_id: "{{ lookup('env', 'AWS_ACCESS_KEY_ID') }}"
aws_secret_access_key: "{{ lookup('env', 'AWS_SECRET_ACCESS_KEY') }}"
```

Creates DNS records in AWS Route53.

## Variables

See `defaults/main.yml` for all configurable variables.

**Required Variables**:
- `cluster_name`
- `base_domain`
- `ocp_version`
- `registry_url`
- `pull_secret_path`

**Important Variables**:
- `cluster_topology`: `sno` | `compact` | `ha`
- `registry_type`: `quay` | `harbor` | `jfrog`
- `dns_provider`: `dnsmasq` | `route53`
- `provision_vms`: `true` | `false`

## Dependencies

- **common_vm** role (from ADR 0024) - Used when `provision_vms: true`
- **community.libvirt** collection - VM provisioning
- **kubernetes.core** collection - Cluster validation

## Tags

- `validate` - Run only prerequisite validation
- `manifests` - Generate manifests only
- `iso` - Create ISO only
- `provision` - Provision VMs only
- `monitor` - Monitor installation only

## Integration with AAP Workflows

This role is designed to be used as **AAP Workflow 3** nodes:

- **Node 1**: Validate Prerequisites
- **Node 2**: Generate ISO
- **Node 3**: Provision VMs
- **Node 4**: Monitor Installation
- **Node 5**: Configure Access

## Rollback

If deployment fails, destroy resources:

```bash
# Destroy VMs
virsh destroy ocp4-master-0
virsh undefine ocp4-master-0

# Remove installation directory
rm -rf /root/openshift-install
```

## License

Apache-2.0

## Author

OCP4 Disconnected Helper Project

## Related Documentation

- ADR-0035: Adopt OpenShift Agent-Based Installer
- ADR-0024: Roles and Collections Architecture
- ADR-0032: AAP Workflow Orchestration Strategy
