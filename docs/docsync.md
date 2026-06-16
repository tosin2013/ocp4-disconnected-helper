---
layout: default
title: Documentation Sync Manifest
nav_order: 99
description: "PMB↔Docs synchronization manifest and DID mapping"
---

# Documentation Sync Manifest

**Project**: ocp4-disconnected-helper  
**Version**: v1.4.0 (docset:v1.4.0)  
**Last Updated**: 2026-06-16  
**Source of Truth**: `reconcile` (docs canonical for content, PMB for abstracts)

---

## Document ID (DID) Scheme

**Prefix**: `DOC:ocp4-helper:`  
**Format**: `DOC:ocp4-helper:<relative-path-from-docs>`

**Examples**:
- `DOC:ocp4-helper:tutorials/getting-started-with-aap-workflows.md`
- `DOC:ocp4-helper:how-to/deploy-workflow-1-registry-infrastructure.md`
- `DOC:ocp4-helper:reference/playbook-parameters.md`
- `DOC:ocp4-helper:explanations/bootstrap-vs-workflow-layers.md`

---

## DID Mapping Table

### Tutorials (3 files)

| DID | Path | Type | Last Updated | Status |
|-----|------|------|--------------|--------|
| `DOC:ocp4-helper:tutorials/getting-started-with-aap-workflows.md` | `docs/tutorials/getting-started-with-aap-workflows.md` | Tutorial | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:tutorials/your-first-openshift-image-mirror.md` | `docs/tutorials/your-first-openshift-image-mirror.md` | Tutorial | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:tutorials/end-to-end-disconnected-deployment.md` | `docs/tutorials/end-to-end-disconnected-deployment.md` | Tutorial | 2026-06-16 | ✅ Synced |

### How-To Guides (8 files)

| DID | Path | Type | Last Updated | Status |
|-----|------|------|--------------|--------|
| `DOC:ocp4-helper:how-to/deploy-workflow-1-registry-infrastructure.md` | `docs/how-to/deploy-workflow-1-registry-infrastructure.md` | How-To | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:how-to/deploy-workflow-2-image-mirroring.md` | `docs/how-to/deploy-workflow-2-image-mirroring.md` | How-To | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:how-to/troubleshoot-workflow-failures.md` | `docs/how-to/troubleshoot-workflow-failures.md` | How-To | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:how-to/resolve-aap-login-failure.md` | `docs/how-to/resolve-aap-login-failure.md` | How-To | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:how-to/resolve-oc-mirror-async-cache.md` | `docs/how-to/resolve-oc-mirror-async-cache.md` | How-To | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:how-to/resolve-registry-tls-authentication.md` | `docs/how-to/resolve-registry-tls-authentication.md` | How-To | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:how-to/add-custom-operators.md` | `docs/how-to/add-custom-operators.md` | How-To | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:how-to/switch-registry-types.md` | `docs/how-to/switch-registry-types.md` | How-To | 2026-06-16 | ✅ Synced |

### Reference (6 files)

| DID | Path | Type | Last Updated | Status |
|-----|------|------|--------------|--------|
| `DOC:ocp4-helper:AAP_WORKFLOW_CATALOG.md` | `docs/AAP_WORKFLOW_CATALOG.md` | Reference | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:reference/playbook-parameters.md` | `docs/reference/playbook-parameters.md` | Reference | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:adrs/README.md` | `docs/adrs/README.md` | Reference | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:reference/environment-variables.md` | `docs/reference/environment-variables.md` | Reference | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:reference/workflow-survey-parameters.md` | `docs/reference/workflow-survey-parameters.md` | Reference | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:reference/bootstrap-prerequisites.md` | `docs/reference/bootstrap-prerequisites.md` | Reference | 2026-06-16 | ✅ Synced |

### Explanations (6 files)

| DID | Path | Type | Last Updated | Status |
|-----|------|------|--------------|--------|
| `DOC:ocp4-helper:explanations/bootstrap-vs-workflow-layers.md` | `docs/explanations/bootstrap-vs-workflow-layers.md` | Explanation | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:explanations/multi-workflow-architecture.md` | `docs/explanations/multi-workflow-architecture.md` | Explanation | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:explanations/certificate-management-decisions.md` | `docs/explanations/certificate-management-decisions.md` | Explanation | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:explanations/operator-validation-framework.md` | `docs/explanations/operator-validation-framework.md` | Explanation | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:explanations/airflow-to-aap-migration.md` | `docs/explanations/airflow-to-aap-migration.md` | Explanation | 2026-06-16 | ✅ Synced |
| `DOC:ocp4-helper:explanations/nested-kvm-hypervisor-architecture.md` | `docs/explanations/nested-kvm-hypervisor-architecture.md` | Explanation | 2026-06-16 | ✅ Synced |

---

## Sync Rules

### Document Requirements
1. **DID Header**: Each doc file MUST include DID in front matter:
   ```yaml
   ---
   # DID: DOC:ocp4-helper:path/to/file.md
   ---
   ```

2. **Stable DIDs**: Once assigned, DIDs NEVER change (even if file moves)

3. **Path Changes**: If file moves, update docsync.md mapping but keep DID

### PMB Memory Requirements
1. **Doc Memories**: Each doc has corresponding PMB memory with:
   - DID (stable identifier)
   - Repo-relative path
   - Doc type (tutorial/howto/reference/explanation)
   - Abstract (5-10 lines)
   - Key headings outline
   - Version tag (docset:v1.4.0)

2. **Tags**: All doc memories MUST have:
   - `diataxis`
   - `docs`
   - `project:ocp4-helper`
   - `docset:v1.4.0`
   - `docsync`
   - Type-specific tag (`tutorial` | `howto` | `reference` | `explanation`)

### Reconciliation Process
1. **Docs → PMB**: When doc changes, update PMB abstract/outline
2. **PMB → Docs**: If PMB has unique operational knowledge, append to relevant doc
3. **Conflict Resolution**: Docs canonical for content, PMB for metadata

---

## PMB Commands

### Create Doc Memory
```bash
pmb record_batch items='[
  {
    "type": "fact_tree",
    "main": "DOCSYNC: <doc-title>",
    "subfacts": [
      "DID: DOC:ocp4-helper:path/to/file.md",
      "Path: docs/path/to/file.md",
      "Type: tutorial|howto|reference|explanation",
      "Abstract: <5-10 line summary>",
      "Headings: ## Section 1, ## Section 2, ..."
    ],
    "importance": 0.8
  }
]' --tags diataxis,docs,project:ocp4-helper,docset:v1.4.0,docsync,<type>
```

### Query Doc Memories
```bash
pmb recall --tags project:ocp4-helper,docsync
pmb recall --tags project:ocp4-helper,tutorial
pmb recall --tags project:ocp4-helper,howto
pmb recall --tags project:ocp4-helper,reference
pmb recall --tags project:ocp4-helper,explanation
```

### Update Stale Memory
```bash
pmb update <memory-id> "Updated abstract and headings for <doc-title>"
```

---

## Maintenance

### When Adding New Doc
1. Generate DID: `DOC:ocp4-helper:<relative-path>`
2. Add front matter with DID
3. Add entry to docsync.md mapping table
4. Create PMB memory with DID + abstract + tags
5. Update PMB docset index

### When Moving/Renaming Doc
1. Keep DID unchanged
2. Update path in docsync.md
3. Update path in PMB memory
4. Add redirect from old path if public-facing

### When Updating Doc Content
1. Update doc file
2. Update PMB memory abstract/outline
3. Verify DID still matches
4. Update "Last Updated" in docsync.md

---

## Sync Status

**Last Full Sync**: 2026-06-16  
**Docs Count**: 23 core Diátaxis files  
**PMB Memories**: 23 doc memories + 1 index  
**Sync Health**: ✅ 100% (all docs have PMB memories)

---

## Related Documentation

- [index.md](index.md) - Main documentation index
- [DEPLOYMENT_SUCCESS.md](DEPLOYMENT_SUCCESS.md) - GitHub Pages deployment
- [adrs/README.md](adrs/README.md) - ADR index (36 decisions)

---

**Sync Protocol Version**: 1.0  
**Compatible PMB Version**: ≥ 0.1.0
