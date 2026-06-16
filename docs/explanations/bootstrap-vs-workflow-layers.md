# Understanding Bootstrap vs Workflow Layers

Why some infrastructure must be deployed manually before AAP workflows can work.

---

## The Bootstrap Paradox

**Question**: "Why can't AAP workflows deploy VyOS and DNS if workflows are supposed to automate everything?"

**Answer**: **AAP cannot deploy its own prerequisites.** This is a circular dependency - AAP needs network routing and DNS to function, so these must exist *before* AAP exists.

This is known as the **bootstrap paradox**: The automation platform cannot automate its own creation.

---

## Two-Layer Architecture

This project separates infrastructure into two layers:

### Layer 1: Bootstrap (Manual Playbooks)

**Definition**: Infrastructure that AAP depends on to work.

**Components**:
1. **VyOS Router** - Network routing for AAP communication
2. **DNS Services** - Name resolution for `aap.sandbox3377.opentlc.com`
3. **AAP 2.6** - Automation platform itself

**Why Manual**: These components must exist *before* AAP can execute workflows. Trying to deploy them via AAP workflows creates a chicken-and-egg problem.

**Deployment Method**: Direct Ansible playbook execution via CLI:
```bash
ansible-playbook playbooks/deploy-vyos.yml
ansible-playbook playbooks/setup-route53-dns.yml
ansible-playbook playbooks/deploy-aap-multi-node.yml
```

---

### Layer 2: Workflow (AAP Orchestration)

**Definition**: Infrastructure that AAP orchestrates after it exists.

**Components**:
1. **Registry Infrastructure** (Workflow 1) - Container registry, HAProxy, certificates
2. **Image Mirroring** (Workflow 2) - OpenShift release and operator images
3. **Cluster Deployment** (Workflow 3, planned) - OpenShift cluster nodes

**Why AAP**: These components don't affect AAP's ability to function. Once AAP exists, it can orchestrate their deployment.

**Deployment Method**: AAP Web UI or API:
```bash
# Via Web UI: Templates → Workflows → Launch
# Via API: curl -X POST .../workflow_job_templates/$ID/launch/
```

---

## Why This Separation Matters

### 1. Prevents Circular Dependencies

**Bad** (circular dependency):
```
VyOS needed for network → AAP needs network → AAP deploys VyOS → ❌ DEADLOCK
```

**Good** (layered approach):
```
VyOS deployed manually → AAP has network → AAP deploys registry → ✅ WORKS
```

### 2. Operational Clarity

**Bootstrap layer** failures affect *all* automation:
- VyOS down = no VM network connectivity
- DNS down = AAP Web UI unreachable
- AAP down = no workflow execution

**Workflow layer** failures are isolated:
- Registry down = can't mirror images, but AAP still works
- Mirroring failure = can retry workflow, doesn't affect other infrastructure

### 3. Disaster Recovery

**Bootstrap layer** is **single-instance, stateful**:
- One VyOS router (not clustered)
- One AAP deployment (multi-node, but single logical unit)
- Recovery requires manual playbook execution

**Workflow layer** is **recreatable via workflows**:
- Registry destroyed? Re-run Workflow 1
- Images lost? Re-run Workflow 2
- Cluster failed? Re-run Workflow 3 (planned)

---

## Historical Context: Why Not Just Use AAP for Everything?

### Early Design (v0.x): All Manual Playbooks

**Problem**: No orchestration, no execution order enforcement, no validation gates.

Users ran playbooks in wrong order:
```bash
# ❌ Wrong order
ansible-playbook playbooks/mirror-images.yml  # Fails: no registry!
ansible-playbook playbooks/deploy-registry.yml  # Too late
```

### First Attempt (v1.0): Everything in Workflows

**Problem**: Tried to deploy VyOS via AAP workflows.

**Failure Mode**:
1. AAP tries to deploy VyOS via workflow
2. VyOS deployment playbook needs network access to VM
3. AAP can't reach VyOS because... VyOS isn't deployed yet
4. Workflow hangs or fails cryptically

**User Feedback** (June 16, 2026):
> "we need to remember we do not need to deploy-vyos.yml because the deployment of aap depends on it so we would be chasing a chicken"

### Current Design (v1.3): Bootstrap + Workflow Layers

**Solution**: Explicit separation documented in [ADR-0032](../adrs/adr-0032-aap-workflow-orchestration-strategy.md).

**Benefits**:
- ✅ Clear deployment order (bootstrap → workflows)
- ✅ No circular dependencies
- ✅ AAP workflows enforce correct execution order *within* workflow layer
- ✅ Users can't accidentally run Workflow 2 before Workflow 1 (prerequisite validation)

---

## Architectural Decision Trade-offs

### Trade-off 1: Consistency vs Flexibility

**Sacrifice**: Not everything is deployed the same way (manual vs AAP).

**Gain**: System actually works. Circular dependencies prevented.

### Trade-off 2: User Convenience vs Operational Safety

**Sacrifice**: User must run 3 manual playbooks before AAP workflows available.

**Gain**: Bootstrap infrastructure is stable. AAP can't accidentally delete its own network.

### Trade-off 3: Documentation Complexity vs Runtime Clarity

**Sacrifice**: Docs must explain two deployment methods (bootstrap + workflow).

**Gain**: Users understand *why* they can't deploy VyOS via AAP. Failure modes are obvious.

---

## When to Add Components to Each Layer

### Add to Bootstrap Layer If:
- ✅ AAP depends on it to function (network, DNS, AAP itself)
- ✅ It's a singleton (one instance, not clustered)
- ✅ Failure would prevent AAP Web UI access

### Add to Workflow Layer If:
- ✅ AAP doesn't need it to work
- ✅ It's recreatable via workflow re-execution
- ✅ Failure is isolated (doesn't affect AAP or other workflows)

### Example: Where Does HAProxy Belong?

**Question**: HAProxy provides load balancing. Is it bootstrap or workflow?

**Analysis**:
- Does AAP need HAProxy to function? **No** (AAP works without it)
- Is HAProxy recreatable via workflow? **Yes** (Workflow 1 Step 3)
- Does HAProxy failure prevent AAP access? **No** (only affects registry routing)

**Answer**: **Workflow layer** (Workflow 1).

---

## Common Misconceptions

### Misconception 1: "Workflows should automate everything"

**Reality**: Workflows automate everything *that doesn't create circular dependencies*.

AAP can't automate its own prerequisites without deadlocking.

### Misconception 2: "Bootstrap is a limitation we'll fix later"

**Reality**: Bootstrap layer is a *design constraint*, not a technical limitation.

No amount of engineering can eliminate the chicken-and-egg problem. Bootstrap layer will always exist.

### Misconception 3: "Just deploy AAP in the cloud to avoid bootstrap"

**Reality**: Cloud AAP still needs:
- Cloud networking (VPC, subnets) - cloud equivalent of VyOS
- Cloud DNS (Route53, Cloud DNS) - same DNS requirement
- Cloud compute (EC2, GCE) - AAP host

Bootstrap layer exists *everywhere*, just with different tools (cloud console, Terraform, etc.).

---

## Related Decisions

- [ADR-0032: Multi-Workflow Architecture](../adrs/adr-0032-aap-workflow-orchestration-strategy.md) - Formal architectural decision
- [ADR-0021: Deprecate Airflow and Adopt AAP](../adrs/0021-deprecate-airflow-adopt-aap.md) - Why AAP, not Airflow
- [ADR-0025: VyOS Router Network Infrastructure](../adrs/0025-vyos-router-network-infrastructure.md) - Why VyOS is a prerequisite

---

## Summary

**Bootstrap layer** = Manual playbooks for AAP's prerequisites (VyOS, DNS, AAP itself)

**Workflow layer** = AAP orchestration for everything else (registry, images, clusters)

**Why separate?** Prevents circular dependencies. AAP can't deploy its own network/DNS.

**Key insight**: Not everything *should* be automated the same way. Bootstrap is manual *by design*, not by accident.
