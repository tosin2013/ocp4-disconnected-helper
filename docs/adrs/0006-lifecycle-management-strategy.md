# ADR 0006: Lifecycle Management Strategy

**Status:** Proposed  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 4 - Operational Model, Section 6 - Post-Deployment Lifecycle Management

## Context

The ocp4-disconnected-helper is not a one-time deployment tool but a **lifecycle management solution**. After initial cluster deployment, organizations need to:

1. Apply OpenShift version updates
2. Update operator catalogs
3. Add new operators
4. Patch security vulnerabilities

All of these operations must work in a fully disconnected environment.

## Decision

Implement a comprehensive lifecycle management strategy with:

1. **Repeatable mirroring**: `download-to-tar.yml` designed for repeated execution
2. **Incremental updates**: Leverage oc-mirror's stateful workspace
3. **Cluster update playbook**: New `update-cluster.yml` for orchestrating updates

### Operational Modes

| Mode | `clean_mirror_path` | Use Case |
|------|---------------------|----------|
| Initial Deployment | `true` | First-time mirror, full content download |
| Incremental Update | `false` | Regular updates, delta sync only |

## Rationale

### Why Lifecycle Focus?
1. **Security**: Clusters must receive security patches
2. **Compliance**: Many regulations require timely updates
3. **Features**: Access to new OpenShift capabilities
4. **Support**: Stay within supported version ranges

### Update Workflow
```
┌─────────────────────────────────────────────────────────────────┐
│                    Update Workflow                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Update imageset-config.yml                                  │
│     └── Add new version targets                                 │
│                                                                 │
│  2. Run download-to-tar.yml (clean_mirror_path=false)           │
│     └── Incremental download of new content                     │
│                                                                 │
│  3. Transfer tar to disconnected environment                    │
│     └── Physical media or approved transfer mechanism           │
│                                                                 │
│  4. Run push-tar-to-registry.yml                                │
│     └── Push new content to local registry                      │
│                                                                 │
│  5. Run update-cluster.yml                                      │
│     └── Update CVO, trigger cluster upgrade                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Consequences

### Positive
- **Continuous operations**: Clusters stay current and secure
- **Efficient updates**: Only download changed content
- **Automated process**: Playbooks handle complex update sequences
- **Audit trail**: Git-tracked configuration changes

### Negative
- **Operational discipline**: Requires regular update cycles
- **Storage growth**: Workspace accumulates over time
- **Coordination**: Updates must be planned and tested

## Implementation

### update-cluster.yml Variables
```yaml
# Target version for update
update_ocp_release_version: "4.20.0"
update_ocp_release_channel: "stable"

# Cluster access
cluster_kubeconfig: "/path/to/kubeconfig"
```

### Update Process
```yaml
# update-cluster.yml tasks (high-level)
- name: Verify current cluster version
  command: oc get clusterversion

- name: Apply new ICSP/IDMS manifests
  command: oc apply -f {{ icsp_manifest_path }}

- name: Update ClusterVersion to target release
  command: >
    oc adm upgrade --to-image={{ local_registry }}/{{ release_image }}

- name: Monitor upgrade progress
  command: oc get clusterversion -w
```

### GitHub Actions Integration
```yaml
# .github/workflows/update-cluster.yml
name: Cluster Update
on:
  workflow_dispatch:
    inputs:
      target_version:
        description: 'Target OCP version'
        required: true
jobs:
  update:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      - name: Run update playbook
        run: |
          ansible-playbook playbooks/update-cluster.yml \
            -e update_ocp_release_version=${{ inputs.target_version }}
```

## Related ADRs
- ADR 0003: oc-mirror for Image Mirroring
- ADR 0005: OpenShift Appliance Builder Integration
- ADR 0008: GitHub Actions Automation
