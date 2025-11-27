# ADR 0009: Secret Management Strategy

**Status:** Proposed  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 7.2 - Dependencies

## Context

The ocp4-disconnected-helper project handles sensitive data:
- Registry credentials (Harbor/JFrog admin passwords)
- Pull secrets for Red Hat registries
- SSH keys for appliance access
- Kubeconfig files for cluster management

Current state: Variables stored in plaintext YAML files pose security risks.

## Decision

Adopt a **tiered secret management strategy**:

### Tier 1: Development/Lab
- **Ansible Vault** for encrypting sensitive variables
- Vault password stored in environment variable or file

### Tier 2: Production
- **HashiCorp Vault** integration via `hashi_vault` lookup plugin
- Secrets fetched at runtime, never stored in files

### Tier 3: CI/CD
- **GitHub Secrets** for workflow credentials
- Self-hosted runner with Vault access

## Rationale

| Approach | Use Case | Security Level |
|----------|----------|----------------|
| Ansible Vault | Local dev, demos | Medium |
| HashiCorp Vault | Production | High |
| GitHub Secrets | CI/CD pipelines | Medium-High |

## Consequences

### Positive
- Secrets never in plaintext in git
- Audit trail for secret access
- Rotation without code changes
- Compliance with security standards

### Negative
- Additional infrastructure (Vault server)
- Operational complexity
- Learning curve for teams

## Implementation

### Ansible Vault (Tier 1)
```bash
# Encrypt sensitive vars file
ansible-vault encrypt extra_vars/secrets.yml

# Run playbook with vault
ansible-playbook playbooks/setup-harbor-registry.yml \
  --ask-vault-pass
```

### HashiCorp Vault (Tier 2)
```yaml
# In playbook
- name: Get registry password from Vault
  set_fact:
    harbor_admin_password: "{{ lookup('hashi_vault', 
      'secret=ocp4-helper/harbor:admin_password') }}"
```

### Variable Structure
```yaml
# extra_vars/secrets.yml.example
harbor_admin_password: "CHANGE_ME"
jfrog_admin_token: "CHANGE_ME"
pull_secret_path: "/path/to/pull-secret.json"
```

## Migration Path

1. Identify all sensitive variables in existing playbooks
2. Create `secrets.yml.example` template
3. Encrypt actual secrets with Ansible Vault
4. Update playbooks to use vault variables
5. Document vault password management

## Related ADRs
- ADR 0004: Dual Registry Support
- ADR 0008: GitHub Actions Automation
