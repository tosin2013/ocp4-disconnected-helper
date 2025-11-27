# ADR 0017: Quay Mirror Registry as Lightweight Registry Option

## Status
Accepted

## Date
2025-11-26

## Context

The project currently supports Harbor and JFrog Artifactory as registry options (ADR 0004). However, Red Hat provides the **Quay mirror-registry** (https://github.com/quay/mirror-registry) as a purpose-built, lightweight solution specifically designed for disconnected OpenShift deployments.

### Mirror-Registry Advantages

| Feature | mirror-registry | Harbor | JFrog |
|---------|-----------------|--------|-------|
| Installation | Single binary | Helm/Docker Compose | Complex |
| Red Hat Support | ✅ Official | Community | Enterprise license |
| Resource Requirements | Minimal (~2GB RAM) | Medium (~8GB RAM) | High |
| TLS Certificates | Built-in generation | Manual | Manual |
| oc-mirror Integration | Native | Compatible | Compatible |
| Air-gap Transfer | Single tarball | Multiple containers | Multiple containers |
| Web UI | Quay UI included | Harbor UI | JFrog UI |
| Vulnerability Scanning | ❌ | ✅ Trivy/Clair | ✅ Xray |
| High Availability | ❌ Single node | ✅ | ✅ |
| Replication | ❌ | ✅ | ✅ |

### Why Add Mirror-Registry?

1. **Official Red Hat Support** - Documented in OpenShift disconnected installation guides
2. **Simplicity** - Single binary, single command installation
3. **Air-gap Optimized** - Designed for transfer to disconnected environments
4. **Built-in TLS** - Generates certificates automatically
5. **Quay Backend** - Production-grade registry with web UI

## Decision

Add Quay mirror-registry as a **third registry option** and make it the **RECOMMENDED default** for new disconnected deployments.

### Implementation

1. **New Playbook**: `playbooks/setup-mirror-registry.yml`
   - Download mirror-registry binary
   - Install with configurable options
   - Support both auto-generated and custom TLS certificates
   - Configure for oc-mirror compatibility

2. **Registry Selection Variable**:
   ```yaml
   # extra_vars/registry.yml
   registry_type: "mirror-registry"  # Options: mirror-registry, harbor, jfrog
   ```

3. **Integration with Existing Playbooks**:
   - Update `push-tar-to-registry.yml` to detect registry type
   - Update Airflow DAGs to support registry selection

4. **Certificate Options**:
   - **Default**: Use mirror-registry's built-in certificate generation
   - **Custom**: Use certificates from ADR 0016 (`setup-certificates.yml`)

### Recommendation Matrix

| Use Case | Recommended Registry |
|----------|---------------------|
| Simple disconnected deployment | **mirror-registry** |
| Enterprise with existing Harbor | Harbor |
| Enterprise with JFrog license | JFrog |
| Need vulnerability scanning | Harbor |
| Need HA/replication | Harbor or JFrog |
| Fastest time to deploy | **mirror-registry** |

## Consequences

### Positive

- **Simpler deployment** for most users
- **Official Red Hat support** and documentation
- **Single-binary installation** - easy air-gap transfer
- **Built-in TLS** - reduces certificate complexity
- **Quay UI** - web interface for browsing images
- **Lower resource requirements** - runs on smaller hardware

### Negative

- **No vulnerability scanning** - must use external tools
- **Single-node only** - no high availability
- **No replication** - cannot sync between registries
- **Less enterprise features** - may not meet compliance requirements

### Trade-offs

| Requirement | mirror-registry | Alternative |
|-------------|-----------------|-------------|
| Simple deployment | ✅ Best choice | - |
| Vulnerability scanning | ❌ | Harbor with Trivy |
| High availability | ❌ | Harbor or JFrog |
| Enterprise compliance | ⚠️ May not meet | Harbor or JFrog |
| Air-gap simplicity | ✅ Best choice | - |

## Alternatives Considered

### 1. Harbor Only
**Rejected**: Too complex for simple deployments, requires multiple containers.

### 2. JFrog Only  
**Rejected**: Requires enterprise license for full features.

### 3. Docker Registry
**Rejected**: Lacks OCI artifact support, no authentication UI, no web interface.

### 4. Podman Registry
**Rejected**: Not designed for production use, lacks features.

## Implementation Tasks

1. [ ] Create `playbooks/setup-mirror-registry.yml`
2. [ ] Create `templates/mirror-registry-config.yml.j2`
3. [ ] Update `push-tar-to-registry.yml` for mirror-registry support
4. [ ] Update Airflow DAGs with registry_type parameter
5. [ ] Create `extra_vars/mirror-registry-example.yml`
6. [ ] Update ADR 0004 to reference this ADR
7. [ ] Document mirror-registry in README

## Related ADRs

- [ADR 0004: Dual Registry Support](0004-dual-registry-support.md) - Original registry decision
- [ADR 0016: Trusted Certificate Management](0016-trusted-certificate-management.md) - Custom certificates

## References

- [Quay mirror-registry GitHub](https://github.com/quay/mirror-registry)
- [Red Hat: Mirroring images for a disconnected installation](https://docs.openshift.com/container-platform/latest/installing/disconnected_install/installing-mirroring-installation-images.html)
- [mirror-registry documentation](https://docs.openshift.com/container-platform/latest/installing/disconnected_install/installing-mirroring-creating-registry.html)
