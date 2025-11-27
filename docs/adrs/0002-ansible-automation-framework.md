# ADR 0002: Ansible as Automation Framework

**Status:** Accepted  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 5.1, 6.1 - Ansible Playbooks

## Context

The ocp4-disconnected-helper project requires an automation framework to:
- Install and configure software on target hosts
- Execute complex multi-step workflows
- Handle both initial deployment and ongoing lifecycle management
- Support idempotent operations for reliability

## Decision

Use **Ansible** as the primary automation framework with playbooks organized by function:

| Playbook | Purpose |
|----------|---------|
| `download-to-tar.yml` | Mirror content from registries to tar archives |
| `push-tar-to-registry.yml` | Push mirrored content to local registry |
| `setup-harbor-registry.yml` | Configure Harbor as local registry |
| `setup-jfrog-registry.yml` | Configure JFrog as local registry |
| `build-appliance.yml` | Build OpenShift appliance disk images (new) |
| `update-cluster.yml` | Update deployed clusters (new) |

## Rationale

### Why Ansible?
1. **Agentless architecture**: No agents needed on target hosts (SSH-based)
2. **Declarative and idempotent**: Ensures consistent state across runs
3. **Rich module ecosystem**: Built-in modules for package management, file operations, containers
4. **YAML-based**: Human-readable playbooks, easy to version control
5. **Red Hat ecosystem alignment**: Native integration with OpenShift tooling

### Alternatives Considered

| Alternative | Reason Rejected |
|-------------|-----------------|
| Terraform | Better for infrastructure provisioning, not configuration management |
| Puppet/Chef | Requires agents, more complex for this use case |
| Shell scripts | Not idempotent, harder to maintain at scale |
| Python scripts | Less standardized, requires more custom code |

## Consequences

### Positive
- **Idempotent operations**: Safe to re-run playbooks without side effects
- **Readable automation**: YAML playbooks are self-documenting
- **Extensible**: Easy to add new playbooks for additional functionality
- **Community support**: Large ecosystem of roles and modules

### Negative
- **Performance**: Slower than native scripts for simple tasks
- **Learning curve**: Requires Ansible knowledge for contributors
- **Secret management**: Need additional tooling (Ansible Vault) for sensitive data

## Implementation Notes

### Directory Structure
```
playbooks/
├── download-to-tar.yml
├── push-tar-to-registry.yml
├── setup-harbor-registry.yml
├── setup-jfrog-registry.yml
├── build-appliance.yml      # PRD Phase 1
├── update-cluster.yml       # PRD Phase 2
├── inventory
├── tasks/
└── templates/
```

### Variable Management
- Use `extra_vars/` directory for environment-specific configurations
- Sensitive data should use Ansible Vault encryption

## Related ADRs
- ADR 0001: Three-Tier Architecture
- ADR 0005: Secret Management Strategy
