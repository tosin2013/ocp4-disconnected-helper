# Registry Passthrough Mode Guide

This guide covers the implementation and usage of Registry Passthrough Mode for disconnected OpenShift deployments, as defined in [ADR 0020](adrs/0020-registry-passthrough-mode.md).

## Overview

Registry Passthrough Mode enables transparent container image access where workloads reference upstream registries (e.g., `quay.io`, `registry.redhat.io`) but actually pull from a local registry. This is achieved through:

1. **Tarfile-based distribution** - Images distributed as tar archives for air-gapped transfer
2. **Local registry mirroring** - Quay, Harbor, mirror-registry, or JFrog
3. **ICSP-based redirection** - OpenShift ImageContentSourcePolicy handles transparent redirection

## Supported Registries

| Registry | Auth Task | Mirror Repo Task |
|----------|-----------|------------------|
| mirror-registry | `setup-mirror-registry-auth.yml` | `create-mirror-repo-mirror-registry.yml` |
| Harbor | `setup-harbor-auth.yml` | `create-mirror-repo-harbor.yml` |
| Quay | `setup-quay-auth.yml` | `create-mirror-repo-quay.yml` |
| JFrog | `setup-jfrog-auth.yml` | `create-mirror-repo-jfrog.yml` |

## Quick Start

### 1. Configure Variables

Copy and customize the example variables:

```bash
cp extra_vars/passthrough-example.yml extra_vars/passthrough-vars.yml
```

Edit `passthrough-vars.yml`:

```yaml
registry_type: "mirror-registry"  # or harbor, quay, jfrog
registry_local_uri: "registry.disconnected.local"
registry_local_port: "8443"
```

### 2. Run Setup Playbook

```bash
cd /root/ocp4-disconnected-helper/playbooks

ansible-playbook -i inventory setup-registry-passthrough.yml \
    -e @../extra_vars/passthrough-vars.yml
```

### 3. Apply ICSP to Cluster

After setup, apply the generated ICSP:

```bash
/opt/ocp4-disconnected-helper/templates/icsp/apply-icsp-mirror-registry.sh
```

### 4. Validate Configuration

```bash
ansible-playbook -i inventory validate-passthrough-mode.yml \
    -e @../extra_vars/passthrough-vars.yml
```

## Registry Mirror Configuration

Based on [Red Hat Solution 2998411](https://access.redhat.com/solutions/2998411), the following registries are configured by default:

### Core Registries (Highest Priority)
- `registry.access.redhat.com` - Red Hat Access Registry
- `registry.redhat.io` - Red Hat Container Registry
- `registry.connect.redhat.com` - Red Hat Connect Registry (third-party)

### High Priority Registries
- `quay.io` - Quay Container Registry
- `cdn.quay.io` - Quay CDN
- `docker.io` - Docker Hub
- `storage.googleapis.com/openshift-release` - OpenShift Release Storage

### Medium Priority (Optional)
- `sso.redhat.com` - Red Hat SSO
- `github.com` - GitHub Container Registry
- `gitlab.com` - GitLab Container Registry

## Naming Convention

All mirrored images follow the pattern:

```
<local-registry>/mirror/<upstream-registry>/<image-path>:<tag>
```

Examples:
- `registry.local:8443/mirror/quay.io/centos/centos:stream8`
- `registry.local:8443/mirror/registry.redhat.io/rhel8/httpd-24:latest`

## Airflow Integration

The `ocp_registry_sync` DAG supports passthrough mode:

```bash
# Trigger with passthrough enabled
airflow dags trigger ocp_registry_sync \
    --conf '{"target_registry": "mirror-registry", "enable_passthrough": true}'
```

## Troubleshooting

### Registry Not Accessible

```bash
# Test registry health
curl -k https://registry.disconnected.local:8443/health

# Test catalog access
curl -k https://registry.disconnected.local:8443/v2/_catalog
```

### ICSP Not Working

```bash
# Check ICSP policies
oc get imagecontentsourcepolicy

# Verify Machine Config Operator status
oc get mcp
```

### Authentication Issues

Check the generated auth config:

```bash
cat /opt/ocp4-disconnected-helper/templates/icsp/*-auth-config.json
```

## Related Documentation

- [ADR 0003: oc-mirror v2](adrs/0003-oc-mirror-image-mirroring.md)
- [ADR 0004: Dual Registry Support](adrs/0004-dual-registry-support.md)
- [ADR 0017: Quay Mirror Registry](adrs/0017-quay-mirror-registry.md)
- [ADR 0020: Registry Passthrough Mode](adrs/0020-registry-passthrough-mode.md)
