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
| TLS Certificates | Built-in + external injection | Manual | Manual |
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

4. **Certificate Integration** (Updated 2026-06-04):
   - **Default (Disconnected)**: Mirror-registry auto-generates self-signed CA
     - ⚠️ **LIMITATION**: CA is NOT trusted outside the registry VM
     - **RESOLUTION**: Must install CA in hypervisor trust store (see ADR 0016)
     - Implementation: `roles/registry_vm/tasks/setup_certificates.yml` (self-signed path)
   
   - **Cloud (Let's Encrypt)**: Use ADR 0016 setup_certificates.yml
     - Automatically trusted, no CA distribution needed
     - Pass certificates via `--sslCert` and `--sslKey` flags
     - Auto-selected when AWS credentials present
     - Implementation: `roles/registry_vm/tasks/setup_certificates.yml` (letsencrypt path)
   
   - **Installation Command**:
     ```bash
     ./mirror-registry install \
       --quayHostname registry.example.com \
       --quayRoot /opt/mirror-registry/quay-storage \
       --initPassword <password> \
       --sslCert /opt/mirror-registry/ssl.cert \
       --sslKey /opt/mirror-registry/ssl.key \
       --verbose
     ```
     
   **Critical Sequence**: Certificates MUST be configured BEFORE mirror-registry installation. Post-installation certificate injection is NOT supported by mirror-registry v2.

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

## Implementation Status

**Completed (2026-06-04)**:
- [x] Created `roles/registry_vm` with complete lifecycle management
  - VM provisioning via `common_vm` role delegation
  - Certificate setup with dual-path automation
  - Mirror-registry installation with `--sslCert` and `--sslKey` flags
  - Authentication setup and health verification
- [x] Integrated into `playbooks/site.yml` as primary deployment entrypoint
- [x] Tested with mirror-registry v2 on CentOS Stream 10
  - Successfully deployed with Let's Encrypt certificates
  - podman login authentication verified
  - Image push/pull operations validated

**Pending** (Future Work):
- [ ] Create `extra_vars/mirror-registry-example.yml`
- [ ] Update ADR 0004 to reference this ADR
- [ ] Document mirror-registry in README

## Incident Record

**Registry TLS Authentication Failure (2026-06-04)**:
- **Issue**: Mirror-registry's built-in self-signed CA was not trusted by podman on hypervisor
- **Discovery**: Initial deployment used self-signed CA despite Route53/AWS credentials being available
- **Resolution**: Implemented dual-path certificate automation (Let's Encrypt + self-signed)
- **Enhancement**: Added `--sslCert` and `--sslKey` flag support to installation command
- **Validation**: Added certificate trust check and podman login smoke test
- **PMB Reference**: ULID `0019e93110c6e_7c3ad77a` (pinned)
- **Full Report**: `docs/hardening/registry-tls-auth-failure-v1.0-2026-06-04.md`

This incident clarified that mirror-registry's "built-in certificate generation" produces untrusted self-signed certs and requires external certificate injection for production use.

## Related ADRs

- [ADR 0016: Trusted Certificate Management](0016-trusted-certificate-management.md) - Dual-path certificates (Let's Encrypt + self-signed)
- [ADR 0024: Roles Architecture](0024-ansible-roles-collections-architecture.md) - registry_vm role structure

## References

- [Quay mirror-registry GitHub](https://github.com/quay/mirror-registry)
- [Red Hat: Mirroring images for a disconnected installation](https://docs.openshift.com/container-platform/latest/installing/disconnected_install/installing-mirroring-installation-images.html)
- [mirror-registry documentation](https://docs.openshift.com/container-platform/latest/installing/disconnected_install/installing-mirroring-creating-registry.html)
- [mirror-registry v2 SSL Configuration](https://github.com/quay/mirror-registry#ssl-certificates)
