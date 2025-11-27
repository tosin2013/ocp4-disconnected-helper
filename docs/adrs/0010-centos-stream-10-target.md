# ADR 0010: CentOS Stream 10 as Target Platform

**Status:** Accepted  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 7.1 - Target Environment

## Context

The ocp4-disconnected-helper automation needs a stable, enterprise-aligned Linux distribution for:
- Running oc-mirror and appliance builder tools
- Hosting local container registries
- Executing Ansible playbooks
- Long-term support and security updates

## Decision

Target **CentOS Stream 10** as the primary operating system for all automation hosts.

### Alignment with Stack
- **qubinode_navigator**: Already supports CentOS Stream 10 via RHEL 10 plugin
- **kcli-pipelines**: Compatible with CentOS Stream 10
- **OpenShift tooling**: Tested on RHEL/CentOS family

## Rationale

| Distribution | Support | RHEL Alignment | OCP Compatibility |
|--------------|---------|----------------|-------------------|
| CentOS Stream 10 | Active | Upstream of RHEL 10 | Excellent |
| RHEL 10 | 10+ years | Reference | Excellent |
| Rocky Linux 10 | Community | RHEL clone | Good |
| Fedora | ~13 months | Future RHEL | Variable |

### Why CentOS Stream 10?
1. **RHEL alignment**: Upstream of RHEL 10, closest to enterprise
2. **Free**: No subscription required for development/lab
3. **Modern packages**: Latest stable versions of required tools
4. **qubinode_navigator support**: Native plugin available
5. **Container tooling**: Podman 5.x, modern container stack

## Consequences

### Positive
- Consistent with Red Hat ecosystem
- Access to latest features and security fixes
- Strong community and enterprise support path
- Native support in qubinode_navigator

### Negative
- Rolling updates may introduce changes
- Less stable than point releases
- Some third-party software may lag support

## Implementation

### qubinode_navigator Integration
```bash
# Deploy CentOS Stream 10 host via qubinode_navigator
cd /root/qubinode_navigator
python3 qubinode_cli.py deploy --plugin rhel10 --variant centos-stream
```

### Required Packages
```yaml
# Packages available on CentOS Stream 10
base_packages:
  - podman
  - skopeo
  - golang  # >= 1.19
  - libguestfs-tools
  - ansible-core
```

### Compatibility Matrix

| Tool | CentOS Stream 10 | Notes |
|------|------------------|-------|
| podman | 5.x | Native |
| oc-mirror | v2 | Supported |
| openshift-appliance | Latest | Supported |
| ansible-core | 2.16+ | Native |
| go | 1.22+ | Native |

## Related ADRs
- ADR 0001: Three-Tier Architecture
- ADR 0005: OpenShift Appliance Builder
