# ADR 0003: oc-mirror v2 for Image Mirroring

**Status:** Accepted  
**Date:** 2025-11-25  
**Revised:** 2025-12-06  
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
1. **Stateful mirroring**: Uses `working-dir` directory to track mirrored content
2. **Incremental updates**: Compares existing state with `imageset-config.yml` to download only changes
3. **Tar archive support**: Can output to tar files for air-gapped transfer
4. **Manifest generation**: Automatically creates ICSP/IDMS for cluster configuration

## Rationale

### Why oc-mirror v2?
1. **Official Red Hat tooling**: Maintained and supported by Red Hat
2. **OpenShift release graph awareness**: Understands upgrade paths and dependencies
3. **Operator catalog support**: Handles complex operator bundle mirroring
4. **Stateful operation**: Enables efficient incremental updates
5. **v1 Deprecation**: As of OCP 4.18, v1 is deprecated; v2 is mandatory starting 4.21

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
- **Workspace dependency**: Requires preserving `working-dir` between runs
- **Storage requirements**: Large disk space needed for workspace and archives
- **Complexity**: Configuration via `imageset-config.yml` requires understanding

## Implementation

### oc-mirror v2 CLI Syntax

**CRITICAL**: As of oc-mirror 4.18+, v1 is deprecated. The `--v2` flag is **mandatory**.

#### Workflow Commands

| Workflow | Command |
|----------|---------|
| **Mirror to Disk** | `oc-mirror -c <config> file://<path> --v2` |
| **Disk to Mirror** | `oc-mirror -c <config> --from file://<path> docker://<registry> --v2` |
| **Mirror to Mirror** | `oc-mirror -c <config> --workspace file://<path> docker://<registry> --v2` |

#### Key v2 Flags

| Flag | Description |
|------|-------------|
| `--v2` | **Required** - Use oc-mirror v2 (v1 deprecated) |
| `-c, --config` | Path to ImageSetConfiguration file |
| `--authfile` | Path to authentication file (**NOT** `-a`) |
| `--from` | Source path for disk-to-mirror workflow |
| `--workspace` | Working directory for mirror-to-mirror |
| `--dest-tls-verify=false` | Skip TLS verification for self-signed certs |
| `--continue-on-error` | Continue despite errors |

#### Example Commands

```bash
# Mirror to Disk (download to local storage)
oc-mirror -c /opt/images/imageSetConfig.yml \
    file:///opt/images \
    --authfile /root/pull-secret.json \
    --continue-on-error \
    --v2

# Disk to Mirror (push from local to registry)
oc-mirror -c /opt/images/imageSetConfig.yml \
    --from file:///opt/images \
    docker://mirror-registry.example.com:8443 \
    --authfile /root/pull-secret.json \
    --dest-tls-verify=false \
    --continue-on-error \
    --v2

# Direct Mirror to Mirror (connected environment)
oc-mirror -c /opt/images/imageSetConfig.yml \
    --workspace file:///opt/images \
    docker://mirror-registry.example.com:8443 \
    --authfile /root/pull-secret.json \
    --dest-tls-verify=false \
    --v2
```

### Workflow Diagram
```
┌─────────────────────────────────────────────────────────────────┐
│                    oc-mirror v2 Workflow                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  imageset-config.yml ──┐                                        │
│                        ▼                                        │
│  ┌─────────────────────────────────────┐                        │
│  │         oc-mirror --v2              │                        │
│  │  ┌─────────────────────────────┐    │                        │
│  │  │   working-dir/              │◀───┼── State (incremental)  │
│  │  └─────────────────────────────┘    │                        │
│  └─────────────────────────────────────┘                        │
│                        │                                        │
│                        ▼                                        │
│  ┌─────────────────────────────────────┐                        │
│  │     Output: working-dir archives    │                        │
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
    path: /opt/images
mirror:
  platform:
    graph: true
    channels:
      - name: stable-4.19
        minVersion: 4.19.0
        maxVersion: 4.19.99
        type: ocp
  operators:
    - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.19
      packages:
        - name: local-storage-operator
  additionalImages: []
  helm: {}
```

### Integration with Ansible Playbooks

**Per ADR 0002 and ADR 0012**, oc-mirror should be invoked via Ansible playbooks, NOT directly in DAGs:

```bash
# Use the download-to-tar.yml playbook
ansible-playbook -i playbooks/inventory playbooks/download-to-tar.yml \
    -e @extra_vars/download-to-tar-vars.yml

# Use the push-tar-to-registry.yml playbook  
ansible-playbook -i playbooks/inventory playbooks/push-tar-to-registry.yml \
    -e @extra_vars/push-tar-to-registry-vars.yml
```

The playbooks handle:
- oc-mirror binary installation
- ImageSetConfiguration templating
- Proper error handling and logging
- State management

## Related ADRs
- ADR 0002: Ansible Automation Framework
- ADR 0004: Dual Registry Support
- ADR 0006: Lifecycle Management Strategy
- ADR 0012: Airflow DAG Orchestration
