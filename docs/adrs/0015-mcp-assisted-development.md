# ADR 0015: MCP-Assisted Development Workflow

**Status:** Accepted  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 3.2 - Objectives

## Context

Development and operations of ocp4-disconnected-helper can be enhanced through AI-assisted tooling. The qubinode_navigator project provides Model Context Protocol (MCP) servers that enable:
- Natural language interaction with infrastructure
- AI-powered documentation search
- Automated ADR generation and analysis
- Intelligent workflow orchestration

## Decision

Integrate with **qubinode_navigator's MCP servers** during development and operations to enable AI-assisted workflows.

### Available MCP Servers

| Server | Tools | Capabilities |
|--------|-------|--------------|
| **Airflow MCP** | 9 | DAG management, VM lifecycle, workflow orchestration |
| **AI Assistant MCP** | 3 | RAG documentation search, chat, context-aware help |
| **ADR Analysis MCP** | 55 | ADR generation, architectural analysis, deployment validation |

## Rationale

### Benefits of MCP Integration

1. **Faster development**: AI assists with code generation, troubleshooting
2. **Better documentation**: Automated ADR generation from PRD
3. **Intelligent operations**: Natural language DAG triggering
4. **Knowledge retention**: RAG-powered search across project docs
5. **Consistency**: AI validates architectural decisions against ADRs

### Use Cases

| Task | MCP Server | Example |
|------|------------|---------|
| Generate ADRs from PRD | ADR Analysis | `generate_adrs_from_prd` |
| Trigger deployment | Airflow MCP | "Start initial deployment for OCP 4.20" |
| Search documentation | AI Assistant | "How do I configure oc-mirror?" |
| Validate architecture | ADR Analysis | `review_existing_adrs` |
| Check deployment status | Airflow MCP | `list_dags`, `get_dag_status` |

## Consequences

### Positive
- **Accelerated development**: AI handles repetitive tasks
- **Improved quality**: Automated validation and consistency checks
- **Better onboarding**: AI assistant helps new contributors
- **Living documentation**: ADRs stay in sync with code

### Negative
- **MCP dependency**: Full AI features require MCP server setup
- **Learning curve**: Teams need to understand MCP interaction
- **Resource usage**: MCP servers consume additional resources

## Implementation

### Setup MCP Servers

```bash
# Via qubinode_navigator
cd /root/qubinode_navigator/airflow
./setup-mcp-servers.sh

# Verify MCP servers are running
curl http://localhost:8889/health  # Airflow MCP
curl http://localhost:8890/health  # AI Assistant MCP
```

### IDE Integration (Windsurf/Cursor)

MCP servers can be configured in IDE settings for inline assistance:

```json
// .windsurf/mcp.json or similar
{
  "servers": {
    "adr-analysis": {
      "command": "mcp-adr-analysis-server",
      "args": ["--project-path", "/root/ocp4-disconnected-helper"]
    },
    "airflow": {
      "url": "http://localhost:8889"
    }
  }
}
```

### Development Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                MCP-Assisted Development Flow                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Planning Phase                                              │
│     └── ADR Analysis MCP: generate_adrs_from_prd                │
│     └── ADR Analysis MCP: suggest_adrs                          │
│                                                                 │
│  2. Development Phase                                           │
│     └── AI Assistant MCP: Search docs, get examples             │
│     └── ADR Analysis MCP: validate_rules                        │
│                                                                 │
│  3. Testing Phase                                               │
│     └── Airflow MCP: Trigger test DAGs                          │
│     └── ADR Analysis MCP: compare_adr_progress                  │
│                                                                 │
│  4. Deployment Phase                                            │
│     └── Airflow MCP: Trigger deployment DAGs                    │
│     └── ADR Analysis MCP: deployment_readiness                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Key MCP Tools for ocp4-disconnected-helper

| Tool | Purpose |
|------|---------|
| `generate_adrs_from_prd` | Create ADRs from PRD.md |
| `analyze_project_ecosystem` | Understand project architecture |
| `compare_adr_progress` | Validate implementation vs ADRs |
| `deployment_readiness` | Check if ready to deploy |
| `get_workflow_guidance` | Get recommended next steps |
| `suggest_adrs` | Identify missing architectural decisions |

### Context File

The `.mcp-server-context.md` file provides instant context to LLMs:

```bash
# Reference in conversations
@.mcp-server-context.md What ADRs have we created?
@.mcp-server-context.md What's the current project score?
```

## Graceful Degradation

MCP integration is **optional**. Without MCP servers:
- Manual ADR creation still works
- Playbooks run directly via ansible-playbook
- Documentation is still accessible in markdown files
- Airflow UI provides workflow management

See ADR 0013 (Flexible Execution Model) for non-MCP workflows.

## Related ADRs
- ADR 0011: qubinode_navigator Integration
- ADR 0012: Airflow DAG Orchestration Strategy
- ADR 0013: Flexible Execution Model
- ADR 0014: Airflow Replaces kcli-pipelines
