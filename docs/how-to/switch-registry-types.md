# How to Switch Registry Types

Migrate from one container registry type (Quay/Harbor/JFrog) to another without losing mirrored images.

---

## Supported Registry Types

| Registry | Production Ready | OpenShift Integration | License |
|----------|------------------|----------------------|---------|
| **Quay** (mirror-registry v2) | ✅ | Excellent (Red Hat) | Free (up to 10 users) |
| **Harbor** | ✅ | Good (CNCF) | Open Source (Apache 2.0) |
| **JFrog Artifactory** | ✅ | Good (Enterprise) | Commercial + Free tier |

**Recommendation**: Use **Quay mirror-registry** for official Red Hat support and seamless OpenShift integration.

---

## Migration Scenarios

### Scenario 1: Switch Before Mirroring (Clean Slate)

**When**: Registry deployed but no images mirrored yet

**Effort**: Low (10-15 minutes)  
**Downtime**: None  
**Data Loss**: None

### Scenario 2: Switch After Mirroring (Re-mirror Required)

**When**: Images already mirrored, need different registry

**Effort**: High (1-8 hours depending on image count)  
**Downtime**: Yes (until re-mirror complete)  
**Data Loss**: None (images re-mirrored from TAR archives)

### Scenario 3: Coexistence (Dual Registry)

**When**: Need both registries for different purposes

**Effort**: Medium (30-45 minutes)  
**Downtime**: None  
**Data Loss**: None

---

## Scenario 1: Switch Before Mirroring

### Step 1: Destroy Existing Registry

```bash
# Stop and remove current registry
ansible-playbook playbooks/destroy-registry.yml \
  -e registry_type=quay \
  -e confirm_destroy=yes
```

**What this does**:
- Stops registry containers/services
- Removes registry data directories
- Cleans up systemd units
- Preserves VM (only removes registry software)

### Step 2: Deploy New Registry Type

```bash
# Via Workflow 1 (AAP)
# Launch workflow and select new registry_type from survey

# Via direct playbook
ansible-playbook playbooks/setup-mirror-registry.yml \
  -e registry_type=harbor
```

**Registry-specific steps**:

**Quay**:
```bash
ansible-playbook playbooks/setup-mirror-registry.yml \
  -e registry_type=quay \
  -e @extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Harbor**:
```bash
ansible-playbook playbooks/setup-harbor-registry.yml \
  -e registry_type=harbor
```

**JFrog**:
```bash
ansible-playbook playbooks/setup-jfrog-registry.yml \
  -e registry_type=jfrog
```

### Step 3: Verify New Registry

```bash
# Test health endpoint
curl -k https://registry.example.com:8443/health/instance

# Test authentication
echo "$PASSWORD" | podman login --username init \
  --password-stdin registry.example.com:8443
```

### Step 4: Proceed with Mirroring

```bash
# Run Workflow 2 as normal
# Images will push to new registry type
```

**Total time**: 10-15 minutes (no re-mirror needed)

---

## Scenario 2: Switch After Mirroring

### Step 1: Backup TAR Archives

**Critical**: Verify TAR archives exist before destroying registry

```bash
# List TAR archives
ls -lh /data/oc-mirror/mirror-seq*/mirror_seq*_*.tar

# Expected: One or more .tar files with mirrored images
```

**If TAR archives missing**:
```bash
# Re-download images (required if TARs deleted)
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/operators/storage-operators.yml
```

### Step 2: Destroy Old Registry

```bash
ansible-playbook playbooks/destroy-registry.yml \
  -e registry_type=quay \
  -e confirm_destroy=yes
```

### Step 3: Deploy New Registry

```bash
ansible-playbook playbooks/setup-harbor-registry.yml \
  -e registry_type=harbor
```

### Step 4: Re-Push Images from TAR

```bash
# Push all TAR archives to new registry
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e target_registry=registry.example.com:8443 \
  -e source_tar_dir=/data/oc-mirror/mirror-seq1
```

**Time estimate**:
- Storage operators (8 operators): ~20-30 minutes
- Observability operators (7 operators): ~15-25 minutes
- OpenShift AI (9 operators): ~45-60 minutes
- All operators: ~2-4 hours

### Step 5: Update Pull Secrets

```bash
# Generate new pull secret for new registry
ansible-playbook playbooks/extract-pull-secret.yml \
  -e target_registry=registry.example.com:8443 \
  -e output_file=/tmp/new-pull-secret.json
```

### Step 6: Update OpenShift Clusters (If Already Deployed)

```bash
# Update global pull secret on cluster
oc set data secret/pull-secret -n openshift-config \
  --from-file=.dockerconfigjson=/tmp/new-pull-secret.json

# Restart nodes to pick up new pull secret (rolling restart)
oc adm drain <node-name> --ignore-daemonsets --delete-emptydir-data
oc adm uncordon <node-name>
```

**Total time**: 1-8 hours (depends on image count + cluster restart)

---

## Scenario 3: Coexistence (Dual Registry)

### Use Case: Different Registries for Different Purposes

Example:
- **Quay** for OpenShift operators
- **Harbor** for application container images
- **JFrog** for build artifacts

### Step 1: Deploy Second Registry on Different VM

```bash
# Provision second registry VM
ansible-playbook playbooks/provision-vm.yml \
  -e vm_name=harbor-registry \
  -e vm_ip=192.168.10.11 \
  -e vm_memory=16384 \
  -e vm_cpus=4

# Deploy Harbor on second VM
ansible-playbook playbooks/setup-harbor-registry.yml \
  -e registry_vm=harbor-registry \
  -e registry_fqdn=harbor.example.com
```

### Step 2: Configure HAProxy for Multi-Registry Routing

```yaml
# extra_vars/haproxy-multi-registry.yml
registries:
  - name: quay
    fqdn: quay.example.com
    backend: 192.168.10.10:8443
  
  - name: harbor
    fqdn: harbor.example.com
    backend: 192.168.10.11:8443
```

```bash
# Apply HAProxy configuration
ansible-playbook playbooks/setup-haproxy.yml \
  -e @extra_vars/haproxy-multi-registry.yml
```

### Step 3: Mirror Images to Appropriate Registry

```bash
# OpenShift operators → Quay
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e target_registry=quay.example.com:8443 \
  -e @extra_vars/operators/storage-operators.yml

# Application images → Harbor
skopeo copy --all \
  docker://my-app:v1.0 \
  docker://harbor.example.com/apps/my-app:v1.0
```

### Step 4: Configure Multi-Registry Pull Secrets

```json
// combined-pull-secret.json
{
  "auths": {
    "quay.example.com:8443": {
      "auth": "aW5pdDpwYXNzd29yZA==",
      "email": "admin@example.com"
    },
    "harbor.example.com:8443": {
      "auth": "YWRtaW46SGFyYm9yMTIzNDU=",
      "email": "admin@example.com"
    }
  }
}
```

**Total time**: 45-60 minutes (no re-mirror, additive)

---

## Registry-Specific Considerations

### Migrating FROM Quay

**Advantages of staying with Quay**:
- ✅ Red Hat support for OpenShift
- ✅ Simpler authentication (no LDAP required)
- ✅ Automatic garbage collection
- ✅ Built-in geo-replication

**Reasons to migrate**:
- ❌ Need advanced RBAC (Harbor better)
- ❌ Need vulnerability scanning (Harbor Trivy, JFrog Xray)
- ❌ Need artifact management beyond containers (JFrog)

### Migrating TO Harbor

**Migration benefits**:
- ✅ Built-in vulnerability scanning (Trivy)
- ✅ Advanced RBAC with projects and roles
- ✅ Replication to multiple registries
- ✅ Helm chart repository support

**Migration caveats**:
- ⚠️ Requires PostgreSQL database (Quay uses embedded)
- ⚠️ More complex authentication setup
- ⚠️ Larger resource footprint (4GB RAM minimum vs 2GB for Quay)

### Migrating TO JFrog Artifactory

**Migration benefits**:
- ✅ Universal artifact repository (containers, Maven, npm, PyPI, Helm)
- ✅ Advanced security scanning (Xray)
- ✅ Enterprise support and SLA
- ✅ Build integration (Jenkins, GitLab CI, etc.)

**Migration caveats**:
- ⚠️ Commercial license required for full features
- ⚠️ Higher resource requirements (8GB RAM recommended)
- ⚠️ More complex configuration

---

## Migration Automation

### Automated Registry Swap Script

```bash
#!/bin/bash
# scripts/swap-registry-type.sh

OLD_TYPE=$1
NEW_TYPE=$2

echo "=== Migrating from $OLD_TYPE to $NEW_TYPE ==="

# Step 1: Verify TAR archives exist
if [ ! -d /data/oc-mirror/mirror-seq1 ]; then
  echo "ERROR: TAR archives not found. Run download-to-disk-v2.yml first."
  exit 1
fi

# Step 2: Destroy old registry
ansible-playbook playbooks/destroy-registry.yml \
  -e registry_type=$OLD_TYPE \
  -e confirm_destroy=yes

# Step 3: Deploy new registry
ansible-playbook playbooks/setup-${NEW_TYPE}-registry.yml \
  -e registry_type=$NEW_TYPE

# Step 4: Re-push images
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e target_registry=registry.example.com:8443 \
  -e source_tar_dir=/data/oc-mirror/mirror-seq1

echo "=== Migration complete. Verify with: podman login registry.example.com:8443 ==="
```

**Usage**:
```bash
chmod +x scripts/swap-registry-type.sh
./scripts/swap-registry-type.sh quay harbor
```

---

## Rollback Procedure

### If New Registry Fails

```bash
# Step 1: Destroy failed new registry
ansible-playbook playbooks/destroy-registry.yml \
  -e registry_type=harbor \
  -e confirm_destroy=yes

# Step 2: Re-deploy old registry type
ansible-playbook playbooks/setup-mirror-registry.yml \
  -e registry_type=quay

# Step 3: Re-push images from TAR
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e target_registry=registry.example.com:8443 \
  -e source_tar_dir=/data/oc-mirror/mirror-seq1
```

---

## Verification Checklist

After migration, verify:

- [ ] Registry health endpoint responds: `curl -k https://registry.example.com:8443/health/instance`
- [ ] Authentication works: `podman login registry.example.com:8443`
- [ ] Image count matches: `curl -sk https://registry.example.com:8443/v2/_catalog | jq '.repositories | length'`
- [ ] Pull secret works: `oc create -f /tmp/new-pull-secret.json --dry-run=client`
- [ ] Test image pull: `podman pull registry.example.com:8443/openshift/release:4.21.0-x86_64`

---

## Troubleshooting

### "Authentication failed" After Migration

**Cause**: Old credentials cached

**Solution**:
```bash
# Remove old credentials
rm -f ~/.docker/config.json
podman logout registry.example.com:8443

# Re-authenticate
echo "$NEW_PASSWORD" | podman login --username $NEW_USERNAME \
  --password-stdin registry.example.com:8443
```

### Image Count Mismatch

**Cause**: Partial push or TAR corruption

**Solution**:
```bash
# Re-push specific TAR archive
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e target_registry=registry.example.com:8443 \
  -e source_tar=/data/oc-mirror/mirror-seq1/mirror_seq1_000000.tar
```

### Registry Slow After Migration

**Cause**: New registry type has higher resource requirements

**Solution**: Increase VM resources:
```bash
virsh setmem registry 16384M --config
virsh setvcpus registry 4 --config --maximum
virsh reboot registry
```

---

## Related Documentation

- [Deploy Workflow 1](deploy-workflow-1-registry-infrastructure.md)
- [ADR-0004: Dual Registry Support](../adrs/0004-dual-registry-support.md)
- [ADR-0017: Quay Mirror Registry](../adrs/0017-quay-mirror-registry.md)
- [Workflow Survey Parameters](../reference/workflow-survey-parameters.md)
