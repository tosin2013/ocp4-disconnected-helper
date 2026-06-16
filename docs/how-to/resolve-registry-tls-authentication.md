# How to Resolve: Registry TLS Authentication Failure

Fix "tls: failed to verify certificate: x509: certificate signed by unknown authority" when authenticating to mirror registry.

---

## Problem

`podman login` to mirror registry fails with:

```
Error: authenticating creds for "registry.example.com:8443": pinging container registry registry.example.com:8443: Get "https://registry.example.com:8443/v2/": tls: failed to verify certificate: x509: certificate signed by unknown authority
```

However, registry health endpoint works:
```bash
curl -k https://registry.example.com:8443/health/instance
# ✅ Returns {"status": "healthy"}
```

---

## Root Cause

**Certificate Trust Chain Broken**: Mirror-registry v2 generates a self-signed CA certificate that is NOT in the system's trusted CA bundle. Podman (and other clients) refuse to authenticate because they can't verify the certificate.

See [Hardening Report: Registry TLS Auth Failure (v1.0)](../hardening/registry-tls-auth-failure-v1.0-2026-06-04.md) for complete incident analysis.

---

## Solution

### Option A: Add CA Certificate to System Trust (Recommended)

**When to use**: Production deployments, multiple clients need access

**Steps**:

1. **Copy CA certificate from registry VM**:
   ```bash
   scp admin@registry.example.com:/opt/mirror-registry/quay-rootCA/rootCA.pem \
     /tmp/quay-rootCA.pem
   ```

2. **Add to system trust store**:
   ```bash
   # RHEL/CentOS Stream
   sudo cp /tmp/quay-rootCA.pem /etc/pki/ca-trust/source/anchors/
   sudo update-ca-trust extract
   
   # Ubuntu/Debian
   sudo cp /tmp/quay-rootCA.pem /usr/local/share/ca-certificates/quay-rootCA.crt
   sudo update-ca-certificates
   ```

3. **Verify trust**:
   ```bash
   openssl s_client -connect registry.example.com:8443 -CApath /etc/pki/tls/certs \
     < /dev/null 2>&1 | grep -E "Verify return code"
   
   # Expected: Verify return code: 0 (ok)
   ```

4. **Test authentication**:
   ```bash
   echo "$PASSWORD" | podman login --username init \
     --password-stdin registry.example.com:8443
   
   # Expected: Login Succeeded!
   ```

---

### Option B: Use Let's Encrypt (Cloud Deployments Only)

**When to use**: Registry has public DNS and Route53 access

**Prevention**: Configure Let's Encrypt BEFORE deploying mirror-registry

1. **Verify Route53 credentials**:
   ```bash
   ls ~/.aws/credentials && echo "Use Let's Encrypt" || echo "Use self-signed"
   ```

2. **Deploy with Let's Encrypt mode**:
   ```bash
   ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml \
     -e certificate_mode=letsencrypt \
     --tags certificates,registry
   ```

3. **Verify public trust**:
   ```bash
   curl https://registry.example.com:8443/health/instance
   # Should work without -k flag (no certificate error)
   ```

**Advantage**: No CA distribution needed, works everywhere

---

### Option C: Skip TLS Verification (Development Only)

**When to use**: Temporary testing, not production

**Warning**: Security risk - opens door to MITM attacks

```bash
# Podman login with insecure flag
podman login --tls-verify=false registry.example.com:8443

# oc-mirror with insecure flag
oc-mirror --dest-skip-tls --from ./mirror-seq1 \
  docker://registry.example.com:8443/openshift/release
```

**Do NOT use in production** - use Option A or B instead.

---

## Prevention

### Deploy Certificates BEFORE Mirror-Registry

**Critical order**:
1. Setup certificates (Let's Encrypt or self-signed)
2. Install mirror-registry with `--sslCert` and `--sslKey` flags

**Bad** (post-install certificate injection):
```bash
# ❌ Mirror-registry installed first
ansible-playbook playbooks/setup-mirror-registry.yml

# ❌ Certificates generated after - TOO LATE
ansible-playbook playbooks/setup-certificates.yml
```

**Good** (pre-install certificate generation):
```bash
# ✅ Certificates generated first
ansible-playbook playbooks/setup-certificates.yml \
  -e certificate_mode=selfsigned

# ✅ Mirror-registry uses generated certificates
ansible-playbook playbooks/setup-mirror-registry.yml
```

### Auto-Detect Certificate Mode

Use inventory defaults to auto-detect:

```yaml
# inventory/ibm-cloud.yml
all:
  vars:
    # Auto-detect: Uses letsencrypt if ~/.aws/credentials exists, else selfsigned
    certificate_mode: "{{ 'letsencrypt' if lookup('file', '~/.aws/credentials', errors='ignore') else 'selfsigned' }}"
```

Now `playbooks/site.yml` automatically chooses correct mode.

### Validate Before Full Deployment

Run preflight check:

```bash
ansible-playbook playbooks/site.yml \
  --tags validate \
  -e certificate_mode=selfsigned
```

This validates:
- ✅ Certificate files exist
- ✅ Certificate not expired
- ✅ Certificate matches hostname
- ✅ CA trust chain valid

---

## Verification

### Check Certificate Details

```bash
# View certificate on registry
openssl s_client -connect registry.example.com:8443 \
  -showcerts < /dev/null 2>&1 | \
  openssl x509 -noout -text | grep -E "Issuer|Subject|Not After"
```

**Self-signed** output:
```
Issuer: CN = quay-rootCA
Subject: CN = registry.example.com
Not After : Jun  4 10:00:00 2036 GMT
```

**Let's Encrypt** output:
```
Issuer: C = US, O = Let's Encrypt, CN = R3
Subject: CN = registry.example.com
Not After : Sep  2 10:00:00 2026 GMT
```

### Test from Multiple Clients

```bash
# Test from hypervisor (where mirror-registry was deployed)
podman login registry.example.com:8443

# Test from different machine (requires CA distribution for self-signed)
ssh user@workstation "podman login registry.example.com:8443"
```

---

## CA Distribution Strategies

### For Disconnected Environments

**Manual distribution**:
```bash
# Copy CA to all clients
for host in client1 client2 client3; do
  scp /tmp/quay-rootCA.pem $host:/tmp/
  ssh $host "sudo cp /tmp/quay-rootCA.pem /etc/pki/ca-trust/source/anchors/ && \
             sudo update-ca-trust extract"
done
```

**Ansible automation**:
```yaml
# playbooks/distribute-ca.yml
- hosts: openshift_nodes
  tasks:
    - name: Copy CA certificate
      copy:
        src: /tmp/quay-rootCA.pem
        dest: /etc/pki/ca-trust/source/anchors/quay-rootCA.pem
      
    - name: Update CA trust
      command: update-ca-trust extract
```

### For OpenShift Clusters

Add CA to cluster during installation:

```yaml
# install-config.yaml
additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  MIIDXTCCAkWgAwIBAgIJAKZ... (quay-rootCA contents)
  -----END CERTIFICATE-----
```

Or post-installation:

```bash
oc create configmap registry-cas \
  --from-file=registry.example.com..8443=/tmp/quay-rootCA.pem \
  -n openshift-config

oc patch image.config.openshift.io/cluster \
  --type=merge \
  -p '{"spec":{"additionalTrustedCA":{"name":"registry-cas"}}}'
```

---

## Advanced: Dual Certificate Strategy

For mixed environments (some clients have Let's Encrypt, some need self-signed):

1. Deploy Let's Encrypt for public access
2. Keep self-signed CA for disconnected clients
3. Configure HAProxy SNI routing:
   - External DNS → Let's Encrypt certificate
   - Internal IP → Self-signed certificate

**Configuration**:
```yaml
# extra_vars/registry-dual-cert.yml
certificate_mode: dual
letsencrypt_domain: registry.example.com
selfsigned_domain: registry.internal.example.com
```

---

## Related Documentation

- [ADR-0016: Trusted Certificate Management](../adrs/0016-trusted-certificate-management.md)
- [ADR-0017: Quay Mirror Registry](../adrs/0017-quay-mirror-registry.md)
- [Hardening Report: Registry TLS Auth Failure (v1.0)](../hardening/registry-tls-auth-failure-v1.0-2026-06-04.md)
- [Certificate Management Decisions](../explanations/certificate-management-decisions.md)
