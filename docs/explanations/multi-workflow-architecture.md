# Understanding Multi-Workflow Architecture

Why this project uses multiple AAP workflows instead of one monolithic workflow, and the design trade-offs involved.

---

## The Problem: Workflow Granularity

**Question**: "Why split infrastructure deployment into multiple workflows? Why not one workflow that does everything?"

**Answer**: **Separation of concerns** + **Prerequisite validation** + **Failure isolation** = Better operational safety.

---

## Design Evolution

### v0.x: All Manual Playbooks (No Orchestration)

**Structure**:
```bash
# User runs playbooks manually in correct order
ansible-playbook playbooks/deploy-vyos.yml
ansible-playbook playbooks/deploy-registry.yml
ansible-playbook playbooks/download-images.yml
ansible-playbook playbooks/push-images.yml
```

**Problems**:
- ❌ No execution order enforcement
- ❌ No prerequisite validation
- ❌ User can run playbooks in wrong order
- ❌ No centralized orchestration or visibility

**Example failure**:
```bash
# User runs playbooks out of order
ansible-playbook playbooks/download-images.yml  # Fails: no registry!
ansible-playbook playbooks/deploy-registry.yml   # Too late
```

---

### v1.0: Single Monolithic Workflow (First Attempt)

**Structure**:
```
Workflow 1: Deploy Everything
├─ Node 1: Deploy VyOS
├─ Node 2: Deploy Registry
├─ Node 3: Download Images
├─ Node 4: Push Images
├─ Node 5: Deploy HAProxy
├─ Node 6: Setup Certificates
└─ Node 7: Verify Deployment
```

**Problems**:
- ❌ **Bootstrap paradox**: AAP cannot deploy VyOS (its own network prerequisite)
- ❌ **Tight coupling**: Registry failure blocks image mirroring
- ❌ **Long execution time**: 30-60 minutes for full run
- ❌ **Difficult retries**: Must re-run entire workflow after fixing one step
- ❌ **No reusability**: Cannot mirror different operator sets without duplicating workflow

**Example failure**:
```
Node 1 (VyOS) fails → Entire workflow stuck
Can't proceed to registry deployment even though VyOS is independent
```

---

### v1.2: Two-Workflow Architecture (Current)

**Structure**:
```
Bootstrap Layer (Manual):
├─ VyOS Router
├─ DNS Services
└─ AAP 2.6

Workflow 1: Registry Infrastructure
├─ Node 1: Deploy Registry VM
├─ Node 2: Setup Registry (Quay/Harbor/JFrog)
├─ Node 3: Configure HAProxy
├─ Node 4: Setup Certificates
└─ Node 5: Verify Infrastructure

Workflow 2: Image Mirroring
├─ Node 0: Verify Prerequisites (checks Workflow 1 complete)
├─ Node 1: Download Images
├─ Node 2: Push to Registry
└─ Node 3: Verify Mirror
```

**Advantages**:
- ✅ **Bootstrap paradox solved**: Manual deployment for AAP prerequisites
- ✅ **Prerequisite validation**: Workflow 2 checks Workflow 1 completion
- ✅ **Failure isolation**: Registry failure doesn't block retry of image mirroring
- ✅ **Reusability**: Run Workflow 2 multiple times with different operator presets
- ✅ **Faster iteration**: Re-run only failed workflow, not entire stack

---

## Multi-Workflow Design Principles

### Principle 1: One Workflow Per Lifecycle Phase

**Guideline**: Each workflow represents a distinct infrastructure lifecycle phase.

**Workflow 1** (Registry Infrastructure):
- **Purpose**: Deploy container registry and load balancing
- **Lifecycle**: Infrastructure provisioning
- **Run frequency**: Once per environment
- **Idempotence**: Yes (re-running doesn't create duplicates)

**Workflow 2** (Image Mirroring):
- **Purpose**: Mirror OpenShift images to registry
- **Lifecycle**: Content synchronization
- **Run frequency**: Multiple times (different operator sets, OCP versions)
- **Idempotence**: Yes (only mirrors new/changed images)

### Principle 2: Strict Prerequisite Dependencies

**Rule**: Downstream workflows MUST validate upstream workflow completion.

**Implementation**:
```yaml
# Workflow 2 - Node 0: Verify Prerequisites
tasks:
  - name: Check registry is accessible
    uri:
      url: "https://{{ target_registry }}/health/instance"
      validate_certs: no
    register: registry_health
    failed_when: registry_health.status != 200

  - name: Fail if registry not ready
    fail:
      msg: "Registry not accessible. Run Workflow 1 first."
    when: registry_health.status != 200
```

**Why**: Prevents cascading failures when infrastructure not ready.

### Principle 3: Survey-Driven Configuration

**Guideline**: Workflow behavior controlled by user-provided survey parameters, not hardcoded values.

**Workflow 1 Survey**:
1. `registry_type`: quay | harbor | jfrog
2. `certificate_mode`: letsencrypt | selfsigned

**Workflow 2 Survey**:
1. `operator_preset_file`: storage-operators | networking-operators | ...
2. `target_registry`: registry.example.com:8443

**Why**: Same workflow supports multiple configurations without duplication.

### Principle 4: Failure Isolation

**Guideline**: Workflow failures should be isolated, not cascading.

**Example scenario**:
```
Workflow 1 succeeds → Registry deployed
Workflow 2 fails → oc-mirror timeout

User fixes: Increase oc-mirror timeout
User re-runs: Workflow 2 only (NOT Workflow 1+2)
```

**Why**: Faster recovery, lower risk of breaking working infrastructure.

---

## Trade-offs and Alternatives Considered

### Alternative 1: Single Workflow with Tags

**Approach**: One workflow with Ansible tags to control execution

```yaml
# Single workflow with tags
- hosts: all
  tasks:
    - name: Deploy VyOS
      tags: [vyos, bootstrap]
    
    - name: Deploy Registry
      tags: [registry, infrastructure]
    
    - name: Mirror Images
      tags: [images, mirroring]
```

**Execution**:
```bash
ansible-playbook site.yml --tags infrastructure
ansible-playbook site.yml --tags mirroring
```

**Why rejected**:
- ❌ **No AAP survey support**: Tags are CLI-only, not exposed in AAP Web UI
- ❌ **No prerequisite validation**: Tags skip tasks, don't validate dependencies
- ❌ **Poor visibility**: Can't see workflow structure in AAP UI
- ❌ **Difficult troubleshooting**: Single job output mixes all phases

### Alternative 2: Three Workflows (Infrastructure + Download + Push)

**Approach**: Split Workflow 2 into separate Download and Push workflows

```
Workflow 1: Registry Infrastructure (unchanged)
Workflow 2: Download Images
Workflow 3: Push to Registry
```

**Why rejected**:
- ❌ **Over-segmentation**: Download and Push are tightly coupled (same operator preset)
- ❌ **No independent value**: Download without Push is incomplete
- ❌ **Extra overhead**: More workflows to maintain, configure, document

### Alternative 3: Conditional Workflow (Dynamic Branching)

**Approach**: Single workflow with conditional branching based on survey

```
Workflow 1
├─ If registry_type == quay → Setup Quay
├─ If registry_type == harbor → Setup Harbor
└─ If registry_type == jfrog → Setup JFrog
```

**Why rejected**:
- ❌ **Complex workflow structure**: Many conditional branches hard to visualize
- ❌ **Difficult testing**: Must test all branches for every change
- ❌ **Poor troubleshooting**: Complex execution path hard to debug

---

## Current Architecture Justification

### Why Two Workflows (Not One)

**Separation of concerns**:
- Workflow 1: Infrastructure (deploy once)
- Workflow 2: Content (run multiple times)

**Reusability**:
- Run Workflow 2 with different operator presets
- Run Workflow 2 for different OCP versions
- No need to re-deploy infrastructure

**Operational clarity**:
- Infrastructure failures vs content failures isolated
- Clear execution order: Infrastructure → Content
- Easier troubleshooting: Smaller scope per workflow

### Why Two Workflows (Not Three+)

**Avoid over-segmentation**:
- Download + Push are tightly coupled (same TAR archives)
- No value in running Download without Push
- Single workflow unit easier to maintain

**Balanced granularity**:
- Fine enough for failure isolation
- Coarse enough to avoid orchestration overhead
- Right level of abstraction for operators

---

## Workflow Extension Strategy

### Future: Workflow 3 (Cluster Deployment)

**Planned addition**:
```
Workflow 3: OpenShift Cluster Deployment
├─ Node 0: Verify Prerequisites (Workflow 1+2 complete)
├─ Node 1: Generate Ignition Configs
├─ Node 2: Deploy Bootstrap Node
├─ Node 3: Deploy Master Nodes
├─ Node 4: Deploy Worker Nodes
└─ Node 5: Verify Cluster Health
```

**Why separate workflow**:
- ✅ Different lifecycle phase (cluster vs infrastructure)
- ✅ Depends on both Workflow 1 and Workflow 2
- ✅ May be run multiple times (dev, staging, prod clusters)
- ✅ Failure isolation from infrastructure workflows

### Not Planned: Workflow 4 (Operator Installation)

**Why not**:
- ❌ Operator installation happens post-cluster deployment
- ❌ Better handled by GitOps (ArgoCD, FluxCD)
- ❌ Not infrastructure-level workflow
- ❌ Too application-specific

---

## Workflow Relationships

### Dependency Graph

```
Bootstrap Layer (Manual)
  ├─ VyOS Router
  ├─ DNS Services
  └─ AAP 2.6
      ↓
Workflow 1: Registry Infrastructure
      ↓
Workflow 2: Image Mirroring
      ↓
Workflow 3: Cluster Deployment (planned)
```

**Dependencies**:
- Workflow 1 depends on Bootstrap Layer
- Workflow 2 depends on Workflow 1
- Workflow 3 depends on Workflow 1 + Workflow 2

**Execution order**: Top to bottom (prerequisites before dependents)

### Prerequisite Validation Strategy

**Node 0 pattern**: Every workflow after Workflow 1 starts with prerequisite validation node.

**Workflow 2 - Node 0 example**:
```yaml
- name: Verify Prerequisites
  tasks:
    - name: Check Workflow 1 completion
      # Query AAP API for latest Workflow 1 job
      uri:
        url: "{{ controller_host }}/api/controller/v2/workflow_jobs/?name__contains=Registry Infrastructure&status=successful&order_by=-id"
      register: workflow1_status
    
    - name: Fail if Workflow 1 not complete
      fail:
        msg: "Workflow 1 (Registry Infrastructure) must complete successfully before Workflow 2"
      when: workflow1_status.json.count == 0
```

**Why**: Explicit validation prevents cryptic failures downstream.

---

## Operational Patterns

### Pattern 1: Infrastructure-Once, Content-Many

**Workflow 1**: Run once per environment
**Workflow 2**: Run multiple times with different parameters

**Example usage**:
```bash
# Day 1: Deploy infrastructure
Run Workflow 1 (registry_type=quay, certificate_mode=letsencrypt)

# Day 2: Mirror storage operators
Run Workflow 2 (operator_preset=storage-operators)

# Day 3: Mirror networking operators (same infrastructure)
Run Workflow 2 (operator_preset=networking-operators)

# Day 4: Mirror AI operators (same infrastructure)
Run Workflow 2 (operator_preset=openshift-ai-operators)
```

### Pattern 2: Incremental Rollout

**Approach**: Deploy infrastructure to dev, test workflows, then deploy to staging/prod

```bash
# Dev environment
Run Workflow 1 (dev-registry.example.com)
Run Workflow 2 (operator_preset=storage-operators) → Test

# Staging environment (after dev validation)
Run Workflow 1 (staging-registry.example.com)
Run Workflow 2 (operator_preset=storage-operators) → Verify

# Production environment (after staging validation)
Run Workflow 1 (prod-registry.example.com)
Run Workflow 2 (operator_preset=storage-operators) → Deploy
```

### Pattern 3: Disaster Recovery

**Scenario**: Registry VM crashes, data lost

**Recovery with multi-workflow**:
```bash
# Step 1: Re-run Workflow 1 (re-deploy registry infrastructure)
Run Workflow 1 (same parameters as before)

# Step 2: Re-run Workflow 2 (re-mirror images from TAR archives)
Run Workflow 2 (operator_preset=storage-operators)
Run Workflow 2 (operator_preset=networking-operators)
```

**Why multi-workflow helps**: Infrastructure and content recovery are separate steps, clear recovery path.

---

## Performance Considerations

### Workflow Execution Time

| Workflow | Average Time | Variability |
|----------|--------------|-------------|
| Workflow 1 | 15-20 minutes | Low (infrastructure provisioning) |
| Workflow 2 | 10-60 minutes | High (depends on operator count) |

**Why variability matters**: Separate workflows mean Workflow 2 time doesn't impact Workflow 1 retry speed.

### Concurrency

**Current**: Workflows run sequentially (prerequisite dependencies)

**Future**: Workflow 2 could run in parallel for different registries:
```bash
# Concurrent mirroring to dev and staging registries
Run Workflow 2 (target_registry=dev-registry.example.com) &
Run Workflow 2 (target_registry=staging-registry.example.com) &
wait
```

**Limitation**: Shared TAR archives on hypervisor (disk I/O bottleneck)

---

## Related Decisions

- [ADR-0032: AAP Workflow Orchestration Strategy](../adrs/adr-0032-aap-workflow-orchestration-strategy.md)
- [ADR-0021: Deprecate Airflow and Adopt AAP](../adrs/0021-deprecate-airflow-adopt-aap.md)
- [Bootstrap vs Workflow Layers](bootstrap-vs-workflow-layers.md)
- [AAP Workflow Catalog](../AAP_WORKFLOW_CATALOG.md)

---

## Summary

**Multi-workflow architecture** provides:
1. **Separation of concerns** (infrastructure vs content)
2. **Prerequisite validation** (explicit dependency checking)
3. **Failure isolation** (retry only failed workflow)
4. **Reusability** (run Workflow 2 multiple times)
5. **Operational clarity** (clear execution order and dependencies)

**Key insight**: Not too few (monolithic), not too many (over-segmented), just right (balanced granularity).
