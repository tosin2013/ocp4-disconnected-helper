# ADR 0006: Lifecycle Management Strategy

**Status:** Accepted  
**Date:** 2025-11-25  
**Last Updated:** 2026-06-10 (AAP Workflow Integration)  
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

## AAP Workflow Integration (2026-06-10 Update)

**Context**: Since this ADR was originally proposed (2025-11-25), the project has adopted AAP 2.5 as the automation platform (ADR 0021) and established workflow orchestration as the standard pattern for infrastructure lifecycle management (ADR 0032).

**Impact on Lifecycle Management**:
- ❌ **Deprecated**: Manual playbook execution (`update-cluster.yml`)
- ❌ **Deprecated**: GitHub Actions workflow automation
- ✅ **Adopted**: AAP workflow orchestration for cluster upgrades

### Upgrade Workflow Pattern (AAP-Based)

Following ADR 0032 design principles (atomic job templates, two-workflow pattern, safety gates):

```
Workflow: Upgrade OpenShift Cluster
  
  Node 1: Pre-Upgrade Health Check
    Job Template: "Check Cluster Upgrade Prerequisites"
    - Verify cluster status (oc get clusterversion)
    - Check node health (all nodes Ready)
    - Validate etcd quorum
    - Check available storage capacity
    - Verify no pending PodDisruptionBudgets blocking
    
  Node 2: Mirror New Version Images
    Job Template: "Mirror OpenShift Upgrade Images"
    - Update imageset-config.yml with target version
    - Run oc-mirror (incremental: clean_mirror_path=false)
    - Push new images to disconnected registry
    - Verify image availability in local registry
    
  Node 3: Backup Cluster State
    Job Template: "Backup Cluster Configuration"
    - Export critical resources (ICSP/IDMS, ClusterVersion)
    - Create etcd snapshot
    - Document current cluster version
    - Store backup in /data/backups/cluster-[timestamp]/
    
  Node 4: Approval Gate (Production Only)
    Workflow Approval Node
    - Manual approval required for production clusters
    - Display upgrade summary (current → target version)
    - Show estimated downtime window
    - Confirm backup completion
    
  Node 5: Apply ICSP/IDMS Updates
    Job Template: "Update Image Content Source Policies"
    - Apply new ICSP/IDMS manifests for target version
    - Wait for MachineConfigPool updates to stabilize
    - Verify nodes accept new image sources
    
  Node 6: Trigger Cluster Upgrade
    Job Template: "Execute OpenShift Upgrade"
    - Run: oc adm upgrade --to-image=<local_registry>/<release_image>
    - Monitor ClusterVersion status (async task, timeout: 4 hours)
    - Track upgrade progress per node
    - Alert on upgrade failures
    
  Node 7: Post-Upgrade Verification
    Job Template: "Verify Cluster Upgrade Success"
    - Verify all nodes at target version
    - Run cluster health checks (oc adm must-gather)
    - Validate critical workloads running
    - Update cluster inventory with new version
    
  Node 8 (Failure Path): Rollback Alert
    Job Template: "Cluster Upgrade Rollback Notification"
    - Alert administrators of upgrade failure
    - Provide rollback instructions
    - Reference backup location
    - Create incident tracking ticket
```

### Safety Mechanisms

1. **Pre-Flight Checks**: Node health, etcd status, storage capacity
2. **Backup Before Upgrade**: Automated etcd snapshot + resource export
3. **Approval Gates**: Manual approval for production clusters (dev/staging can auto-approve)
4. **Incremental Mirroring**: Only download delta images (`clean_mirror_path: false`)
5. **Rollback Documentation**: Backup location and rollback procedures provided
6. **Async Monitoring**: Long-running upgrades (up to 4 hours) with progress tracking

### Workflow Configuration

**File**: `playbooks/aap-configuration/configure-cluster-upgrade-workflow.yml`

**Job Templates**:
1. Check Cluster Upgrade Prerequisites
2. Mirror OpenShift Upgrade Images
3. Backup Cluster Configuration
4. Update Image Content Source Policies
5. Execute OpenShift Upgrade
6. Verify Cluster Upgrade Success
7. Cluster Upgrade Rollback Notification

**Workflow Variables**:
```yaml
# Target upgrade version
target_ocp_version: "4.21.0"
target_ocp_channel: "stable-4.21"

# Cluster connection
cluster_name: "ocp4-prod"
cluster_kubeconfig_path: "/opt/kubeconfigs/ocp4-prod-kubeconfig"

# Safety controls
require_approval: true          # Approval gate for production
create_backup: true             # Backup before upgrade
allow_rollback: true            # Enable rollback on failure
upgrade_timeout: 14400          # 4 hours max upgrade time
```

### Operational Model

**Initial Deployment** (One-time):
- Use `clean_mirror_path: true` (full content download)
- Deploy cluster with mirrored images

**Incremental Updates** (Regular):
- Use `clean_mirror_path: false` (delta sync only)
- Run AAP "Upgrade OpenShift Cluster" workflow
- Approval gate ensures human oversight

**Update Cadence**:
- **Security Patches**: Within 30 days of release
- **Minor Versions**: Quarterly (e.g., 4.20 → 4.21)
- **Operator Catalogs**: Monthly or as needed

## Related ADRs
- **ADR 0003**: oc-mirror for Image Mirroring (provides incremental sync capability)
- **ADR 0021**: Deprecate Airflow and Adopt AAP 2.5 (establishes AAP as automation platform)
- **ADR 0032**: AAP Workflow Orchestration for Infrastructure Lifecycle Management (mandates workflow-based upgrades)
- ADR 0005: OpenShift Appliance Builder Integration (deprecated)
- ADR 0008: GitHub Actions Automation (deprecated)
