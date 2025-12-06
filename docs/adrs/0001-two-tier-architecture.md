# ADR 0001: Two-Tier Architecture Stack

**Status:** Accepted (Revised)  
**Date:** 2025-11-25  
**Revised:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 2 - The Full Stack (revised per ADR 0014)

## Context

The ocp4-disconnected-helper project needs to operate within a larger ecosystem for deploying and managing OpenShift clusters in disconnected environments. The solution requires clear separation of concerns between infrastructure/orchestration and automation workloads.

Originally, the PRD proposed a three-tier stack with kcli-pipelines as the orchestration layer. However, qubinode_navigator now includes Apache Airflow with MCP server integration, making kcli-pipelines redundant. See ADR 0014 for the full rationale.

## Decision

Adopt a **two-tier architecture stack**:

1. **qubinode_navigator** - Infrastructure + Orchestration Layer
   - Prepares CentOS Stream 10 servers
   - Installs dependencies
   - Configures the base environment
   - **Airflow** for workflow orchestration
   - **MCP servers** for AI-assisted operations

2. **ocp4-disconnected-helper** - Automation Layer
   - Contains Ansible playbooks for heavy lifting
   - Performs content mirroring
   - Builds appliances
   - Executes cluster updates
   - Provides Airflow DAG definitions

## Consequences

### Positive
- **Simplified stack**: Two components instead of three
- **Better orchestration**: Airflow provides superior workflow management
- **AI integration**: MCP servers enable intelligent automation
- **Single source**: qubinode_navigator handles both infra and orchestration
- **Flexibility**: Can run with or without Airflow (see ADR 0013)

### Negative
- **PRD deviation**: Original PRD mentioned kcli-pipelines (now superseded)
- **Airflow dependency**: Full orchestration requires Airflow setup

## Implementation

```
┌─────────────────────────────────────────────────────────────┐
│                  qubinode_navigator                          │
│         (Infrastructure + Orchestration)                     │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐    ┌────────────────────────────┐     │
│  │  Infrastructure  │    │   Airflow Orchestration    │     │
│  │  - OS plugins    │    │   - DAG management         │     │
│  │  - Vault         │    │   - MCP server (9 tools)   │     │
│  │  - Dependencies  │    │   - Scheduling/monitoring  │     │
│  └──────────────────┘    └────────────────────────────┘     │
│                              │                               │
│                              ▼                               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │            ocp4-disconnected-helper                  │    │
│  │  - Ansible playbooks (download, push, build, update) │    │
│  │  - Airflow DAGs (workflow definitions)               │    │
│  │  - Can run standalone without Airflow                │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Related ADRs
- ADR 0002: Ansible as Automation Framework
- ADR 0003: oc-mirror for Image Mirroring
- ADR 0011: qubinode_navigator Integration
- ADR 0012: Airflow DAG Orchestration Strategy
- ADR 0013: Flexible Execution Model
- ADR 0014: Airflow Replaces kcli-pipelines
