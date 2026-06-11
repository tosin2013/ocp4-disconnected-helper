# Operator Validation Framework - Quick Start Guide

**Status**: ✅ Implemented (ADR-0034)  
**Date**: 2026-06-11

---

## What Problem Does This Solve?

Previously, operator typos and invalid configurations only surfaced 10-30 minutes into expensive oc-mirror operations, wasting time and bandwidth.

**Example Old Failure**:
```yaml
operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
    packages:
      - name: local-storage  # ❌ TYPO - should be "local-storage-operator"

# Error appears 10 minutes later:
# [ERROR] package local-storage not found in catalog
```

**Now**: Validation catches this in <30 seconds with helpful suggestions.

---

## Quick Start (3 Steps)

### Step 1: Discover Operators

Use the discovery tool to browse available operators:

```bash
# Search for storage operators
./scripts/discover-operators.sh --search storage

# Search certified catalog for monitoring
./scripts/discover-operators.sh --catalog certified --search monitoring

# List all operators in a catalog
./scripts/discover-operators.sh --catalog redhat --list-all
```

**Output**: Valid YAML snippets ready for copy-paste.

### Step 2: Validate Before Mirroring

Always validate operator selections before expensive mirroring:

```bash
# Validate using curated preset
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml

# Validate custom configuration
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/my-operators.yml

# Force refresh catalog cache
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e "force_refresh=true"
```

**Validation Output Example**:

```
❌ VALIDATION FAILED

Invalid operators in redhat-operator-index:v4.21:
  • local-storage          → Did you mean: local-storage-operator?
  • gitops                 → Did you mean: openshift-gitops-operator?

Channel not found:
  • ocs-operator:stable-4.22 → Available channels: stable-4.21, stable-4.20

✅ Valid operators (5):
  • metallb-operator:stable
  • lvms-operator:stable-4.21
  • loki-operator:stable-6.1
  ...
```

### Step 3: Mirror (After Successful Validation)

Once validation passes, proceed with mirroring:

```bash
# Phase 1: Download to disk
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/operators/storage-operators.yml

# Phase 2: Push to registry
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e @extra_vars/operators/storage-operators.yml
```

---

## Curated Operator Presets

Pre-configured operator bundles for common use cases:

### Storage Operators
**File**: `extra_vars/operators/storage-operators.yml`

Includes:
- local-storage-operator (local disk management)
- odf-operator (Ceph-based distributed storage)
- lvms-operator (LVM-based storage)
- ocs-operator (legacy ODF)
- portworx-certified (enterprise storage)

### Observability Operators
**File**: `extra_vars/operators/observability-operators.yml`

Includes:
- cluster-logging (log collection)
- loki-operator (log aggregation)
- cluster-observability-operator (metrics framework)
- netobserv-operator (network flow monitoring)

### Custom Operators
Create your own by combining presets or using discovery tool output:

```yaml
---
# custom-operators.yml
openshift_releases:
  - name: stable-4.21
    minVersion: 4.21.0
    maxVersion: 4.21.0
    shortestPath: true

operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
    packages:
      - name: local-storage-operator
        channels:
          - name: stable
      - name: cluster-logging
        channels:
          - name: stable-6.1

target_mirror_path: "/data/ocp-mirror"
target_registry: "registry.ocp4.sandbox3377.opentlc.com:8443"
target_namespace: "openshift4"
```

---

## AAP Workflow Integration

The validation playbook integrates as a preflight node in AAP workflows:

```
Workflow: "Deploy Disconnected OpenShift Infrastructure"
  ├─► Node 1: Validate Operator Selection          ← NEW
  │   └─► On Failure: Stop workflow
  │
  ├─► Node 2: Download OpenShift Images (Phase 1)
  └─► Node 3: Mirror Images to Registry (Phase 2)
```

**Benefits**:
- Catches errors before expensive operations start
- Prevents wasted bandwidth in air-gapped environments
- Provides immediate feedback to users

---

## Advanced Usage

### Cache Management

Validation caches operator catalog metadata for fast repeated checks:

```bash
# Check cache age
ls -lh /var/cache/oc-mirror/catalogs/

# Force refresh (ignores 24h TTL)
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e "force_refresh=true"

# Clear cache manually
sudo rm -rf /var/cache/oc-mirror/catalogs/*
```

**Cache Details**:
- **Location**: `/var/cache/oc-mirror/catalogs/`
- **TTL**: 24 hours (configurable)
- **Size**: ~5-10MB per catalog
- **Source**: `oc mirror list operators --catalog=<url>`

### Non-Strict Validation

Run validation as warnings-only (no failure):

```bash
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e "operator_validation_strict=false"
```

### Offline/Air-Gapped Mode

For disconnected environments, pre-cache catalogs before going offline:

```bash
# On connected system: cache catalogs
ansible-playbook playbooks/validate-operator-selection.yml \
  -e "force_refresh=true" \
  -e "openshift_version=4.21"

# Transfer cache to air-gapped system
tar czf operator-cache.tar.gz /var/cache/oc-mirror/catalogs/

# On air-gapped system: extract and validate
tar xzf operator-cache.tar.gz -C /
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e "force_refresh=false"
```

---

## Architecture Components

### operator_catalog Role (ADR-0024 Atomic Pattern)

**Tasks**:
- `cache-catalog-metadata.yml`: Download and cache catalog listings
- `validate-operators.yml`: Validate against cached data
- `validate-operator-catalog.yml`: Per-catalog validation logic

**Variables** (defaults/main.yml):
```yaml
operator_catalog_cache_dir: "/var/cache/oc-mirror/catalogs"
operator_catalog_cache_ttl_hours: 24
operator_validation_strict: true
operator_validation_suggest_typos: true
operator_validation_check_channels: true
```

### Discovery Tool (Bash Script)

**Features**:
- Search catalogs by keyword
- Display available channels
- Generate valid YAML snippets
- Support for Red Hat, Certified, Community catalogs

**Example**:
```bash
./scripts/discover-operators.sh --search storage

# Output:
# ────────────────────────────────────────
# Operator: local-storage-operator
# Default Channel: stable
# Available Channels (1):
#   • stable (default)
# 
# YAML Snippet (copy-paste):
#   - name: local-storage-operator
#     channels:
#       - name: stable
```

---

## Testing

### Test Validation File

`extra_vars/operators/test-validation.yml` demonstrates error detection:

```yaml
operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
    packages:
      # ✅ VALID
      - name: local-storage-operator
        channels:
          - name: stable

      # ❌ INVALID - Typo
      - name: local-storage

      # ❌ INVALID - Wrong channel
      - name: ocs-operator
        channels:
          - name: stable-4.22  # Should be stable-4.21
```

Run test:
```bash
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/test-validation.yml
```

Expected: Validation fails with actionable error messages.

---

## Success Metrics

- **Error Detection Time**: <30 seconds (vs 10+ minutes previously)
- **False Positive Rate**: <5% (typo suggestions are accurate)
- **Bandwidth Savings**: Prevents partial downloads of invalid configs
- **User Satisfaction**: Clear error messages reduce support tickets

---

## Related Documentation

- [ADR-0034: Operator Catalog Validation Framework](adrs/adr-0034-operator-catalog-validation-framework.md)
- [ADR-0003: oc-mirror v2 for Image Mirroring](adrs/adr-0003-oc-mirror-v2-for-image-mirroring.md)
- [ADR-0024: Roles and Collections Architecture](adrs/adr-0024-roles-and-collections-architecture.md)
- [Operator Presets README](../extra_vars/operators/README.md)
- [OpenShift Operator Catalog](https://catalog.redhat.com/software/operators/search)

---

## Troubleshooting

### "Cache not found" Error

```bash
# First run needs cache download
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e "force_refresh=true"
```

### "oc-mirror not found" Error

```bash
# Install oc-mirror
ansible-playbook playbooks/download-to-disk-v2.yml --tags install
```

### "Pull secret not found" Error

```bash
# Download pull secret
# Visit: https://console.redhat.com/openshift/install/pull-secret
# Save to: ~/pull-secret.json
```

### Stale Cache Warnings

Cache is refreshed automatically after 24 hours. To force immediate refresh:

```bash
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e "force_refresh=true"
```

---

## Next Steps

1. **Try Discovery Tool**: `./scripts/discover-operators.sh --search <keyword>`
2. **Validate Preset**: `ansible-playbook playbooks/validate-operator-selection.yml -e @extra_vars/operators/storage-operators.yml`
3. **Create Custom Config**: Copy preset and modify for your needs
4. **Integrate with AAP**: Add validation as preflight workflow node

For questions or issues, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md) or open a GitHub issue.
