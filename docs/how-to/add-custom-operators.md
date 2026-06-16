# How to Add Custom Operators

Create custom operator presets beyond the 8 curated bundles for specialized workloads.

---

## When to Create Custom Presets

**Use curated presets** if operators exist in:
- storage-operators (ODF, local-storage, NFS, Hostpath)
- networking-operators (Multus, SR-IOV, MetalLB)
- observability-operators (Prometheus, Grafana, Loki)
- security-operators (ACS, Compliance, Cert Manager)
- virtualization-operators (CNV, CDI, HPP)
- service-mesh-operators (Istio, Kiali, Jaeger)
- openshift-ai-operators (RHOAI, ODH)
- rhacm-operators (RHACM, Submariner)

**Create custom preset** if:
- ✅ You need operators from multiple categories
- ✅ You need ISV operators not in curated presets
- ✅ You need specific operator versions
- ✅ You want a minimal subset for testing

---

## Step 1: Discover Available Operators

### Option A: Use Discovery Tool (Recommended)

```bash
# Search by keyword
./scripts/discover-operators.sh --search storage

# List all operators in a catalog
./scripts/discover-operators.sh --catalog redhat-operator-index

# Get operator details
./scripts/discover-operators.sh --operator local-storage-operator
```

**Output**:
```
=== Search Results: storage ===

1. local-storage-operator (redhat-operator-index)
   Description: Provides local storage using hostPath volumes
   Channels: stable, preview
   Latest: v4.21.0

2. odf-operator (redhat-operator-index)
   Description: OpenShift Data Foundation
   Channels: stable-4.21
   Latest: v4.21.3

... (more results)
```

### Option B: Query Catalog Directly

```bash
# Extract operator names from catalog
oc-mirror list operators --catalog registry.redhat.io/redhat/redhat-operator-index:v4.21 | \
  grep -i database
```

**Common catalogs**:
- `registry.redhat.io/redhat/redhat-operator-index:v4.21` - Red Hat operators
- `registry.redhat.io/redhat/certified-operator-index:v4.21` - ISV certified
- `registry.redhat.io/redhat/community-operator-index:v4.21` - Community operators

---

## Step 2: Create Custom Preset File

### Template Structure

```yaml
# extra_vars/operators/my-custom-preset.yml
---
operator_preset_name: "my-custom-preset"

operators:
  - name: operator-name
    catalog: redhat-operator-index
    channels:
      - name: stable
        minVersion: "v1.0.0"  # Optional: specific version
        maxVersion: "v1.5.0"  # Optional: version range

  - name: another-operator
    catalog: certified-operator-index
    # No channels = mirror all channels and versions
```

### Example: Database Operators Preset

```yaml
# extra_vars/operators/database-operators.yml
---
operator_preset_name: "database-operators"

operators:
  # PostgreSQL
  - name: postgresql-operator
    catalog: redhat-operator-index
    channels:
      - name: stable

  # MongoDB
  - name: mongodb-enterprise
    catalog: certified-operator-index
    channels:
      - name: stable

  # Redis
  - name: redis-operator
    catalog: redhat-operator-index
    channels:
      - name: stable

  # MySQL
  - name: mysql-operator
    catalog: certified-operator-index
    channels:
      - name: stable-8.0

  # CockroachDB
  - name: cockroachdb-certified
    catalog: certified-operator-index
```

### Example: Minimal Testing Preset

```yaml
# extra_vars/operators/minimal-test.yml
---
operator_preset_name: "minimal-test"

operators:
  # Just one operator for quick testing
  - name: local-storage-operator
    catalog: redhat-operator-index
    channels:
      - name: stable
        minVersion: "v4.21.0"
```

---

## Step 3: Validate Custom Preset

**Always validate before mirroring** - catches typos and saves bandwidth.

```bash
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/my-custom-preset.yml
```

**Success output**:
```
TASK [Validate operator: operator-name] ******************************
ok: [localhost] => {
    "msg": "✓ operator-name exists in redhat-operator-index"
}

PLAY RECAP ************************************************************
localhost                  : ok=3    changed=0    failed=0
```

**Failure with suggestions**:
```
TASK [Validate operator: odf-operato] ********************************
fatal: [localhost]: FAILED! => {
    "msg": "✗ Operator 'odf-operato' not found in redhat-operator-index\n
            Did you mean:\n
              - odf-operator (99% match)\n
              - ocs-operator (85% match)"
}
```

**Fix typos and re-validate until all operators pass.**

---

## Step 4: Mirror Custom Preset

### Via AAP Workflow 2

1. **Add preset to survey choices**:
   ```bash
   # Edit workflow configuration
   vim playbooks/aap-configuration/configure-mirroring-workflow.yml
   
   # Add to survey_spec.spec[0].choices:
   - my-custom-preset
   ```

2. **Re-deploy workflow configuration**:
   ```bash
   ansible-playbook playbooks/aap-configuration/configure-mirroring-workflow.yml
   ```

3. **Launch workflow** and select custom preset from dropdown

### Via Direct Playbook Execution

```bash
# Download to disk
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/operators/my-custom-preset.yml

# Push to registry
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e @extra_vars/operators/my-custom-preset.yml \
  -e target_registry=registry.example.com:8443
```

---

## Advanced: Version Pinning

### Pin to Specific Version

```yaml
operators:
  - name: odf-operator
    catalog: redhat-operator-index
    channels:
      - name: stable-4.21
        minVersion: "v4.21.3"
        maxVersion: "v4.21.3"  # Exact version
```

### Pin to Version Range

```yaml
operators:
  - name: openshift-gitops-operator
    catalog: redhat-operator-index
    channels:
      - name: stable
        minVersion: "v1.8.0"
        maxVersion: "v1.10.0"  # All versions 1.8.x - 1.10.x
```

### Mirror All Versions (Default)

```yaml
operators:
  - name: serverless-operator
    catalog: redhat-operator-index
    # No version constraints = mirror all versions
```

---

## Advanced: Multi-Catalog Operators

### Mix Operators from Different Catalogs

```yaml
# extra_vars/operators/mixed-catalog-preset.yml
---
operator_preset_name: "mixed-catalog-preset"

operators:
  # Red Hat catalog
  - name: compliance-operator
    catalog: redhat-operator-index

  # Certified catalog (ISV)
  - name: dynatrace-operator
    catalog: certified-operator-index

  # Community catalog
  - name: strimzi-kafka-operator
    catalog: community-operator-index
```

**Validation**: Each operator is validated against its specified catalog.

---

## Advanced: Custom Catalog Sources

### Use Custom or Partner Catalogs

```yaml
operators:
  - name: my-custom-operator
    catalog: custom-operator-index:v1.0
    catalogSource: my-custom-catalog  # Custom CatalogSource name
```

**Prerequisites**:
1. Custom catalog must be accessible during mirroring
2. Add catalog to ImageSetConfiguration in `playbooks/download-to-disk-v2.yml`

---

## Troubleshooting

### "Operator not found in catalog"

**Cause**: Typo in operator name or wrong catalog

**Solution**:
```bash
# Search for correct name
./scripts/discover-operators.sh --search <partial-name>

# Validate preset
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/my-custom-preset.yml
```

### "Channel not found for operator"

**Cause**: Channel name doesn't exist for this operator

**Solution**:
```bash
# List available channels
./scripts/discover-operators.sh --operator <operator-name>

# Update preset with correct channel name
```

### Mirroring Takes Too Long

**Cause**: Too many operators or too many versions

**Solution**: Use version constraints to reduce image count:
```yaml
channels:
  - name: stable
    minVersion: "v4.21.0"  # Skip old versions
```

### Disk Space Exhausted

**Cause**: Download directory full

**Solution**:
```bash
# Check space
df -h /data

# Clean old downloads
rm -rf /data/oc-mirror/mirror-seq*

# Use smaller operator subset
```

---

## Preset Maintenance

### Update Preset for New OpenShift Version

When upgrading from OCP 4.21 → 4.22:

```yaml
operators:
  - name: odf-operator
    catalog: redhat-operator-index
    channels:
      - name: stable-4.22  # Update channel for new OCP version
        minVersion: "v4.22.0"
```

### Remove Deprecated Operators

```yaml
# Before (OCP 4.20)
operators:
  - name: ocs-operator  # Deprecated in 4.21
    catalog: redhat-operator-index

# After (OCP 4.21)
operators:
  - name: odf-operator  # Replaced ocs-operator
    catalog: redhat-operator-index
```

---

## Best Practices

1. **Name presets descriptively**: `database-operators`, not `preset-1`
2. **Always validate before mirroring**: Catches 90% of errors in 10 seconds
3. **Use version constraints**: Reduces download size and time
4. **Document operator purpose**: Add comments in preset file
5. **Test with minimal preset first**: Verify workflow before large mirrors
6. **Keep presets in version control**: Track changes over time
7. **Use discovery tool**: Don't guess operator names
8. **Pin production versions**: Avoid unexpected upgrades

---

## Preset Template Generator

Use this generator for quick preset creation:

```bash
# Generate template
cat > extra_vars/operators/my-preset.yml << 'EOF'
---
operator_preset_name: "my-preset"

operators:
  - name: operator-1
    catalog: redhat-operator-index
    channels:
      - name: stable

  - name: operator-2
    catalog: certified-operator-index
    channels:
      - name: stable
EOF

# Validate
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/my-preset.yml
```

---

## Related Documentation

- [Operator Validation Framework](../explanations/operator-validation-framework.md)
- [Workflow Survey Parameters](../reference/workflow-survey-parameters.md)
- [Deploy Workflow 2](deploy-workflow-2-image-mirroring.md)
- [ADR-0034: Operator Catalog Validation Framework](../adrs/adr-0034-operator-catalog-validation-framework.md)
