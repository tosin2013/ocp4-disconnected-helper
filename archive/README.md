# Legacy Code Archive

Preserved code from v4.20.0 for reference during v4.21.0 migration.

## Contents

- **airflow-legacy/**: Apache Airflow DAG code (~2000 lines)
  - Will be populated in Phase 3 (Task 3.8)
  - Reference: 8 production DAGs for workflow orchestration
  
- **kcli-legacy/**: kcli-based VM provisioning playbooks
  - Will be populated in Phase 1 (Task 1.3 backup)
  - Reference: Original kcli CLI approach

## Important Notes

⚠️ **Do not modify**: This code is frozen for reference only.

📌 **Legacy Tag**: v4.20.0-airflow  
📅 **Archived**: 2026-06-02  
🎯 **Migration**: See [RELEASE_PLAN.md](../RELEASE_PLAN.md)

## For Legacy Users

If you need to remain on the old architecture:

```bash
git checkout v4.20.0-airflow
```

No backports will be provided to this version.

## Migration Timeline

- **Phase 0** (Week 1): Preservation - Tag created ✅
- **Phase 1** (Weeks 1-4): Libvirt migration - kcli code archived here
- **Phase 2** (Weeks 3-8): Qubinode removal
- **Phase 3** (Weeks 2-15): AAP adoption - Airflow code archived here
- **Phase 4** (Weeks 16-17): Documentation finalization

See [TODO.md](../TODO.md) for complete task list.
