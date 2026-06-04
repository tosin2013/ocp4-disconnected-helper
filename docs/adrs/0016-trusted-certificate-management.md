# ADR 0016: Trusted Certificate Management for Disconnected Environments

## Status
Accepted (Updated 2026-06-04)

## Date
2025-11-26 (Original), 2026-06-04 (Updated)

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

### Deployment Context Discovery (Added 2026-06-04)

**CRITICAL FINDING**: Initial ADR assumed pure disconnected environments. Real-world deployments may be:

1. **Cloud-Connected** (IBM Cloud, AWS, GCP): Route53/DNS automation available
2. **On-Premise Disconnected**: True air-gapped with no internet access
3. **Hybrid**: Connected for setup, disconnected post-deployment

The automation MUST detect the deployment context and select the appropriate certificate strategy.

## Decision

Implement a **dual-path certificate management strategy** with automatic detection:

### 0. Auto-Detection Logic (Added 2026-06-04)

```yaml
# Determine certificate strategy based on environment
ssl_cert_provider: "{{ 'letsencrypt' if aws_credentials_available else 'selfsigned' }}"
```

**Detection Criteria**:
- Check for `~/.aws/credentials` file existence
- Verify Route53 hosted zone accessibility (implicit via credentials)
- If AWS credentials present: use Let's Encrypt with DNS-01 challenge
- If credentials missing: use self-signed CA

**Implementation**: `roles/registry_vm/defaults/main.yml`

### 1. Let's Encrypt Path (Cloud/Connected) — Added 2026-06-04

**When to Use**: AWS Route53 available, DNS automation possible

**Implementation**:
```yaml
roles/registry_vm/tasks/setup_certificates.yml:
- Install certbot and certbot-dns-route53
- Read AWS credentials from ~/.aws/credentials
- Request certificate via DNS-01 challenge
- Copy fullchain.pem and privkey.pem to registry VM
- Pass --sslCert and --sslKey to mirror-registry install
```

**Benefits**:
- Automatically trusted by all systems (no CA distribution)
- Industry-standard certificate authority
- 90-day validity with auto-renewal capability
- **PREFERRED** for cloud/hybrid deployments

### 2. Self-Signed CA Path (Disconnected/On-Premise)

**When to Use**: No AWS credentials, no Route53, true air-gapped deployment

Create a project-specific CA for the disconnected environment:
- Root CA with 10-year validity
- Intermediate CA for service certificates (optional)
- Automated certificate generation via Ansible
- **Manual trust store distribution required**

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

### 5. Critical Constraint (Added 2026-06-04)

**USER REQUIREMENT** (from incident resolution): "It is not good to skip the cert validation"

**Enforcement**:
- NEVER use `--insecure-registry` or `--skip-tls-verify` in production
- NEVER bypass certificate validation for convenience
- ALWAYS use either Let's Encrypt (cloud) or properly-distributed self-signed CA (disconnected)
- Preflight validation MUST confirm certificate provider matches infrastructure

**Rationale**: Security-first approach. Certificate validation protects against MITM attacks and ensures registry authenticity.

### 6. Implementation Sequence (Added 2026-06-04)

**CRITICAL**: Certificates MUST be generated BEFORE mirror-registry installation

```yaml
# roles/registry_vm/tasks/main.yml
- import_tasks: setup_certificates.yml        # PHASE 2 - Generate/fetch certs
- assert: mirror_registry_ssl_cert is defined  # PHASE 2.5 - Validate certs exist
- import_tasks: install_mirror_registry.yml    # PHASE 3 - Install with --sslCert/--sslKey
```

**Why**: mirror-registry v2 requires certificates at install time. Post-installation certificate injection is NOT supported.

### 7. Implementation Variables

```yaml
# Certificate provider (auto-detected based on AWS credentials)
ssl_cert_provider: "{{ 'letsencrypt' if lookup('file', lookup('env', 'HOME') + '/.aws/credentials', errors='ignore') else 'selfsigned' }}"

# Preflight validation
validate_cert_provider: true  # Verify cert provider matches infrastructure

# Certificate configuration (self-signed path)
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

# Let's Encrypt configuration
letsencrypt_email: "admin@{{ external_domain }}"
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

### Risks (Updated 2026-06-04)

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| CA compromise | Low | Critical | Secure key storage, HSM for production |
| Certificate expiry | Medium | High | Monitoring, automated rotation |
| Trust chain issues | Medium | Medium | Thorough testing, documentation |
| Let's Encrypt rate limits | Low | Medium | Use DNS-01 (higher limit), staging for testing |
| AWS credentials exposure | Medium | Critical | Read from ~/.aws/, never commit to git |
| Wrong cert path selected | Low | High | Auto-detect with preflight validation |

## Alternatives Considered

### 1. Insecure Registries (`--insecure-registry`)
**Rejected**: Security risk, not suitable for production, violates compliance requirements.

### 2. Manual Certificate Management
**Rejected**: Error-prone, not reproducible, doesn't scale.

### 3. Per-Service Self-Signed Certificates
**Rejected**: Complex trust chain, each service needs separate trust configuration.

### 4. Let's Encrypt / ACME
**UPDATED DECISION (2026-06-04)**: **Accepted** for cloud/connected deployments with Route53.

**Original Rejection Reason** (2025-11-26): "Not applicable in disconnected environments without internet access"

**Why the Change**:
- Initial ADR assumed all "disconnected OpenShift" deployments were truly air-gapped
- Real-world finding: Many disconnected deployments use cloud infrastructure (IBM Cloud, AWS, GCP) during setup phase
- These environments have Route53 DNS and AWS credentials available
- Let's Encrypt with Route53 DNS-01 validation is **PREFERRED** when available because:
  - Automatically trusted by all systems (no CA distribution)
  - Industry-standard CA with wide trust
  - 90-day validity with auto-renewal
  - No manual trust store installation required

**When to Use**:
- Cloud deployments: IBM Cloud, AWS, GCP (Route53 available)
- Hybrid deployments: Connected during setup, disconnected post-deployment
- Any environment with `~/.aws/credentials` and Route53 access

**When NOT to Use**:
- True air-gapped environments with no internet access
- On-premise deployments without Route53
- Compliance requirements preventing external CA usage

**Implementation Status**: ✅ Completed (2026-06-04)
- `roles/registry_vm/tasks/setup_certificates.yml` with dual-path logic
- Auto-detection based on AWS credentials presence
- Preflight validation to catch misconfigurations

### 5. Enterprise PKI Integration Only
**Partially Accepted**: Supported as an option, but self-signed CA provides standalone capability.

## Implementation Status

**Completed (2026-06-04)**:
- [x] Created `roles/registry_vm/tasks/setup_certificates.yml` with dual-path logic
  - Let's Encrypt path with certbot-dns-route53
  - Self-signed CA path with trust store installation
  - Auto-detection based on AWS credentials presence
  - Preflight validation to catch misconfigurations
- [x] Integrated into `roles/registry_vm/tasks/main.yml` deployment workflow
  - Certificate setup runs BEFORE mirror-registry installation
  - Assertion validates certificates configured before install
  - Certificates passed via --sslCert and --sslKey flags
- [x] Added preflight validation mode to `playbooks/site.yml`
  - Usage: `ansible-playbook ... --tags validate`
  - Checks cert provider matches infrastructure
  - Warns about misconfigurations before deployment
- [x] Tested with mirror-registry v2 on CentOS Stream 10
  - Let's Encrypt certificates successfully obtained
  - podman login authentication verified
  - Image push/pull operations validated

**Pending** (Future Work):
- [ ] Create certificate templates for Harbor/JFrog
  - `templates/ca-csr.json.j2`
  - `templates/server-csr.json.j2`
  - `templates/openssl.cnf.j2`
- [ ] Update registry playbooks for Harbor/JFrog
  - Modify `setup-harbor-registry.yml` to use generated certs
  - Modify `setup-jfrog-registry.yml` to use generated certs
- [ ] Create `playbooks/rotate-certificates.yml`
  - Backup existing certificates
  - Generate new certificates
  - Distribute to services
  - Restart affected services
- [ ] Update appliance builder integration
  - Inject CA bundle into `appliance-config.yaml`
  - Document CA trust configuration
- [ ] Create monitoring/alerting
  - Certificate expiry checks
  - CA health validation

## Incident Record

**Registry TLS Authentication Failure (2026-06-04)**:
- **Symptom**: podman login failed with "x509: certificate signed by unknown authority"
- **Root Cause**: Self-signed CA used despite Route53/AWS credentials being available
- **Resolution**: Implemented dual-path automation with auto-detection
- **Prevention**: Preflight validation, structural assertions, AI agent guidance in CLAUDE.md
- **PMB Reference**: ULID `0019e93110c6e_7c3ad77a` (pinned)
- **Full Report**: `docs/hardening/registry-tls-auth-failure-v1.0-2026-06-04.md`

This incident drove the acceptance of Let's Encrypt as a primary certificate strategy for cloud/hybrid deployments.

## Related ADRs

- [ADR 0017: Quay Mirror Registry](0017-quay-mirror-registry.md) - Registry implementation with certificate injection
- [ADR 0009: Secret Management](0009-secret-management.md) - CA key protection
- [ADR 0024: Roles Architecture](0024-ansible-roles-collections-architecture.md) - Role structure

## References

- [OpenShift Documentation: Configuring a Custom PKI](https://docs.openshift.com/container-platform/latest/security/certificates/replacing-default-ingress-certificate.html)
- [Let's Encrypt DNS-01 Challenge](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge)
- [Certbot DNS Route53 Plugin](https://certbot-dns-route53.readthedocs.io/)
- [Red Hat: Managing Certificates in OpenShift](https://access.redhat.com/documentation/en-us/openshift_container_platform/)
