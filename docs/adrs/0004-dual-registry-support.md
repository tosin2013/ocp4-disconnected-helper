# ADR 0004: Dual Registry Support (Harbor and JFrog)

**Status:** Accepted  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 5.2 - Variables for Appliance Configuration

## Context

Organizations deploying OpenShift in disconnected environments use various container registries based on their existing infrastructure, compliance requirements, and operational preferences. The two most common enterprise registries are:

1. **Harbor**: Open-source, CNCF graduated project
2. **JFrog Artifactory**: Commercial solution with broad artifact support

## Decision

Support **both Harbor and JFrog** as target registries through dedicated setup playbooks:

- `setup-harbor-registry.yml` - Configure Harbor registry
- `setup-jfrog-registry.yml` - Configure JFrog Artifactory

The `push-tar-to-registry.yml` playbook will be registry-agnostic, using standard OCI/Docker registry APIs.

## Rationale

### Why Support Both?
1. **Customer flexibility**: Different organizations have different registry investments
2. **No vendor lock-in**: Users can choose based on their requirements
3. **Compliance**: Some industries mandate specific registry solutions
4. **Feature parity**: Both support OCI artifacts and container images

### Comparison

| Feature | Harbor | JFrog Artifactory |
|---------|--------|-------------------|
| License | Open Source (Apache 2.0) | Commercial (OSS tier available) |
| OCI Support | Full | Full |
| Vulnerability Scanning | Built-in (Trivy) | Built-in + integrations |
| Replication | Native | Native |
| RBAC | Project-based | Repository-based |
| Air-gap Support | Excellent | Excellent |

## Consequences

### Positive
- **Flexibility**: Users choose registry based on their needs
- **Adoption**: Lower barrier to entry for existing registry users
- **Maintenance**: Separate playbooks allow independent updates

### Negative
- **Code duplication**: Similar logic in both setup playbooks
- **Testing overhead**: Must validate against both registries
- **Documentation**: Need to maintain docs for both options

## Implementation

### Playbook Structure
```
playbooks/
├── setup-harbor-registry.yml    # Harbor-specific setup
├── setup-jfrog-registry.yml     # JFrog-specific setup
└── push-tar-to-registry.yml     # Registry-agnostic push
```

### Common Variables
```yaml
# Shared across both registries
appliance_image_registry_uri: "registry.example.com"
appliance_image_registry_port: 443

# Registry-specific
harbor_admin_password: "{{ vault_harbor_password }}"
jfrog_admin_token: "{{ vault_jfrog_token }}"
```

### Registry Selection
```yaml
# extra_vars/registry.yml
registry_type: "harbor"  # or "jfrog"
```

## Migration Path

For users switching registries:
1. Export images from source registry
2. Run appropriate setup playbook for target
3. Re-push content using `push-tar-to-registry.yml`

## Related ADRs
- ADR 0003: oc-mirror for Image Mirroring
- ADR 0005: Secret Management Strategy
