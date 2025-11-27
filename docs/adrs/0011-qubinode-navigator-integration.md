# ADR 0011: qubinode_navigator Integration

**Status:** Proposed  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 2 - The Full Stack

## Context

The ocp4-disconnected-helper project operates as part of a three-tier stack where **qubinode_navigator** serves as the infrastructure layer. Integration between these projects enables:
- Automated host provisioning before running disconnected helper playbooks
- Consistent CentOS Stream 10 / RHEL 10 deployments
- AI-powered assistance via MCP servers
- Unified secret management via HashiCorp Vault

## Decision

Integrate with **qubinode_navigator** as the infrastructure provisioning layer using:

1. **Plugin Framework**: Use qubinode_navigator's OS plugins (rhel10/centos-stream) to provision hosts
2. **MCP Servers**: Leverage AI Assistant for RAG-powered documentation and troubleshooting
3. **Vault Integration**: Share HashiCorp Vault for unified secret management
4. **Event System**: Hook into qubinode_navigator's event system for orchestration

## qubinode_navigator Capabilities

### Plugin Architecture
```
plugins/
├── os/           # OS-specific deployment (RHEL 8/9/10, CentOS Stream 10)
├── cloud/        # Cloud providers (Hetzner, Equinix, AWS)
├── environments/ # Deployment environments
└── services/     # Service integrations (Vault, etc.)
```

### MCP Servers Available

| Server | Tools | Purpose |
|--------|-------|---------|
| **Airflow MCP** | 9 | DAG management, VM lifecycle, workflow orchestration |
| **AI Assistant MCP** | 3 | RAG documentation search, chat, context-aware help |

### Integration Points

| Component | qubinode_navigator | ocp4-disconnected-helper |
|-----------|-------------------|--------------------------|
| Host Provisioning | OS plugins | Consumes provisioned hosts |
| Secrets | HashiCorp Vault | Ansible Vault + Vault lookup |
| Orchestration | Airflow DAGs | Ansible playbooks |
| Documentation | AI Assistant RAG | ADRs, playbook docs |

## Consequences

### Positive
- **Unified infrastructure**: Single source for host provisioning
- **AI assistance**: RAG-powered troubleshooting and guidance
- **Secret sharing**: Centralized credential management
- **Consistent environments**: Reproducible CentOS Stream 10 hosts

### Negative
- **Dependency**: Requires qubinode_navigator for full workflow
- **Complexity**: Two projects to maintain and version
- **Learning curve**: Teams need familiarity with both projects

## Implementation

### Workflow Integration
```
┌─────────────────────────────────────────────────────────────────┐
│                    Integrated Workflow                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. qubinode_navigator: Provision CentOS Stream 10 host         │
│     └── python3 qubinode_cli.py deploy --plugin rhel10          │
│                                                                 │
│  2. ocp4-disconnected-helper: Mirror content                    │
│     └── ansible-playbook playbooks/download-to-tar.yml          │
│                                                                 │
│  3. ocp4-disconnected-helper: Setup registry                    │
│     └── ansible-playbook playbooks/setup-harbor-registry.yml    │
│                                                                 │
│  4. ocp4-disconnected-helper: Build appliance                   │
│     └── ansible-playbook playbooks/build-appliance.yml          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Shared Vault Configuration
```yaml
# Both projects use same Vault instance
vault_addr: "https://vault.example.com:8200"
vault_namespace: "disconnected-ocp"

# Secrets paths
vault_paths:
  registry_creds: "secret/ocp4-helper/registry"
  pull_secrets: "secret/ocp4-helper/pull-secret"
  ssh_keys: "secret/qubinode/ssh"
```

### AI Assistant Integration
```bash
# Query AI Assistant for ocp4-disconnected-helper docs
# (after ingesting docs into RAG)
curl -X POST http://localhost:8000/chat \
  -d '{"query": "How do I configure oc-mirror for OCP 4.20?"}'
```

### Inventory Handoff
```yaml
# qubinode_navigator generates inventory
# ocp4-disconnected-helper consumes it
[disconnected_hosts]
mirror-host ansible_host=192.168.1.100
registry-host ansible_host=192.168.1.101
```

## RAG Ingestion Plan

To enable AI-powered assistance across both projects:

1. **Ingest ocp4-disconnected-helper docs**:
   - PRD.md
   - docs/adrs/*.md
   - playbooks/*.yml (as reference)

2. **Cross-reference with qubinode_navigator**:
   - Link ADRs between projects
   - Share deployment patterns
   - Unified troubleshooting knowledge

## Related ADRs
- ADR 0001: Three-Tier Architecture
- ADR 0010: CentOS Stream 10 as Target Platform
- qubinode_navigator ADR-0028: Modular Plugin Framework
