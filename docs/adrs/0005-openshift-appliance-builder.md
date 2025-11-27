# ADR 0005: OpenShift Appliance Builder Integration

**Status:** Proposed  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 5.1 - New Ansible Playbook for Appliance Building

## Context

Deploying OpenShift in fully disconnected environments traditionally requires:
1. Setting up a bootstrap node with network access
2. Configuring PXE boot or ISO-based installation
3. Manual intervention during the installation process

The **OpenShift Appliance Builder** provides an alternative approach by creating self-contained disk images that include all necessary components for installation.

## Decision

Integrate the OpenShift Appliance Builder into ocp4-disconnected-helper via a new `build-appliance.yml` playbook that:

1. Installs the `openshift-appliance` builder and dependencies
2. Generates `appliance-config.yaml` from user variables
3. Executes `openshift-appliance build` to create disk images

### Default Architecture
Deploy a **3-node compact cluster** where nodes serve as both control plane and workers, optimized for edge and resource-constrained disconnected environments.

## Rationale

### Why Appliance-Based Deployment?
1. **Simplified air-gap installation**: Single disk image contains everything needed
2. **Reproducibility**: Same image can deploy identical clusters
3. **Reduced complexity**: No PXE, DHCP, or bootstrap node required
4. **Edge-friendly**: Compact 3-node architecture suits edge deployments

### Alternatives Considered

| Alternative | Reason Not Selected |
|-------------|---------------------|
| Agent-based installer | Requires more infrastructure setup |
| UPI with PXE | Complex network requirements |
| Assisted Installer | Requires network connectivity |

## Consequences

### Positive
- **Streamlined deployment**: Single artifact for complete cluster
- **Consistent environments**: Identical images ensure reproducibility
- **Offline-first**: Designed for disconnected scenarios
- **Reduced time-to-deploy**: Pre-built images speed up installation

### Negative
- **Disk space**: Large appliance images (100+ GB)
- **Build time**: Initial appliance build is time-consuming
- **Flexibility**: Changes require rebuilding the appliance
- **Dependencies**: Requires specific tooling (podman, go, libguestfs)

## Implementation

### Required Dependencies
```yaml
# From PRD Section 7.2
dependencies:
  - podman
  - go (>= 1.19)
  - libguestfs-tools
  - coreos-installer
  - oc
  - oc-mirror (v2)
  - skopeo
```

### Playbook Variables
```yaml
# build-appliance.yml variables
ocp_release_version: "4.20.0"
ocp_release_channel: "stable"
appliance_disk_size_gb: 150
appliance_image_registry_uri: "registry.example.com"
appliance_image_registry_port: 5000
appliance_ssh_key: "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"
additional_images: []
operators:
  - local-storage-operator
  - odf-operator
```

### Build Workflow
```
┌─────────────────────────────────────────────────────────────────┐
│                 Appliance Build Workflow                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Install Dependencies                                        │
│     └── podman, go, libguestfs-tools, coreos-installer          │
│                                                                 │
│  2. Generate appliance-config.yaml                              │
│     └── From Ansible variables                                  │
│                                                                 │
│  3. Execute openshift-appliance build                           │
│     └── Creates bootable disk image                             │
│                                                                 │
│  4. Output: appliance.raw / appliance.qcow2                     │
│     └── Ready for deployment                                    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Integration Points

### With oc-mirror
The appliance builder consumes mirrored content from the local registry populated by `download-to-tar.yml` and `push-tar-to-registry.yml`.

### With kcli-pipelines
Orchestrated via kcli-pipelines for automated end-to-end deployment.

## Related ADRs
- ADR 0003: oc-mirror for Image Mirroring
- ADR 0006: Lifecycle Management Strategy
- ADR 0007: 3-Node Compact Cluster Architecture
