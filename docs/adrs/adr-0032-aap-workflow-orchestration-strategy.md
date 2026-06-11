# ADR 0032: AAP Workflow Orchestration for Infrastructure Lifecycle Management

## Date
2026-06-10

## Status
Accepted → **Validated in Production (v1.2)**

**Production Validation**: 2026-06-11 (Release v1.2)  
**Workflows Deployed**: 
- Workflow ID 36: "Disconnected OpenShift Image Mirroring" (3-node with operator validation)
- Validation successful in Workflow Job #118 (all 3 nodes passed)

## Context

Currently, infrastructure deployment and teardown are performed via manual `ansible-playbook` CLI execution (Tier 1 automation). While ADR 0021 adopted AAP 2.5 as the automation platform, it did not define how workflows would be structured or which components should be orchestrated via AAP vs manual playbooks.

We have successfully implemented two AAP workflows:
1. **Workflow ID 18**: Deploy Disconnected OpenShift Infrastructure (Phase 1: download-to-disk + Phase 2: push-to-registry)
2. **Workflow ID 21**: Teardown oc-mirror Workspace (dry-run, force, and clean-all modes)

These workflows establish a proven pattern for infrastructure lifecycle management.

### Current Infrastructure Landscape

The project manages multiple infrastructure components across different tiers:

**Foundational (Bootstrap) Tier:**
- VyOS Router (network infrastructure prerequisite - ADR 0025)
- DNS Services (required for name resolution)
- AAP 2.5 (automation platform itself)
- IBM Cloud hypervisor (one-time provisioning)

**Application Tier (Workflow-Managed):**
- Quay Mirror Registry (operational with workflows)
- oc-mirror operations (download, push, cleanup)
- Future: Harbor/JFrog registries
- Future: OpenShift cluster nodes
- Future: Storage VMs
- Future: Monitoring infrastructure

### Limitations of Manual Playbook Execution

Manual `ansible-playbook` CLI execution has operational limitations:
- No visual progress tracking (users must watch terminal output)
- No centralized job history (logs scattered across systems)
- Difficult to chain multi-step operations (requires scripting or documentation)
- No approval gates or notifications (all-or-nothing execution)
- Requires direct SSH access and Ansible CLI expertise
- No role-based access control (anyone with SSH can run any playbook)

### Workflow Orchestration Capabilities

AAP workflow orchestration provides:
- Visual workflow designer and real-time execution monitoring
- Job template reusability across workflows
- Conditional execution nodes and approval gates
- Centralized logging with audit trail
- Role-based access control (RBAC)
- Integration capabilities (webhooks, notifications, external triggers)
- Scheduled execution and event-driven automation

## Decision

**Adopt AAP workflow orchestration as the standard pattern for infrastructure lifecycle management (deployment and teardown).**

### Included in Workflow Orchestration

The following components MUST be managed via AAP workflows:
- **Registry VMs**: Quay, Harbor, JFrog (deploy + teardown)
- **oc-mirror Operations**: download-to-disk, push-to-registry, workspace cleanup
- **OpenShift Clusters**: node provisioning, cluster deployment (future)
- **Storage Infrastructure**: NFS VMs, persistent storage (future)
- **Monitoring Stack**: Prometheus, Grafana, Loki (future)
- **Certificate Management**: Let's Encrypt renewal, self-signed CA rotation
- **Backup/Restore**: Infrastructure state backup and recovery

### Excluded from Workflow Orchestration (Manual Playbook Only)

The following components MUST remain manual playbook execution:
- **VyOS Router**: Network foundation prerequisite (ADR 0025), deployed before AAP
- **DNS Services**: Foundational dependency for all name resolution
- **AAP Deployment**: Bootstrap paradox (cannot use AAP to deploy itself)
- **Hypervisor Setup**: One-time IBM Cloud VSI provisioning

**Rationale for Exclusions**: These components are either prerequisites for AAP operation (VyOS, DNS) or create circular dependencies (AAP deploying itself). They require one-time manual deployment.

### Workflow Design Principles

1. **Atomic Job Templates**: Each job template performs one well-defined task (provision VM, configure service, verify health)
2. **Two-Workflow Pattern**: Separate deployment and teardown workflows for each component (enables independent lifecycle management)
3. **Idempotent Operations**: All workflows safe to re-run without side effects
4. **Safety Gates**: Teardown workflows include dry-run mode and confirmation prompts by default
5. **Dependency Awareness**: Workflows check prerequisites before execution (fail fast if dependencies missing)
6. **Shared Templates**: Common tasks (VM provisioning, certificate setup) as reusable job templates

### Workflow Implementation Pattern

Proven pattern from oc-mirror workflows:

```yaml
# Deployment Workflow
Workflow: Deploy [Component] Infrastructure
  Node 1: Check Prerequisites
    - Verify VyOS router accessible
    - Verify DNS resolution working
    - Verify storage paths exist
  Node 2: Provision VM(s)
    - Create KVM guest with cloud-init
    - Wait for SSH connectivity
  Node 3: Configure [Component]
    - Install packages
    - Configure service
    - Setup certificates
  Node 4: Verify [Component]
    - Health checks
    - Integration tests
  Node 5: Register Service
    - Update DNS records
    - Add to monitoring

# Teardown Workflow
Workflow: Teardown [Component] Infrastructure
  Node 1: Pre-Flight Checks (dry-run mode)
    - Calculate resources to remove
    - Display impact summary
  Node 2: Confirmation Gate (unless force=true)
    - User approval required
  Node 3: Backup/Export (if applicable)
    - Export configuration
    - Backup persistent data
  Node 4: Remove [Component]
    - Stop services
    - Remove packages
    - Clean configurations
  Node 5: Cleanup VM(s)
    - Destroy KVM guest
    - Remove storage volumes
  Node 6: Cleanup Registry
    - Remove DNS records
    - Remove monitoring targets
```

### Workflow Configuration Management

All workflow definitions MUST be stored in Git:
- **Location**: `playbooks/aap-configuration/configure-[component]-workflow.yml`
- **Version Control**: Committed to `ocp4-disconnected-helper` repository
- **Authoritativeness**: Playbooks remain the source of truth; workflows call playbooks (never inline tasks)

## Consequences

### Positive Consequences

1. **Improved Operational Visibility**: Real-time workflow progress tracking in AAP Web UI (users can see execution status without SSH access)
2. **Centralized Automation Governance**: RBAC, audit logs, approval gates provide enterprise-grade controls
3. **Reduced Operational Errors**: Guided workflows with validation gates reduce human mistakes vs manual CLI
4. **Faster Onboarding**: New operators can use Web UI without mastering Ansible CLI
5. **Workflow Reusability**: Templates shared across development, staging, production environments
6. **Integration Capabilities**: Webhooks enable external system triggers (monitoring alerts → auto-remediation)

### Negative Consequences

1. **Increased AAP Resource Usage**: Controller CPU/memory increases with concurrent workflow executions
2. **Additional Maintenance Burden**: Must maintain both playbooks AND workflow configuration files
3. **Learning Curve**: Workflow designer requires different skillset than playbook authoring
4. **Dependency on AAP Availability**: Workflows unavailable if AAP Controller is down (fallback to manual playbooks)

### Risks and Mitigation

**Risk: Workflow Configuration Drift**
- Workflow definitions may diverge from underlying playbooks over time
- **Mitigation**: Playbooks remain authoritative; workflows call playbooks (not inline tasks). Regular workflow audits verify alignment.

**Risk: Over-Orchestration Complexity**
- Temptation to create complex nested workflows that are hard to debug
- **Mitigation**: Follow atomic job template principle. Limit workflow depth to 3 levels maximum.

**Risk: AAP Controller Performance Impact**
- Too many concurrent workflows could overload Controller resources
- **Mitigation**: Monitor Controller CPU/memory usage. Implement workflow execution limits (max 5 concurrent workflows).

**Risk: Bootstrap Dependency**
- If AAP is unavailable, all infrastructure operations blocked
- **Mitigation**: Maintain manual playbook execution capability. Document emergency recovery procedures using CLI.

## Alternatives Considered

### Alternative 1: Continue Manual Playbook CLI Execution (Tier 1 Only)
- **Pros**: Simpler architecture, no AAP dependency, direct control
- **Cons**: No centralized visibility, no RBAC, no audit trail, difficult onboarding
- **Rejected**: Does not meet enterprise operational requirements

### Alternative 2: Hybrid Approach (Workflows for Common Operations, Manual for Advanced)
- **Pros**: Balanced complexity, flexibility for edge cases
- **Cons**: Confusing for operators (which path to use?), governance gaps
- **Rejected**: Creates operational inconsistency and training burden

### Alternative 3: External Orchestrator (Jenkins, Tekton, GitHub Actions)
- **Pros**: Mature CI/CD platforms, extensive plugin ecosystems
- **Cons**: Additional infrastructure to manage, different automation paradigm
- **Rejected**: AAP 2.5 already adopted (ADR 0021), adding another orchestrator increases complexity

### Alternative 4: GitOps Approach (ArgoCD for Infrastructure)
- **Pros**: Git-native, declarative state management, drift detection
- **Cons**: Requires Kubernetes, limited support for VM infrastructure, steep learning curve
- **Rejected**: Project uses KVM VMs (not Kubernetes-native), GitOps better suited for container workloads

## Related ADRs

- **ADR 0006**: Lifecycle Management Strategy (defines OpenShift cluster upgrade workflow design and safety mechanisms)
- **ADR 0021**: Deprecate Airflow and Adopt AAP 2.5 (establishes AAP as automation platform)
- **ADR 0024**: Roles and Collections Architecture (atomic roles support modular workflows)
- **ADR 0025**: VyOS Router as Network Infrastructure Prerequisite (excluded from workflows)
- **ADR 0029**: Custom Execution Environment (provides oc-mirror tooling for workflows)

## Implementation Notes

### Phase 1: Registry Infrastructure Workflows (Current - June 2026)
- ✅ Completed: oc-mirror download/push/teardown workflows
- 🔄 In Progress: Quay registry VM deployment workflow
- 📋 Planned: Harbor and JFrog registry workflows

### Phase 2: Storage and Backup Workflows (Q3 2026)
- NFS VM provisioning workflow
- Backup/restore automation workflow
- Certificate renewal workflow

### Phase 3: OpenShift Cluster Workflows (Q4 2026)
- Cluster node provisioning workflow
- Cluster installation workflow
- **Cluster upgrade workflow** (see **ADR 0006: Lifecycle Management Strategy** for detailed upgrade workflow design)
  - Pre-upgrade health checks
  - Image mirroring (oc-mirror incremental)
  - Cluster state backup
  - Approval gates for production
  - ICSP/IDMS updates
  - ClusterVersion upgrade execution
  - Post-upgrade verification

### Workflow Template Repository Structure

```
playbooks/aap-configuration/
├── configure-complete-aap-setup.yml      # Bootstrap AAP with all workflows
├── configure-deployment-workflow.yml     # oc-mirror deployment (Workflow ID 18)
├── configure-teardown-workflow.yml       # oc-mirror teardown (Workflow ID 21)
├── configure-registry-vm-workflow.yml    # Registry VM lifecycle (future)
├── configure-storage-workflow.yml        # Storage infrastructure (future)
├── configure-cluster-workflow.yml        # OpenShift cluster provisioning (future)
└── configure-cluster-upgrade-workflow.yml # OpenShift cluster upgrades (future - see ADR 0006)
```

## Compliance and Audit Requirements

For enterprise environments requiring SOC 2 or ISO 27001 compliance:
1. All workflows MUST log execution to centralized AAP database
2. Approval gates MUST be enabled for production environment workflows
3. Workflow execution history MUST be retained for 90 days minimum
4. RBAC policies MUST enforce separation of duties (deployer ≠ approver)

## References

- [AAP 2.5 Workflow Documentation](https://docs.ansible.com/automation-controller/latest/html/userguide/workflows.html)
- [Ansible Best Practices for Workflow Design](https://docs.ansible.com/ansible/latest/user_guide/playbooks_best_practices.html)
- Existing Workflows: `https://aap.sandbox3377.opentlc.com/#/templates/workflow_job_template/18`
- ADR 0021: AAP 2.5 Adoption Decision
