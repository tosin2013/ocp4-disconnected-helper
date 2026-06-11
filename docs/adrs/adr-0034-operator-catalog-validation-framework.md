# ADR-0034: Operator Catalog Validation and Management Framework

**Status**: Accepted → **Validated in Production (v1.2)**  
**Date**: 2026-06-11  
**Production Validation**: 2026-06-11 (Release v1.2)  
**Deciders**: Architecture Team  
**Related ADRs**: ADR-0003 (oc-mirror v2), ADR-0024 (Roles Architecture), ADR-0032/0033 (AAP Workflows)

---

## Context

Operator selection for disconnected OpenShift mirroring currently requires manual lookups, copy-pasting operator names into extra_vars files, and offers no validation until oc-mirror runs (often 10-30 minutes into execution).

### Current Pain Points

1. **No Pre-flight Validation**: Typos in operator names only surface after expensive mirroring starts
2. **Cryptic Error Messages**: `"package local-storage not found in catalog"` provides no suggestions
3. **Manual Discovery**: Users must browse Red Hat documentation to find valid operator names
4. **Duplicate Maintenance**: Same operator lists repeated across multiple extra_vars files
5. **Late Failure Detection**: Invalid channel names fail mid-mirror, wasting time and bandwidth

### Example Failure Scenario

```yaml
# User types "local-storage" instead of "local-storage-operator"
operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
    packages:
      - name: local-storage  # ❌ INVALID - no validation until oc-mirror runs

# Error appears 10 minutes into mirroring:
# [ERROR] package local-storage not found in catalog
```

---

## Decision

Implement a **three-component operator validation framework** that validates operator selections before expensive mirroring operations and provides discovery tooling for easier catalog exploration.

### Architecture Components

**Component 1: Operator Catalog Cache** (Ansible Role)
- **Role**: `roles/operator_catalog/`
- Downloads and caches catalog metadata (~5-10MB per catalog)
- Provides validation logic against cached catalog
- Refreshes cache on-demand or via TTL (24 hours default)

**Component 2: Validation Playbook**
- **Playbook**: `playbooks/validate-operator-selection.yml`
- Validates operator lists from extra_vars against cached catalogs
- Outputs actionable error messages with suggestions
- Integrates as AAP workflow preflight node

**Component 3: Operator Discovery Tool** (CLI Script)
- **Script**: `scripts/discover-operators.sh`
- Searches operator catalogs by keyword
- Displays available channels and versions
- Outputs valid YAML snippets for copy-paste

---

## Implementation Design

### File Structure

```
roles/operator_catalog/
├── tasks/
│   ├── main.yml                       # Entry point
│   ├── cache-catalog-metadata.yml     # Download catalog index
│   ├── validate-operators.yml         # Validation logic
│   └── list-available-operators.yml   # Discovery helper
├── templates/
│   └── operator-list-template.yml.j2  # Starter template
├── vars/
│   └── catalog-urls.yml               # Red Hat catalog registry URLs
└── defaults/
    └── main.yml                       # Cache TTL, validation strictness

playbooks/validate-operator-selection.yml  # User-facing validation playbook

scripts/discover-operators.sh              # CLI discovery tool

extra_vars/operators/                      # Centralized operator definitions
├── storage-operators.yml
├── observability-operators.yml
├── networking-operators.yml
└── README.md
```

### Cache Strategy

- **Location**: `/var/cache/oc-mirror/catalogs/`
- **TTL**: 24 hours (configurable via `operator_catalog_cache_ttl`)
- **Size**: ~5-10MB per catalog (vs 50-100GB full mirror)
- **Source**: `oc mirror list operators --catalog=<url>` output
- **Offline Mode**: Manual catalog import via USB for air-gapped environments

### Validation Logic Flow

```yaml
# playbooks/validate-operator-selection.yml
- name: Validate Operator Selection
  hosts: localhost
  gather_facts: false
  
  tasks:
    - name: Refresh catalog cache if stale
      ansible.builtin.import_role:
        name: operator_catalog
        tasks_from: cache-catalog-metadata.yml
      when: catalog_cache_expired or force_refresh

    - name: Validate operators against cache
      ansible.builtin.import_role:
        name: operator_catalog
        tasks_from: validate-operators.yml
      vars:
        operators_to_validate: "{{ operators }}"
        fail_on_invalid: true
```

### Error Reporting Example

```
❌ VALIDATION FAILED

Invalid operators in redhat-operator-index:v4.21:
  • local-storage          → Did you mean: local-storage-operator?
  • gitops                 → Did you mean: openshift-gitops-operator?
  
Operators not found in certified-operator-index:v4.21:
  • mongodb-enterprise     → Not available in v4.21 catalog
                            Available in: v4.20, v4.19

Channel not found:
  • ocs-operator:stable-4.22 → Available channels: stable-4.21, stable-4.20

✅ Valid operators (15):
  • metallb-operator:stable
  • lvms-operator:stable-4.21
  • kubevirt-hyperconverged:stable
  ...
```

### AAP Workflow Integration

```
Workflow: "Deploy Disconnected OpenShift Infrastructure"
  ├─► Node 1: Validate Operator Selection          ← NEW
  │   └─► Playbook: validate-operator-selection.yml
  │       └─► On Failure: Stop workflow
  │
  ├─► Node 2: Download OpenShift Images (Phase 1)
  │   └─► Playbook: download-to-disk-v2.yml
  │
  └─► Node 3: Mirror Images to Registry (Phase 2)
      └─► Playbook: push-to-registry-v2.yml
```

---

## Alternatives Considered

### Option A: Pre-flight Validation Playbook (CHOSEN)
**Pros**:
- ✅ Fails fast - catches errors before expensive operations
- ✅ Integrates cleanly with AAP workflows as preflight node
- ✅ No runtime overhead on actual mirroring
- ✅ Can run manually for quick validation

**Cons**:
- ⚠️ Requires cached catalog (needs refresh mechanism)
- ⚠️ Users must remember to run validation (unless in AAP)

### Option B: Runtime Validation in Download Playbook
**Pros**:
- ✅ Always runs - no separate step
- ✅ No risk of users forgetting validation

**Cons**:
- ❌ Still wastes time if validation fails (prerequisites already installed)
- ❌ Complicates download playbook logic
- ❌ Harder to test validation independently

**Decision**: Rejected - fails slower than Option A

### Option C: External Web Service
**Pros**:
- ✅ Rich UX with search, autocomplete, visual catalog browsing
- ✅ Real-time catalog updates

**Cons**:
- ❌ Infrastructure dependency (web server, database)
- ❌ Authentication complexity for multi-user access
- ❌ Doesn't fit air-gapped deployment model

**Decision**: Deferred to future enhancement - over-engineered for current needs

---

## Consequences

### Positive

- ✅ **Fast Failure Detection**: Invalid operators caught in seconds vs minutes
- ✅ **Improved User Experience**: Clear error messages with suggestions (fuzzy matching)
- ✅ **Bandwidth Savings**: No partial downloads of invalid configurations
- ✅ **Self-Documenting**: Validation output educates users about catalog structure
- ✅ **Extensible**: Cache mechanism reusable for other validations (e.g., OCP version checks)
- ✅ **AAP-Native Integration**: Works as standard workflow node
- ✅ **Offline Support**: Manual catalog import for disconnected environments

### Negative

- ⚠️ **Cache Dependency**: Stale cache could miss newly-added operators (mitigated by TTL + warnings)
- ⚠️ **Initial Setup**: Requires first-time cache download (5-10MB per catalog)
- ⚠️ **Maintenance**: Cache refresh mechanism needs monitoring

### Mitigation Strategies

1. **Staleness Warnings**: Display cache age and warn if >24 hours old
2. **Force Refresh Flag**: `force_refresh=true` to update cache on demand
3. **Offline Mode**: `scripts/import-catalog-offline.sh` for air-gapped manual updates
4. **Cache Health Check**: Pre-flight validation warns if cache missing/expired

---

## Compliance with Existing ADRs

- **ADR-0003 (oc-mirror v2)**: ✅ Uses `oc mirror list operators` commands
- **ADR-0024 (Roles Architecture)**: ✅ `operator_catalog` role follows atomic pattern
- **ADR-0032/0033 (AAP Workflows)**: ✅ Integrates as workflow preflight node
- **ADR-0009 (Secrets Management)**: ✅ No credentials required (public catalogs)

---

## Implementation Phases

### Phase 1: Core Validation Framework (COMPLETED - v1.2)
- ✅ `playbooks/validate-operator-selection.yml` (validated in AAP Workflow #118)
- ✅ `scripts/discover-operators.sh` (8 operator presets created)
- ✅ AAP workflow integration as preflight node (Workflow ID 36, Job Template ID 34)
- ✅ Fuzzy matching with similarity threshold 0.6 (production-tested)
- ✅ Catalog caching with 24h TTL at ~/.cache/oc-mirror/catalogs/ (~73 KB vs 50-100 GB)

### Phase 2: Enhanced Discovery (COMPLETED - v1.2)
- ✅ Fuzzy matching for typo suggestions (implemented with difflib)
- ✅ Curated operator preset bundles (8 presets validated):
  - storage-operators.yml (5 operators: ODF, LVMS, Local Storage, NFS, Rook Ceph)
  - rhacm-operators.yml (4 operators: RHACM 2.16, MCE 2.11, Submariner 0.24, GitOps)
  - openshift-ai-operators.yml (5 operators: RHODS, Authorino, Service Mesh, Serverless, GPU)
  - virtualization-operators.yml (4 operators: KubeVirt, ODF, NMState, MetalLB)
  - service-mesh-operators.yml (3 operators: Service Mesh, Kiali, Tempo)
  - observability-operators.yml (5 operators: Logging, Loki, Tempo, Observability, GitOps)
  - security-operators.yml (4 operators: Compliance, FIM, Quay, Quay Bridge)
  - networking-operators.yml (4 operators: MetalLB, NMState, Submariner, Service Mesh)
- ✅ Comprehensive documentation (extra_vars/operators/README.md)
- ⏳ Operator dependency graph visualization (deferred to v1.3)
- ⏳ Channel version comparison tool (deferred to v1.3)

### Phase 3: Advanced Features (Future)
- ⏳ Operator CVE scanning integration
- ⏳ Cost estimation (image sizes, mirror duration)
- ⏳ Historical operator availability tracking

---

## Testing Strategy

### Validation Test Cases

1. **Valid Configuration**: All operators exist, channels valid → ✅ PASS
2. **Typo Detection**: `local-storage` → suggests `local-storage-operator`
3. **Invalid Operator**: Non-existent package → clear error with catalog search hint
4. **Invalid Channel**: `stable-4.22` when only `stable-4.21` exists → show available channels
5. **Stale Cache**: Cache >24 hours old → warning + option to refresh
6. **Missing Cache**: No cache exists → auto-download on first run
7. **Offline Mode**: Manual catalog import → validation works without internet

### Integration Test Cases

1. **AAP Workflow**: Validation failure stops workflow before Phase 1
2. **CLI Usage**: `ansible-playbook validate-operator-selection.yml` runs standalone
3. **Cache Refresh**: `force_refresh=true` updates cache successfully
4. **Multiple Catalogs**: Validates across Red Hat + Certified catalogs simultaneously

---

## Success Metrics

- **Error Detection Time**: <30 seconds (vs 10+ minutes with current approach)
- **False Positive Rate**: <5% (typos correctly identified)
- **Cache Hit Rate**: >90% (refresh mechanism working)
- **User Satisfaction**: Reduced support tickets for "operator not found" errors

---

## References

- [Red Hat Operator Catalog Documentation](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.21/html/operators/understanding-operators)
- [oc-mirror v2 Operator Mirroring](https://docs.openshift.com/container-platform/4.21/installing/disconnected_install/installing-mirroring-disconnected.html)
- Historical operator configuration: [download-to-tar-vars.yml](https://github.com/tosin2013/ocp4-disconnected-helper/blob/2b7f48c8b66cf8aecc8ffe18da9d8aed1e855294/extra_vars/download-to-tar-vars.yml)

---

## Notes

- Discovery tool (`scripts/discover-operators.sh`) is Phase 1 deliverable but can be enhanced in Phase 2
- Preset operator bundles (`extra_vars/operators/*.yml`) are organizational aids, not replacements for validation
- Cache mechanism is designed to support future validations (OCP versions, additional images)
