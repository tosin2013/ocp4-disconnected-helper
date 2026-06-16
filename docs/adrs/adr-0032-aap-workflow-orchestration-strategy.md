# ADR 0032: Multi-Workflow Orchestration for Complete OpenShift Disconnected Deployment

## Date
2026-06-10

**Updated**: 2026-06-16 (v1.3 - Multi-Workflow Architecture)

## Status
Accepted → **Validated in Production (v1.2)** → **Expanded (v1.3)**

**Production Validation**: 
- v1.2 (2026-06-11): Workflow ID 36 "Disconnected OpenShift Image Mirroring" (3-node with operator validation)
- v1.3 (2026-06-16): Multi-workflow architecture with conditional execution (3 workflows)

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

**Adopt AAP multi-workflow orchestration as the standard pattern for complete OpenShift disconnected deployment lifecycle.**

### Workflow Catalog (v1.3)

The complete deployment lifecycle is organized into **3 numbered workflows** with clear dependencies and execution order:

#### **Workflow 1: OpenShift Infrastructure Deployment**
**Purpose**: Deploy container registry infrastructure for disconnected OpenShift  
**Execution Model**: Sequential (5-step deployment)  
**Components**:
- Registry VM (Quay/Harbor/JFrog) - KVM guest provisioning
- Registry Installation - Container registry setup and configuration
- HAProxy Load Balancer - SNI routing and SSL termination
- SSL/TLS Certificates - Let's Encrypt or self-signed CA
- Infrastructure Verification - Health checks and validation

**Survey Options**:
- Registry Type: quay / harbor / jfrog
- Certificate Mode: letsencrypt / selfsigned

**Prerequisites**: 
- **Bootstrap Layer Complete** (VyOS, DNS, AAP deployed via manual playbooks)
- VyOS router accessible at 192.168.122.2
- DNS resolving (Route53 or FreeIPA)
- AAP 2.6 operational at https://aap.sandbox3377.opentlc.com

---

#### **Workflow 2: OpenShift Image Mirroring**
**Purpose**: Mirror OpenShift releases and operators to disconnected registry  
**Execution Model**: Sequential (3-step with validation)  
**Components**:
- Operator selection validation (ADR-0034)
- Image download to disk (oc-mirror mirrorToDisk)
- Image push to registry (oc-mirror diskToMirror)

**Survey Options**: Operator preset, Custom preset path, Target registry, Namespace

**Prerequisites**: **Workflow 1 must complete successfully** (verified via Step 0: infrastructure health check)

---

#### **Workflow 3: OpenShift Cluster Deployment** (Future - Deferred to v1.4+)
**Purpose**: Deploy OpenShift cluster using disconnected registry  
**Execution Model**: Sequential (multi-phase cluster deployment)  
**Components** (Planned):
- Generate install-config.yaml with imageContentSources
- Deploy bootstrap node
- Deploy control plane (masters)
- Deploy compute nodes (workers)
- Post-deployment cluster configuration
- Cluster verification

**Prerequisites**: **Workflows 1 and 2 must complete successfully**

**Status**: Deferred - requires 5+ new playbooks for cluster deployment orchestration

---

### Workflow Execution Order

```
┌────────────────────────────────────────┐
│ Workflow 1: Infrastructure Deployment  │
│ (Conditional: KVM/Existing/Cloud)      │
└───────────────┬────────────────────────┘
                │ ✅ Infrastructure Ready
                ▼
┌────────────────────────────────────────┐
│ Workflow 2: Image Mirroring            │
│ (Validates Workflow 1 prerequisites)   │
└───────────────┬────────────────────────┘
                │ ✅ Images Mirrored
                ▼
┌────────────────────────────────────────┐
│ Workflow 3: Cluster Deployment (Future)│
│ (Validates Workflows 1 & 2)            │
└────────────────────────────────────────┘
```

**Enforcement**: Each workflow includes prerequisite validation step that fails gracefully if dependencies not met.

---

### Bootstrap vs Workflow Layers

The deployment architecture is organized into two distinct layers:

#### **Bootstrap Layer** (Manual Playbook Execution - Prerequisites for AAP)

Components that MUST be deployed BEFORE AAP can function:

| Component | Rationale | Deployment Method |
|-----------|-----------|-------------------|
| **VyOS Router** | Network infrastructure required for AAP communication | `playbooks/deploy-vyos.yml` |
| **DNS Services** | Name resolution required for AAP Web UI and API | `playbooks/setup-route53-dns.yml` or `playbooks/setup-freeipa-dns.yml` |
| **AAP 2.6** | Automation platform itself (bootstrap paradox) | `playbooks/deploy-aap-multi-node.yml` |
| **Hypervisor** | KVM/libvirt or cloud infrastructure | One-time provisioning |

**Why Bootstrap Layer Exists**: Circular dependency prevention
- VyOS provides network routing for AAP communication
- DNS provides name resolution for `aap.sandbox3377.opentlc.com`
- AAP cannot deploy itself (bootstrap paradox)
- These must exist BEFORE workflows can run

**Deployment Order**:
```
1. Hypervisor Setup (IBM Cloud VSI or bare metal KVM)
2. VyOS Router (playbooks/deploy-vyos.yml)
3. DNS Services (playbooks/setup-route53-dns.yml)
4. AAP 2.6 (playbooks/deploy-aap-multi-node.yml)
--- AAP Workflows become available after this point ---
5. Workflow 1 (Infrastructure)
6. Workflow 2 (Image Mirroring)
7. Workflow 3 (Cluster Deployment - future)
```

---

#### **Workflow Layer** (AAP Workflow Orchestration)

Components managed via AAP workflows AFTER bootstrap layer is operational:

**Workflow 1 Components** (Infrastructure):
- **Registry VMs**: Quay, Harbor, JFrog (KVM guest provisioning)
- **Registry Installation**: Container registry setup and configuration
- **HAProxy Load Balancer**: SNI routing, SSL termination
- **Certificate Management**: Let's Encrypt or self-signed CA
- **Infrastructure Verification**: Health checks and validation

**Workflow 2 Components** (Mirroring):
- **oc-mirror Operations**: operator validation, download-to-disk, push-to-registry
- **Operator Catalog Mirroring**: Survey-driven preset selection (ADR-0034)
- **Release Channel Mirroring**: OpenShift version selection

**Workflow 3 Components** (Cluster - Future):
- **OpenShift Clusters**: node provisioning, cluster deployment
- **Storage Infrastructure**: NFS VMs, persistent storage
- **Monitoring Stack**: Prometheus, Grafana, Loki
- **Backup/Restore**: Infrastructure state backup and recovery

---

### Why This Separation Matters

**Bootstrap Layer**:
- Required for AAP to function
- Must be deployed manually (CLI playbooks)
- Cannot be managed by AAP (circular dependency)
- Deployed once per environment

**Workflow Layer**:
- Managed by AAP Web UI
- Visual progress tracking, RBAC, audit logs
- Survey-driven configuration
- Can be re-run, torn down, redeployed

**Anti-Pattern to Avoid**: Attempting to deploy VyOS or DNS via AAP workflows creates a "chicken and egg" problem - AAP needs these components to work, so AAP cannot deploy them.

### Workflow Design Principles

1. **Atomic Job Templates**: Each job template performs one well-defined task (provision VM, configure service, verify health)
2. **Two-Workflow Pattern**: Separate deployment and teardown workflows for each component (enables independent lifecycle management)
3. **Idempotent Operations**: All workflows safe to re-run without side effects
4. **Safety Gates**: Teardown workflows include dry-run mode and confirmation prompts by default
5. **Dependency Awareness**: Workflows check prerequisites before execution (fail fast if dependencies missing)
6. **Shared Templates**: Common tasks (VM provisioning, certificate setup) as reusable job templates
7. **Conditional Execution (NEW - v1.3)**: Workflows adapt to deployment scenario via survey-driven conditional nodes
8. **Multi-Environment Support (NEW - v1.3)**: Single workflow supports KVM, existing infrastructure, and cloud deployments
9. **Clear Sequencing (NEW - v1.3)**: Numbered workflows (1, 2, 3) indicate execution order and dependencies

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

### Cross-Workflow Concerns (v1.3)

Certain architectural concerns span multiple workflows and require coordination:

#### **Certificate Management**
- **Workflow 1**: Generates/deploys initial certificates (Let's Encrypt or self-signed)
- **Workflow 2**: Uses certificates for registry authentication
- **Workflow 3** (Future): Uses certificates for cluster API server
- **Shared Dependency**: All workflows assume certificates exist and are valid

#### **DNS Configuration**
- **Workflow 1**: Conditionally configures DNS (Route53 or FreeIPA)
- **Workflow 2**: Relies on DNS for registry resolution
- **Workflow 3** (Future): Requires DNS for cluster API and ingress
- **Shared Dependency**: DNS must be functional before Workflows 2 and 3

#### **Network Infrastructure**
- **Workflow 1**: Conditionally deploys VyOS router (KVM environments)
- **Workflow 2**: Assumes network connectivity to registry
- **Workflow 3** (Future): Requires VLAN segmentation and routing
- **Shared Dependency**: Network infrastructure must exist for all workflows

#### **Registry Access**
- **Workflow 1**: Deploys and configures container registry
- **Workflow 2**: Pushes images to registry
- **Workflow 3** (Future): Pulls images from registry during cluster deployment
- **Shared Dependency**: Registry must be accessible and authenticated

**Design Pattern**: Cross-workflow dependencies are validated via prerequisite check steps (Step 0) at the beginning of dependent workflows.

---

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
7. **Clear Execution Path (v1.3)**: Numbered workflows (1→2→3) eliminate confusion about deployment sequence
8. **Multi-Environment Flexibility (v1.3)**: Single Workflow 1 adapts to KVM, existing infrastructure, and cloud scenarios
9. **Progressive Deployment (v1.3)**: Users can deploy infrastructure only (Workflow 1) without mirroring or clusters

### Negative Consequences

1. **Increased AAP Resource Usage**: Controller CPU/memory increases with concurrent workflow executions
2. **Additional Maintenance Burden**: Must maintain both playbooks AND workflow configuration files
3. **Learning Curve**: Workflow designer requires different skillset than playbook authoring
4. **Dependency on AAP Availability**: Workflows unavailable if AAP Controller is down (fallback to manual playbooks)
5. **Multi-Workflow Complexity (v1.3)**: Users must understand 3-workflow catalog and execution order
6. **Conditional Logic Complexity (v1.3)**: Survey-driven conditional execution requires thorough testing across scenarios
7. **Documentation Burden (v1.3)**: Must document which workflow to use for different deployment scenarios

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

**Risk: Workflow Execution Out of Order (v1.3)**
- Users might run Workflow 2 before Workflow 1, causing failures
- **Mitigation**: Prerequisite check steps (Step 0) fail gracefully with clear error messages directing users to correct workflow.

**Risk: Conditional Execution Bugs (v1.3)**
- Survey-driven logic may have edge cases across KVM/Existing/Cloud scenarios
- **Mitigation**: Comprehensive testing matrix covering all 3 scenarios. Validation playbooks verify environment state before conditional steps.

**Risk: Documentation Drift (v1.3)**
- Workflow catalog documentation may become outdated as workflows evolve
- **Mitigation**: Single source of truth: `docs/AAP_WORKFLOW_CATALOG.md`. Reference from all other documentation.

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

### Release v1.2 (June 2026)
- ✅ Workflow 2: Image Mirroring (oc-mirror download/push with operator validation)
- ✅ Survey integration for operator preset selection
- ✅ Step numbering (Step 1, Step 2, Step 3)

### Release v1.3 (June 2026) - Multi-Workflow Architecture
- ✅ ADR-0032 updated with 3-workflow catalog
- 🔄 In Progress: Workflow 1 configuration (infrastructure deployment)
- 🔄 In Progress: Workflow 2 prerequisite check (verify Workflow 1 completed)
- 📋 Planned: Workflow catalog documentation (`AAP_WORKFLOW_CATALOG.md`)
- 📋 Planned: New playbooks (assess-deployment-environment.yml, verify-infrastructure-prerequisites.yml)

### Release v1.4+ (Future) - Cluster Deployment
- 📋 Workflow 3: OpenShift Cluster Deployment
  - Generate install-config.yaml with imageContentSources
  - Bootstrap node deployment
  - Control plane deployment
  - Worker node deployment
  - Cluster verification
- 📋 **Cluster upgrade workflow** (see **ADR 0006: Lifecycle Management Strategy**)
  - Pre-upgrade health checks
  - Image mirroring (oc-mirror incremental)
  - Cluster state backup
  - Approval gates for production
  - ICSP/IDMS updates
  - ClusterVersion upgrade execution
  - Post-upgrade verification

### Workflow Template Repository Structure (v1.3)

```
playbooks/aap-configuration/
├── configure-complete-aap-setup.yml           # Bootstrap AAP with all workflows
├── configure-infrastructure-workflow.yml      # Workflow 1: Infrastructure (v1.3 NEW)
├── configure-oc-mirror-workflow.yml           # Workflow 2: Image Mirroring (renamed in v1.3)
├── configure-cluster-deployment-workflow.yml  # Workflow 3: Cluster Deployment (future)
└── configure-cluster-upgrade-workflow.yml     # Cluster upgrades (future - see ADR 0006)

playbooks/
├── assess-deployment-environment.yml          # Workflow 1 Step 1 (v1.3 NEW)
├── verify-infrastructure-prerequisites.yml    # Workflow 2 Step 0 (v1.3 NEW)
├── verify-infrastructure-deployment.yml       # Workflow 1 Step 8 (v1.3 NEW)
└── (existing playbooks)
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
