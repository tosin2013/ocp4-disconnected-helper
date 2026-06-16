# Understanding Operator Validation Framework

Why this project validates operator names before mirroring, and how the validation framework prevents costly failures.

---

## The Problem: oc-mirror Fails Late

**Bad workflow** (v1.0-v1.1):
```
1. User creates operator preset with typo: "local-storage" instead of "local-storage-operator"
2. Run download-to-disk-v2.yml (10-30 minutes)
3. oc-mirror fails: "package local-storage not found in catalog"
4. Fix typo, re-run entire playbook (another 10-30 minutes)
```

**Cost**: 20-60 minutes wasted + bandwidth consumed downloading valid operators before failure

**Root cause**: oc-mirror validates operator names at runtime, not at configuration time

---

## Solution: Pre-Flight Operator Validation (ADR-0034)

**New workflow** (v1.2+):
```
1. User creates operator preset
2. Run validate-operator-selection.yml (10-30 seconds)
3. Validation fails immediately with suggestions: "Did you mean: local-storage-operator?"
4. Fix typo, re-validate (5 seconds)
5. Run download-to-disk-v2.yml (only after validation passes)
```

**Savings**: 99% time reduction for error detection (30 min → 30 sec)

---

## Validation Strategy

### Catalog Caching (24-hour TTL)

**Problem**: Querying Red Hat catalog APIs for every validation is slow

**Solution**: Local catalog cache
```bash
# First validation: Download catalog (30 seconds)
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml

# Subsequent validations: Use cache (5 seconds)
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/networking-operators.yml
```

**Cache location**: `/tmp/operator-catalog-cache/redhat-operator-index-v4.21.json`  
**Cache TTL**: 24 hours

### Fuzzy Matching for Typos

**Example**:
```
User input: "odf-operato" (typo)
Validation: ✗ Operator 'odf-operato' not found
Suggestions:
  - odf-operator (99% match)
  - ocs-operator (85% match)
  - local-storage-operator (60% match)
```

**Algorithm**: Levenshtein distance with 70% threshold

### Curated Presets (Zero Validation Failures)

**8 validated operator bundles**:
1. storage-operators (8 operators)
2. networking-operators (6 operators)
3. observability-operators (7 operators)
4. security-operators (5 operators)
5. virtualization-operators (4 operators)
6. service-mesh-operators (6 operators)
7. openshift-ai-operators (9 operators)
8. rhacm-operators (5 operators)

**Production evidence**: 100% validation success rate (32 operators tested, 0 failures)

---

## AAP Workflow Integration

**Workflow 2 architecture**:
```
Node 0: Verify Prerequisites (includes operator validation)
  ↓ (only proceed if validation passes)
Node 1: Download Images
  ↓
Node 2: Push to Registry
  ↓
Node 3: Verify Mirror
```

**Workflow Job #118 metrics**:
- Validation time: 3.6 seconds
- Operators validated: 8 (storage-operators preset)
- Validation result: ✓ All operators found
- Download saved: 25 minutes (avoided failed oc-mirror run)

---

## Discovery Tool

**scripts/discover-operators.sh** - Browse available operators

```bash
# Search by keyword
./scripts/discover-operators.sh --search storage

# List all operators in catalog
./scripts/discover-operators.sh --catalog redhat-operator-index

# Get operator details
./scripts/discover-operators.sh --operator local-storage-operator
```

**Output**:
```
=== Operator Details ===
Name: local-storage-operator
Catalog: redhat-operator-index
Description: Provides local storage using hostPath volumes
Channels: stable, preview
Latest Version: v4.21.0
```

---

## Validation Performance

| Operation | Without Validation | With Validation | Savings |
|-----------|-------------------|-----------------|---------|
| **Detect typo** | 30 minutes (oc-mirror failure) | 30 seconds | 99% |
| **Test 8 operators** | 30 minutes per run | 3.6 seconds | 99.8% |
| **Bandwidth** | 10-30 GB (partial download) | 0 GB | 100% |

---

## Related Documentation

- [ADR-0034: Operator Catalog Validation Framework](../adrs/adr-0034-operator-catalog-validation-framework.md)
- [Add Custom Operators](../how-to/add-custom-operators.md)
- [Deploy Workflow 2](../how-to/deploy-workflow-2-image-mirroring.md)
