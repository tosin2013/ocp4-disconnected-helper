# ADR 0016: Trusted Certificate Management for Disconnected Environments

## Status
Proposed

## Date
2025-11-26

## Context

In disconnected OpenShift environments, all internal services require TLS certificates that are trusted by cluster nodes and workloads. Without proper certificate management:

1. **Registry pulls fail** with certificate validation errors
2. **OpenShift installation** cannot validate image signatures
3. **Appliance builder** cannot connect to local registries
4. **Cluster updates fail** when pulling from internal mirrors

### Supporting Evidence

- Harbor registry requires TLS for production use
- OpenShift image signature verification requires trusted CAs
- oc-mirror validates registry certificates during push operations
- Appliance builder embeds CA bundles for offline installation
- Agent-based installer requires trusted certificates for registry access

### Current State

The project has:
- `setup-harbor-registry.yml` - Deploys Harbor but lacks certificate automation
- `setup-jfrog-registry.yml` - Deploys JFrog but lacks certificate automation
- No standardized CA management across playbooks
- No certificate injection into appliance builds

## Decision

Implement a centralized certificate management strategy:

### 1. Dedicated Certificate Authority (CA)

Create a project-specific CA for the disconnected environment:
- Root CA with 10-year validity
- Intermediate CA for service certificates (optional)
- Automated certificate generation via Ansible

### 2. Ansible Playbooks

```
playbooks/
├── setup-certificates.yml      # Generate CA and service certs
├── rotate-certificates.yml     # Certificate rotation
└── templates/
    ├── ca-config.json.j2       # CA configuration
    ├── server-csr.json.j2      # Server certificate CSR
    └── openssl.cnf.j2          # OpenSSL configuration
```

### 3. Certificate Distribution

- Embed CA bundle in appliance configuration
- Distribute to cluster nodes during bootstrap
- Configure registries with generated certificates
- Update trust stores on management hosts

### 4. Integration Points

| Component | Certificate Usage |
|-----------|-------------------|
| Harbor Registry | Server TLS certificate |
| JFrog Artifactory | Server TLS certificate |
| Appliance Builder | CA bundle for registry trust |
| OpenShift Nodes | CA bundle in trust store |
| oc-mirror | Registry certificate validation |

### 5. Implementation Variables

```yaml
# Certificate configuration
cert_organization: "Disconnected Lab"
cert_country: "US"
cert_state: "Virginia"
cert_locality: "Reston"
cert_validity_days: 3650  # 10 years for CA
cert_server_validity_days: 365  # 1 year for server certs

# Paths
ca_cert_path: "/etc/pki/disconnected-ca"
ca_key_path: "/etc/pki/disconnected-ca/private"
registry_cert_path: "/etc/pki/registry"

# Registry hostnames (for SAN)
registry_hostnames:
  - "registry.disconnected.local"
  - "harbor.disconnected.local"
  - "{{ ansible_fqdn }}"
```

## Consequences

### Positive

- **Secure TLS communication** across all disconnected services
- **Seamless registry authentication** without certificate errors
- **Compliance** with enterprise security requirements
- **Reproducible deployment** via Ansible automation
- **Auditable** certificate lifecycle

### Negative

- **Additional complexity** in initial setup
- **Certificate rotation** requires planned maintenance
- **CA private key** becomes critical security asset
- **Training required** for operations team

### Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| CA compromise | Low | Critical | Secure key storage, HSM for production |
| Certificate expiry | Medium | High | Monitoring, automated rotation |
| Trust chain issues | Medium | Medium | Thorough testing, documentation |

## Alternatives Considered

### 1. Insecure Registries (`--insecure-registry`)
**Rejected**: Security risk, not suitable for production, violates compliance requirements.

### 2. Manual Certificate Management
**Rejected**: Error-prone, not reproducible, doesn't scale.

### 3. Per-Service Self-Signed Certificates
**Rejected**: Complex trust chain, each service needs separate trust configuration.

### 4. Let's Encrypt / ACME
**Rejected**: Not applicable in disconnected environments without internet access.

### 5. Enterprise PKI Integration Only
**Partially Accepted**: Supported as an option, but self-signed CA provides standalone capability.

## Implementation Tasks

1. [ ] Create `playbooks/setup-certificates.yml`
   - Generate Root CA
   - Generate registry server certificates
   - Configure certificate paths

2. [ ] Create certificate templates
   - `templates/ca-csr.json.j2`
   - `templates/server-csr.json.j2`
   - `templates/openssl.cnf.j2`

3. [ ] Update registry playbooks
   - Modify `setup-harbor-registry.yml` to use generated certs
   - Modify `setup-jfrog-registry.yml` to use generated certs

4. [ ] Create `playbooks/rotate-certificates.yml`
   - Backup existing certificates
   - Generate new certificates
   - Distribute to services
   - Restart affected services

5. [ ] Update appliance builder integration
   - Inject CA bundle into `appliance-config.yaml`
   - Document CA trust configuration

6. [ ] Create monitoring/alerting
   - Certificate expiry checks
   - CA health validation

## Related ADRs

- [ADR 0004: Dual Registry Support](0004-dual-registry-support.md) - Registry configuration
- [ADR 0005: OpenShift Appliance Builder](0005-openshift-appliance-builder.md) - Appliance integration
- [ADR 0009: Secret Management](0009-secret-management.md) - CA key protection

## References

- [OpenShift Documentation: Configuring a Custom PKI](https://docs.openshift.com/container-platform/latest/security/certificates/replacing-default-ingress-certificate.html)
- [Harbor TLS Configuration](https://goharbor.io/docs/latest/install-config/configure-https/)
- [Red Hat: Managing Certificates in OpenShift](https://access.redhat.com/documentation/en-us/openshift_container_platform/)
