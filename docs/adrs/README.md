# Architectural Decision Records (ADRs)

This directory contains the Architectural Decision Records for the **ocp4-disconnected-helper** project.

## What are ADRs?

ADRs document significant architectural decisions made during the project's development. Each ADR describes:
- The context and problem being addressed
- The decision made
- The consequences (positive and negative)
- Implementation guidance

## ADR Index

| ADR | Title | Status | PRD Section |
|-----|-------|--------|-------------|
| [0001](0001-three-tier-architecture.md) | Two-Tier Architecture Stack | Accepted (Revised) | §2 |
| [0002](0002-ansible-automation-framework.md) | Ansible as Automation Framework | Accepted | §5.1, §6.1 |
| [0003](0003-oc-mirror-image-mirroring.md) | oc-mirror v2 for Image Mirroring | Accepted | §6.3 |
| [0004](0004-dual-registry-support.md) | Dual Registry Support (Harbor/JFrog) | Accepted | §5.2 |
| [0005](0005-openshift-appliance-builder.md) | OpenShift Appliance Builder Integration | Proposed | §5.1 |
| [0006](0006-lifecycle-management-strategy.md) | Lifecycle Management Strategy | Proposed | §4, §6 |
| [0007](0007-compact-cluster-architecture.md) | 3-Node Compact Cluster Architecture | Accepted | §5.3 |
| [0008](0008-github-actions-automation.md) | GitHub Actions for CI/CD | Proposed | §3.2 |
| [0009](0009-secret-management.md) | Secret Management Strategy | Proposed | §7.2 |
| [0010](0010-centos-stream-10-target.md) | CentOS Stream 10 as Target Platform | Accepted | §7.1 |
| [0011](0011-qubinode-navigator-integration.md) | qubinode_navigator Integration | Proposed | §2 |
| [0012](0012-airflow-dag-orchestration.md) | Airflow DAG Orchestration Strategy | Proposed | §3.2 |
| [0013](0013-flexible-execution-model.md) | Flexible Execution Model | Accepted | §3.2 |
| [0014](0014-airflow-replaces-kcli-pipelines.md) | Airflow Replaces kcli-pipelines | Accepted | §2 |
| [0015](0015-mcp-assisted-development.md) | MCP-Assisted Development Workflow | Accepted | §3.2 |

## Status Definitions

| Status | Description |
|--------|-------------|
| **Proposed** | Under discussion, not yet implemented |
| **Accepted** | Approved and ready for implementation |
| **Deprecated** | No longer recommended, superseded |
| **Superseded** | Replaced by another ADR |

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Three-Tier Stack (ADR 0001)                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              kcli-pipelines (Orchestration)              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│         ┌────────────────────┼────────────────────┐            │
│         ▼                    ▼                    ▼            │
│  ┌─────────────┐    ┌─────────────────┐    ┌──────────────┐   │
│  │ qubinode_   │    │ ocp4-disconnected│    │  OpenShift   │   │
│  │ navigator   │    │     -helper      │    │   Cluster    │   │
│  │ (Infra)     │    │  (Automation)    │    │  (Target)    │   │
│  └─────────────┘    └─────────────────┘    └──────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Key Decisions by Category

### Infrastructure
- **ADR 0001**: Three-tier architecture with qubinode_navigator, kcli-pipelines, ocp4-disconnected-helper
- **ADR 0010**: CentOS Stream 10 as target platform

### Automation
- **ADR 0002**: Ansible playbooks for all automation
- **ADR 0008**: GitHub Actions for CI/CD

### OpenShift Deployment
- **ADR 0003**: oc-mirror v2 for image mirroring
- **ADR 0004**: Support for Harbor and JFrog registries
- **ADR 0005**: OpenShift Appliance Builder for disconnected installs
- **ADR 0007**: 3-node compact cluster as default architecture

### Operations
- **ADR 0006**: Lifecycle management with incremental updates
- **ADR 0009**: Tiered secret management (Vault + Ansible Vault)

## Related Projects

| Project | Role | Repository |
|---------|------|------------|
| qubinode_navigator | Infrastructure Layer | [Qubinode/qubinode_navigator](https://github.com/Qubinode/qubinode_navigator) |
| kcli-pipelines | Orchestration Layer | [tosin2013/kcli-pipelines](https://github.com/tosin2013/kcli-pipelines) |
| openshift-agent-install | Agent-based Install | [tosin2013/openshift-agent-install](https://github.com/tosin2013/openshift-agent-install) |
| appliance | OpenShift Appliance | [openshift/appliance](https://github.com/openshift/appliance) |

## Creating New ADRs

Use the following template for new ADRs:

```markdown
# ADR NNNN: Title

**Status:** Proposed | Accepted | Deprecated | Superseded  
**Date:** YYYY-MM-DD  
**Deciders:** Team/Person  
**PRD Reference:** Section X.X

## Context
[Describe the problem and why a decision is needed]

## Decision
[Describe the decision made]

## Consequences
### Positive
- [Benefit 1]

### Negative
- [Drawback 1]

## Implementation
[Implementation details, code examples]

## Related ADRs
- ADR XXXX: Related Decision
```

## PRD Traceability

All ADRs trace back to the [Product Requirements Document](../../PRD.md):
- **Section 2**: Three-tier stack definition
- **Section 4**: Operational model (initial vs incremental)
- **Section 5**: Initial deployment requirements
- **Section 6**: Post-deployment lifecycle management
- **Section 7**: Technical requirements and dependencies
