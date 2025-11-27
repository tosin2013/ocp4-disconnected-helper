# ADR 0003: oc-mirror v2 for Image Mirroring

**Status:** Accepted  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 6.3 - Registry Update Workflow and oc-mirror v2

## Context

Disconnected OpenShift environments require a reliable mechanism to:
- Mirror container images from Red Hat registries to local storage
- Support both full initial mirrors and incremental updates
- Maintain state to enable efficient delta synchronization
- Generate ICSP/IDMS manifests for cluster configuration

## Decision

Adopt **oc-mirror v2** as the primary tool for image mirroring operations.

### Key Features Utilized
1. **Stateful mirroring**: Uses `oc-mirror-workspace` directory to track mirrored content
2. **Incremental updates**: Compares existing state with `imageset-config.yml` to download only changes
3. **Tar archive support**: Can output to tar files for air-gapped transfer
4. **Manifest generation**: Automatically creates ICSP/IDMS for cluster configuration

## Rationale

### Why oc-mirror v2?
1. **Official Red Hat tooling**: Maintained and supported by Red Hat
2. **OpenShift release graph awareness**: Understands upgrade paths and dependencies
3. **Operator catalog support**: Handles complex operator bundle mirroring
4. **Stateful operation**: Enables efficient incremental updates

### Operational Model

| Workflow | `clean_mirror_path` | Behavior |
|----------|---------------------|----------|
| Initial Deployment | `true` | Full mirror from scratch (time-consuming, one-time) |
| Incremental Update | `false` | Delta sync using workspace state (standard operation) |

## Consequences

### Positive
- **Efficient updates**: Only downloads changed content after initial mirror
- **Consistency**: Ensures mirrored content matches OpenShift release requirements
- **Automation-friendly**: CLI-based, easily integrated into Ansible playbooks
- **Air-gap support**: Native tar archive output for disconnected transfer

### Negative
- **Workspace dependency**: Requires preserving `oc-mirror-workspace` between runs
- **Storage requirements**: Large disk space needed for workspace and archives
- **Complexity**: Configuration via `imageset-config.yml` requires understanding

## Implementation

### Workflow Diagram
```
┌─────────────────────────────────────────────────────────────────┐
│                    oc-mirror Workflow                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  imageset-config.yml ──┐                                        │
│                        ▼                                        │
│  ┌─────────────────────────────────────┐                        │
│  │         oc-mirror v2                │                        │
│  │  ┌─────────────────────────────┐    │                        │
│  │  │   oc-mirror-workspace/      │◀───┼── State (incremental)  │
│  │  └─────────────────────────────┘    │                        │
│  └─────────────────────────────────────┘                        │
│                        │                                        │
│                        ▼                                        │
│  ┌─────────────────────────────────────┐                        │
│  │     Output: tar archives            │                        │
│  │     + ICSP/IDMS manifests           │                        │
│  └─────────────────────────────────────┘                        │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Configuration Example
```yaml
# imageset-config.yml
kind: ImageSetConfiguration
apiVersion: mirror.openshift.io/v1alpha2
storageConfig:
  local:
    path: ./oc-mirror-workspace
mirror:
  platform:
    channels:
      - name: stable-4.20
        minVersion: 4.20.0
        maxVersion: 4.20.0
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.20
      packages:
        - name: local-storage-operator
```

## Related ADRs
- ADR 0004: Dual Registry Support
- ADR 0006: Lifecycle Management Strategy
