# ADR 0014: Airflow Replaces kcli-pipelines for Orchestration

**Status:** Accepted  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**Supersedes:** PRD Section 2 reference to kcli-pipelines

## Context

The original PRD (Section 2) defined a three-tier architecture:
1. **qubinode_navigator** - Infrastructure layer
2. **kcli-pipelines** - Orchestration layer
3. **ocp4-disconnected-helper** - Automation layer

However, qubinode_navigator now includes **Apache Airflow** with MCP server integration, providing superior orchestration capabilities compared to kcli-pipelines.

## Decision

**Replace kcli-pipelines with Airflow** as the orchestration layer.

### Revised Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Two-Tier Architecture                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │           qubinode_navigator                             │   │
│  │  ┌─────────────────┐  ┌─────────────────────────────┐   │   │
│  │  │  Infrastructure │  │  Airflow (Orchestration)    │   │   │
│  │  │  - OS plugins   │  │  - DAGs for workflows       │   │   │
│  │  │  - Vault        │  │  - MCP server integration   │   │   │
│  │  │  - Dependencies │  │  - Scheduling & monitoring  │   │   │
│  │  └─────────────────┘  └─────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│                              ▼                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │              ocp4-disconnected-helper                    │   │
│  │  - Ansible playbooks (automation)                        │   │
│  │  - Airflow DAGs (workflow definitions)                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Rationale

### Airflow vs kcli-pipelines

| Capability | kcli-pipelines | Airflow |
|------------|----------------|---------|
| Web UI | Limited | Full dashboard |
| Scheduling | Basic cron | Rich scheduling with catchup |
| Monitoring | Manual | Built-in task monitoring |
| Retry logic | Manual scripting | Native retry policies |
| Dependencies | Shell scripts | DAG dependency management |
| MCP integration | None | 9 tools via MCP server |
| AI assistance | None | AI Assistant integration |
| Audit trail | Git commits | Execution history + logs |
| Parallelism | Limited | Native parallel execution |

### Why Remove kcli-pipelines?

1. **Redundancy**: Airflow provides all kcli-pipelines capabilities and more
2. **Simplification**: One less component to maintain
3. **Integration**: Airflow is already part of qubinode_navigator
4. **AI-powered**: MCP server enables natural language workflow management
5. **Visibility**: Better monitoring and troubleshooting

### What kcli-pipelines Did

kcli-pipelines was primarily used for:
- Sequencing playbook execution → **Airflow DAGs do this better**
- Triggering workflows → **Airflow UI/CLI/MCP do this**
- CI/CD integration → **GitHub Actions + Airflow handle this**

## Consequences

### Positive
- **Simplified stack**: Two tiers instead of three
- **Better tooling**: Airflow's mature ecosystem
- **AI integration**: MCP server for intelligent orchestration
- **Single orchestration layer**: No confusion between kcli-pipelines and Airflow

### Negative
- **PRD deviation**: Original PRD mentioned kcli-pipelines
- **Migration**: Any existing kcli-pipelines workflows need conversion to DAGs

## Implementation

### Update ADR 0001 (Three-Tier → Two-Tier)

The architecture is now:
1. **qubinode_navigator** - Infrastructure + Orchestration (Airflow)
2. **ocp4-disconnected-helper** - Automation (Playbooks + DAG definitions)

### DAG Location

DAGs can live in either location:
```
# Option A: In ocp4-disconnected-helper (recommended)
ocp4-disconnected-helper/airflow/dags/

# Option B: Symlinked to qubinode_navigator
/root/qubinode_navigator/airflow/dags/ocp4-helper/ → /root/ocp4-disconnected-helper/airflow/dags/
```

### Workflow Mapping

| kcli-pipelines Workflow | Airflow DAG |
|------------------------|-------------|
| initial-deploy pipeline | `ocp_initial_deployment` |
| update-cluster pipeline | `ocp_incremental_update` |
| setup-registry pipeline | `ocp_registry_setup` |

## Related ADRs
- ADR 0001: Three-Tier Architecture (updated to two-tier)
- ADR 0011: qubinode_navigator Integration
- ADR 0012: Airflow DAG Orchestration Strategy
- ADR 0013: Flexible Execution Model
