# Operator Catalog Presets

This directory contains curated operator selection presets for common use cases in disconnected OpenShift deployments.

## Available Presets

### Storage Operators (`storage-operators.yml`)
Persistent storage management operators:
- **local-storage-operator**: Local disk management
- **odf-operator**: OpenShift Data Foundation (Ceph-based)
- **lvms-operator**: Logical Volume Manager Storage
- **ocs-operator**: OpenShift Container Storage (legacy ODF)
- **portworx-certified**: Enterprise storage platform (certified)

### Observability Operators (`observability-operators.yml`)
Monitoring, logging, and alerting operators:
- **cluster-logging**: Log collection and forwarding
- **loki-operator**: Log aggregation
- **cluster-observability-operator**: Observability framework
- **netobserv-operator**: Network flow monitoring

### Networking Operators (`networking-operators.yml`)
Network infrastructure and security operators:
- **metallb-operator**: Load balancer for bare metal
- **kubernetes-nmstate-operator**: Network state management
- **sriov-network-operator**: SR-IOV network device plugin
- **local-dns-operator**: CoreDNS configuration

## Usage

### 1. Validate Operators Before Mirroring

Always validate operator selections to catch typos and invalid configurations:

```bash
# Validate storage operators
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml

# Validate observability operators
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/observability-operators.yml
```

### 2. Mirror Validated Operators

After successful validation, proceed with mirroring:

```bash
# Mirror storage operators (Phase 1: Download to disk)
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/operators/storage-operators.yml

# Mirror storage operators (Phase 2: Push to registry)
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e @extra_vars/operators/storage-operators.yml
```

### 3. Combine Multiple Presets

Create custom configurations by combining multiple presets:

```yaml
---
# custom-operators.yml
openshift_releases:
  - name: stable-4.21
    minVersion: 4.21.0
    maxVersion: 4.21.0
    shortestPath: true

operators:
  # Storage operators
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
    packages:
      - name: local-storage-operator
        channels:
          - name: stable
      - name: odf-operator
        channels:
          - name: stable-4.21

  # Observability operators
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
    packages:
      - name: cluster-logging
        channels:
          - name: stable-6.1
      - name: loki-operator
        channels:
          - name: stable-6.1

target_mirror_path: "/data/ocp-mirror"
target_registry: "registry.ocp4.sandbox3377.opentlc.com:8443"
target_namespace: "openshift4"
```

## Discovery Tool

Use the operator discovery CLI to search for additional operators:

```bash
# Search for storage-related operators
./scripts/discover-operators.sh --search storage

# Search certified catalog for monitoring operators
./scripts/discover-operators.sh --catalog certified --search monitoring

# List all community operators
./scripts/discover-operators.sh --catalog community --list-all

# Search with specific OpenShift version
./scripts/discover-operators.sh --search networking --version 4.20
```

The discovery tool outputs valid YAML snippets ready for copy-paste.

## Validation Framework

### Pre-flight Validation

The validation framework checks:
- ✅ Operator names exist in catalog
- ✅ Channels are valid for the specified operator
- ✅ Catalogs are accessible and cached
- ✅ Typo detection with suggestions (fuzzy matching)

### Error Messages

Example validation output:

```
❌ VALIDATION FAILED

Invalid operators in redhat-operator-index:v4.21:
  • local-storage          → Did you mean: local-storage-operator?
  • gitops                 → Did you mean: openshift-gitops-operator?

Channel not found:
  • ocs-operator:stable-4.22 → Available channels: stable-4.21, stable-4.20

✅ Valid operators (8):
  • metallb-operator:stable
  • lvms-operator:stable-4.21
  • kubevirt-hyperconverged:stable
  ...
```

## Best Practices

1. **Always validate first**: Run validation before starting expensive mirror operations
2. **Use presets as starting points**: Copy and modify for your specific needs
3. **Keep OpenShift version consistent**: Match operator catalog version to OCP release
4. **Cache management**: Validation caches catalogs (TTL: 24 hours) for fast repeated checks
5. **Offline scenarios**: Use `force_refresh=false` in air-gapped environments with pre-cached catalogs

## Catalog Structure

Operators are organized by catalog type:

- **Red Hat Operators** (`redhat-operator-index`): Supported by Red Hat
- **Certified Operators** (`certified-operator-index`): Certified by partners
- **Community Operators** (`community-operator-index`): Community-maintained

## Related Documentation

- [ADR-0034: Operator Catalog Validation Framework](../../docs/adrs/adr-0034-operator-catalog-validation-framework.md)
- [ADR-0003: oc-mirror v2 for Image Mirroring](../../docs/adrs/adr-0003-oc-mirror-v2-for-image-mirroring.md)
- [OpenShift Disconnected Installation Guide](https://docs.openshift.com/container-platform/4.21/installing/disconnected_install/)
- [Red Hat Operator Catalog](https://catalog.redhat.com/software/operators/search)

## Troubleshooting

### Cache Issues

```bash
# Force refresh operator catalog cache
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e "force_refresh=true"

# Clear cache manually
sudo rm -rf /var/cache/oc-mirror/catalogs/*
```

### Validation Failures

```bash
# Non-strict mode (warnings only, no failure)
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e "operator_validation_strict=false"

# Disable channel validation
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml \
  -e "operator_validation_check_channels=false"
```

### Discovery Tool Issues

```bash
# Use custom pull secret location
./scripts/discover-operators.sh --search storage \
  --pull-secret /path/to/pull-secret.json

# Use custom cache directory
./scripts/discover-operators.sh --search logging \
  --cache-dir /tmp/operator-cache
```
