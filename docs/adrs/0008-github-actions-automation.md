# ADR 0008: GitHub Actions for CI/CD Automation

**Status:** Proposed  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 3.2 - Objectives (GitHub Actions Automation)

## Context

The ocp4-disconnected-helper project needs automated workflows for:
- Validating playbook changes (linting, syntax checks)
- Triggering initial deployments
- Executing cluster updates
- Running integration tests

## Decision

Use **GitHub Actions** as the CI/CD platform with self-hosted runners for disconnected environment access.

### Workflow Types

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `lint.yml` | PR | Validate playbooks with ansible-lint |
| `build-appliance.yml` | workflow_dispatch | Build OpenShift appliance |
| `deploy-cluster.yml` | workflow_dispatch | Initial cluster deployment |
| `update-cluster.yml` | workflow_dispatch | Cluster updates |

## Consequences

### Positive
- Native GitHub integration
- Self-hosted runners bridge to disconnected environments
- Workflow as code, versioned with project
- Audit trail for all executions

### Negative
- Runner management overhead
- Network complexity for disconnected access
- Secrets management required

## Implementation

```yaml
# .github/workflows/lint.yml
name: Lint and Validate
on:
  pull_request:
    paths: ['playbooks/**', 'extra_vars/**']
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install ansible-lint yamllint
      - run: ansible-lint playbooks/
```

## Related ADRs
- ADR 0006: Lifecycle Management Strategy
- ADR 0009: Secret Management Strategy
