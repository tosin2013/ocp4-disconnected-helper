# Understanding Certificate Management Decisions

Why this project supports both Let's Encrypt and self-signed certificates, and when to use each.

---

## The Certificate Challenge

**Problem**: Container registries require TLS/SSL certificates for secure image distribution. Getting trusted certificates in disconnected/air-gapped environments is difficult.

**Solutions**: Two paths based on deployment context:
1. **Let's Encrypt** - Cloud deployments with public DNS
2. **Self-Signed CA** - Air-gapped deployments without internet access

---

## Design Principles

### Principle 1: Context-Appropriate Certificate Source

**Not one-size-fits-all** - deployment environment determines certificate strategy.

**Cloud deployments** (IBM Cloud, AWS, Azure):
- Public DNS available (Route53, Cloud DNS, Azure DNS)
- Internet connectivity available
- Certificate verification easy (public CA chain)
- **Use Let's Encrypt**

**Air-gapped deployments** (on-premise data centers):
- No public DNS
- No internet connectivity
- Certificate distribution required
- **Use Self-Signed CA**

### Principle 2: Auto-Detection Over Manual Configuration

**Inventory auto-detection**:
```yaml
# inventory/ibm-cloud.yml
all:
  vars:
    certificate_mode: "{{ 'letsencrypt' if lookup('file', '~/.aws/credentials', errors='ignore') else 'selfsigned' }}"
```

**Logic**: AWS credentials present → public DNS available → use Let's Encrypt

**Why**: Reduces configuration errors, sensible defaults

### Principle 3: Certificate Before Registry

**Critical ordering**:
```bash
# ✅ Correct order
1. Generate certificates (setup-certificates.yml)
2. Install mirror-registry with --sslCert and --sslKey flags

# ❌ Wrong order
1. Install mirror-registry (generates own self-signed cert)
2. Try to replace certificate → NOT SUPPORTED
```

**Why mirror-registry v2 limitation**: Post-install certificate injection not supported.

---

## Let's Encrypt Path

### How It Works

**DNS-01 Challenge**:
1. Let's Encrypt asks: "Prove you control example.com"
2. Certbot creates TXT record: `_acme-challenge.example.com`
3. Let's Encrypt verifies TXT record exists
4. Let's Encrypt issues trusted certificate

**Advantages**:
- ✅ Publicly trusted (no CA distribution needed)
- ✅ Automatic renewal (90-day certificates)
- ✅ Works everywhere (browsers, podman, kubectl trust it)
- ✅ Free

**Requirements**:
- DNS hosted in Route53 (or other supported DNS provider)
- AWS credentials with Route53 permissions
- Public DNS zone

### When to Use Let's Encrypt

**Use when**:
- ✅ Registry has public DNS name
- ✅ AWS/Azure/GCP credentials available
- ✅ DNS hosted in supported provider (Route53, Cloud DNS)
- ✅ Internet connectivity during certificate generation
- ✅ Users access registry from outside environment

**Example deployment context**:
- IBM Cloud VSI with public IP
- Domain: registry.sandbox3377.opentlc.com
- DNS: AWS Route53
- Users: Remote developers, CI/CD systems

### Certificate Lifecycle

**Issuance**: 5-10 minutes (DNS propagation + validation)  
**Validity**: 90 days  
**Renewal**: Automatic via certbot cron job  
**Renewal frequency**: 60 days (30 days before expiry)

**Renewal automation**:
```bash
# Cron job created by setup-certificates.yml
0 0,12 * * * /usr/bin/certbot renew --quiet --deploy-hook "systemctl restart quay-pod"
```

---

## Self-Signed CA Path

### How It Works

**Self-Signed Certificate Generation**:
1. Create CA private key and certificate (10-year validity)
2. Create server private key
3. Generate Certificate Signing Request (CSR)
4. Sign server certificate with CA
5. Install server cert + key in registry

**Advantages**:
- ✅ Works offline (no internet required)
- ✅ Full control (10-year validity, custom attributes)
- ✅ No external dependencies
- ✅ Free

**Disadvantages**:
- ❌ Not publicly trusted (requires CA distribution)
- ❌ Manual trust configuration on clients
- ❌ No automatic renewal

### When to Use Self-Signed

**Use when**:
- ✅ Air-gapped environment (no internet)
- ✅ No public DNS
- ✅ All clients within controlled network
- ✅ Can distribute CA to clients

**Example deployment context**:
- On-premise data center
- Registry: registry.internal.example.com
- DNS: Internal/VyOS dnsmasq
- Users: Only internal OpenShift clusters

### CA Distribution Strategy

**To Ansible control node**:
```bash
ansible-playbook playbooks/distribute-ca.yml \
  -e ca_cert_path=/opt/certificates/quay-rootCA/rootCA.pem
```

**To OpenShift clusters** (during installation):
```yaml
# install-config.yaml
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  (CA certificate content)
  -----END CERTIFICATE-----
```

**To individual clients**:
```bash
# RHEL/CentOS
sudo cp quay-rootCA.pem /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust extract

# Ubuntu
sudo cp quay-rootCA.pem /usr/local/share/ca-certificates/quay-rootCA.crt
sudo update-ca-certificates
```

---

## Implementation: Dual-Path Playbook

### setup-certificates.yml Design

**Single playbook, two paths**:
```yaml
- name: Setup Certificates
  hosts: registry_vm
  tasks:
    - name: Let's Encrypt path
      include_tasks: letsencrypt.yml
      when: certificate_mode == 'letsencrypt'
    
    - name: Self-signed path
      include_tasks: selfsigned.yml
      when: certificate_mode == 'selfsigned'
```

**Why single playbook**: Consistent interface, mode selection via survey/extra_vars

### Certificate Output Locations

**Let's Encrypt**:
```
/etc/letsencrypt/live/registry.example.com/
├── fullchain.pem  → Server certificate + intermediate CA
├── privkey.pem    → Private key
└── chain.pem      → Intermediate CA only
```

**Self-Signed**:
```
/opt/certificates/
├── registry.example.com.crt  → Server certificate
├── registry.example.com.key  → Private key
└── quay-rootCA/
    ├── rootCA.pem            → CA certificate (distribute to clients)
    └── rootCA.key            → CA private key (keep secret)
```

---

## Security Considerations

### Let's Encrypt Security

**Strengths**:
- Public CA chain (ISRG Root X1) widely trusted
- Automatic renewal reduces expired certificate risk
- Rate limiting prevents abuse

**Risks**:
- AWS credentials compromise = unauthorized certificate issuance
- Public CT logs expose domain names
- DNS provider outage = renewal failure

**Mitigation**:
```yaml
# Use IAM user with minimal Route53 permissions
{
  "Effect": "Allow",
  "Action": ["route53:ChangeResourceRecordSets"],
  "Resource": "arn:aws:route53:::hostedzone/Z123..."
}
```

### Self-Signed Security

**Strengths**:
- Full control over CA (no external dependencies)
- CA private key never leaves environment
- Long validity (10 years) reduces operational overhead

**Risks**:
- CA private key compromise = all certificates untrusted
- No certificate revocation mechanism
- Manual client trust required

**Mitigation**:
```bash
# Protect CA private key
chmod 600 /opt/certificates/quay-rootCA/rootCA.key
chown root:root /opt/certificates/quay-rootCA/rootCA.key

# Separate CA signing from certificate generation
# (CA key only accessed during certificate generation, not runtime)
```

---

## Trade-offs Matrix

| Aspect | Let's Encrypt | Self-Signed |
|--------|--------------|-------------|
| **Trust** | Public (works everywhere) | Private (requires distribution) |
| **Validity** | 90 days | 10 years |
| **Renewal** | Automatic | Manual |
| **Internet** | Required | Not required |
| **DNS** | Public DNS required | Any DNS works |
| **Setup Time** | 5-10 minutes | 2-5 minutes |
| **Operational Overhead** | Low (auto-renewal) | Medium (manual renewal) |
| **Security** | External dependency | Full control |
| **Cost** | Free | Free |

---

## Certificate Troubleshooting

### Let's Encrypt Failures

**DNS-01 validation fails**:
```
Error: Timeout waiting for DNS propagation
```

**Cause**: Route53 zone ID incorrect or DNS not propagating

**Solution**:
```bash
# Verify DNS record creation
dig +short _acme-challenge.registry.example.com TXT

# Wait 60 seconds for propagation
sleep 60 && ansible-playbook playbooks/setup-certificates.yml -e certificate_mode=letsencrypt
```

**Rate limit exceeded**:
```
Error: too many certificates already issued for: example.com
```

**Cause**: Let's Encrypt rate limit (50 certificates per domain per week)

**Solution**: Use staging environment for testing, production for final deployment

### Self-Signed Failures

**Client doesn't trust certificate**:
```
Error: x509: certificate signed by unknown authority
```

**Cause**: CA not in client's trust store

**Solution**: Distribute CA certificate and update client trust (see "CA Distribution Strategy" above)

---

## Migration Between Certificate Modes

### Let's Encrypt → Self-Signed

**Scenario**: Moving from cloud to air-gapped deployment

**Steps**:
1. Generate self-signed certificate
2. Destroy existing registry: `ansible-playbook playbooks/destroy-registry.yml -e confirm_destroy=yes`
3. Re-deploy with self-signed: `ansible-playbook playbooks/setup-mirror-registry.yml -e certificate_mode=selfsigned`
4. Distribute CA to all clients
5. Re-mirror images from TAR archives

### Self-Signed → Let's Encrypt

**Scenario**: Moving from on-premise to cloud

**Steps**:
1. Configure AWS Route53 DNS
2. Generate Let's Encrypt certificate
3. Destroy existing registry
4. Re-deploy with Let's Encrypt: `ansible-playbook playbooks/setup-mirror-registry.yml -e certificate_mode=letsencrypt`
5. Re-mirror images

**Why re-deploy**: Mirror-registry v2 doesn't support certificate replacement post-install

---

## Related Decisions

- [ADR-0016: Trusted Certificate Management](../adrs/0016-trusted-certificate-management.md)
- [ADR-0017: Quay Mirror Registry](../adrs/0017-quay-mirror-registry.md)
- [Resolve: Registry TLS Authentication](../how-to/resolve-registry-tls-authentication.md)

---

## Summary

**Certificate management is context-driven**:
- Cloud deployments → Let's Encrypt (publicly trusted, automatic renewal)
- Air-gapped deployments → Self-Signed (works offline, full control)

**Key insight**: No single "best" certificate solution - deployment environment determines optimal approach.
