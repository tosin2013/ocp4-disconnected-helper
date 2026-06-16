# Understanding the Airflow → AAP Migration

Why this project deprecated Apache Airflow and adopted Ansible Automation Platform for workflow orchestration.

---

## The Airflow Experiment (v0.5-v0.8)

### Why Airflow Was Chosen Initially

**v0.5 decision** (ADR-0012):
- ✅ Powerful DAG orchestration
- ✅ Workflow visualization
- ✅ Retry mechanisms built-in
- ✅ Familiar Python-based development
- ✅ Open source

**Initial implementation**:
```python
# dags/registry_deployment.py
registry_deployment_dag = DAG(
    'deploy_registry',
    schedule_interval=None,
    tasks=[
        deploy_vm,
        install_registry,
        configure_certs,
        verify_deployment
    ]
)
```

### Problems Discovered

**1. Heavy Infrastructure Footprint**
- Airflow scheduler: 2 GB RAM
- Airflow web server: 1 GB RAM
- PostgreSQL database: 1 GB RAM
- Redis (Celery): 512 MB RAM
- **Total**: 4.5 GB RAM just for orchestration

**2. Complex Ansible Integration**
- Airflow → BashOperator → ansible-playbook
- No native Ansible inventory support
- No Ansible Vault integration
- Extra vars passed via environment variables (security risk)

**3. Operational Overhead**
- Separate service to maintain (Airflow + dependencies)
- Database schema migrations
- Airflow version upgrades
- User authentication separate from Ansible

**4. Skill Set Mismatch**
- Project uses Ansible for automation
- Team expertise in Ansible, not Python/Airflow
- Debugging requires Python + Airflow knowledge
- Two different tools to maintain

---

## The AAP Migration (v1.0+)

### Why AAP Was Chosen (ADR-0021)

**Decision drivers**:
1. **Native Ansible integration** - No wrapper layer needed
2. **Workflow orchestration** - Similar to Airflow DAGs but Ansible-native
3. **Resource efficiency** - Containerized, shares resources
4. **Unified platform** - Automation + orchestration in one
5. **Enterprise support** - Red Hat backing

**Comparison**:

| Aspect | Airflow | AAP |
|--------|---------|-----|
| **RAM Usage** | 4.5 GB | 8 GB (full platform, not just orchestration) |
| **Ansible Integration** | Via BashOperator | Native |
| **Skill Set** | Python + Airflow | Ansible only |
| **Authentication** | Separate | RBAC built-in |
| **Secrets** | Environment variables | Ansible Vault native |
| **License** | Open source | Red Hat subscription (free for 10 nodes) |

---

## Migration Strategy

### Phase 1: Parallel Deployment (v0.8-v1.0)

**Both systems operational**:
- Airflow: Existing DAGs continue running
- AAP: New workflows developed in parallel

**Purpose**: De-risk migration, validate AAP workflows

### Phase 2: Workflow Conversion (v1.0-v1.2)

**Airflow DAG → AAP Workflow mapping**:

```python
# Airflow DAG (deprecated)
deploy_vm = BashOperator(
    task_id='deploy_vm',
    bash_command='ansible-playbook playbooks/deploy-vm.yml'
)

install_registry = BashOperator(
    task_id='install_registry',
    bash_command='ansible-playbook playbooks/setup-mirror-registry.yml'
)

deploy_vm >> install_registry  # Dependency
```

**AAP Workflow (current)**:
```yaml
# AAP Workflow Template
nodes:
  - name: Deploy VM
    job_template: deploy-registry-vm
  
  - name: Install Registry
    job_template: setup-mirror-registry
    dependencies:
      - Deploy VM  # Success edge
```

**Key improvement**: No BashOperator wrapper, direct Ansible execution

### Phase 3: Airflow Decommission (v1.2)

**Steps**:
1. Migrate all DAGs to AAP workflows
2. Verify AAP workflows production-ready
3. Stop Airflow scheduler and web server
4. Archive Airflow configuration
5. Update documentation to remove Airflow references

**Status**: Complete (ADR-0021)

---

## What Was Kept from Airflow

**Concepts retained**:
- DAG structure → Workflow nodes with success/failure edges
- Retry logic → AAP job template retry settings
- Execution history → AAP job tracking
- Workflow visualization → AAP workflow diagram

**Skills retained**:
- Task dependency modeling
- Error handling patterns
- Idempotence principles
- Orchestration thinking

---

## What AAP Does Better

### Native Ansible Features

**Inventory management**:
```yaml
# AAP Inventory (native)
inventory:
  hosts:
    registry:
      ansible_host: 192.168.10.10
```

**Vault integration**:
```yaml
# AAP Credential (native Ansible Vault)
credential_type: ansible_vault
inputs:
  vault_password: !vault |
    $ANSIBLE_VAULT;1.1;AES256...
```

### Survey-Driven Workflows

**Airflow approach**:
```python
# Hardcoded in DAG code
registry_type = Variable.get('registry_type', default_var='quay')
```

**AAP approach**:
```yaml
# User selects at launch via Web UI
survey:
  - question: "Registry Type"
    choices: [quay, harbor, jfrog]
```

**Advantage**: No code changes for different configurations

### RBAC and Multi-Tenancy

**Airflow**: Basic auth or OAuth  
**AAP**: Granular RBAC (teams, organizations, roles)

**Example**:
- Dev team: Can launch workflows, cannot edit
- Ops team: Can launch + edit workflows
- Admin: Full access

---

## Migration Lessons Learned

### Lesson 1: Start with Orchestration Tool That Matches Automation Tool

**Mistake**: Used Airflow (Python) to orchestrate Ansible (YAML)  
**Fix**: Use AAP (Ansible-native orchestration)

**Guideline**: If automation is in Ansible, use Ansible-native orchestration

### Lesson 2: Operational Overhead Matters

**Mistake**: Underestimated Airflow operational overhead  
**Fix**: AAP containerized deployment simpler

**Guideline**: Factor in maintenance cost, not just feature set

### Lesson 3: Skill Set Alignment

**Mistake**: Team had Ansible skills, not Airflow skills  
**Fix**: AAP leverages existing Ansible knowledge

**Guideline**: Choose tools aligned with team expertise

---

## When to Use Airflow vs AAP

### Use Airflow When:

- ✅ Python-based data pipelines (ETL, ML workflows)
- ✅ Complex scheduling (cron expressions, external triggers)
- ✅ Team has Python/Airflow expertise
- ✅ Non-Ansible automation (Spark, Kubernetes operators)

### Use AAP When:

- ✅ Ansible is primary automation tool
- ✅ Infrastructure provisioning workflows
- ✅ Configuration management orchestration
- ✅ Team has Ansible expertise
- ✅ Enterprise support required

**This project**: Infrastructure provisioning + Ansible-first → AAP was correct choice

---

## Related Decisions

- [ADR-0021: Deprecate Airflow and Adopt AAP](../adrs/0021-deprecate-airflow-adopt-aap.md)
- [ADR-0012: Airflow DAG Orchestration](../adrs/0012-airflow-dag-orchestration.md) (deprecated)
- [ADR-0032: AAP Workflow Orchestration Strategy](../adrs/adr-0032-aap-workflow-orchestration-strategy.md)

---

## Summary

**Why migration happened**: Operational overhead + skill set mismatch + redundant infrastructure

**Key benefit**: Native Ansible orchestration without Python wrapper layer

**Result**: Simpler operations, better team alignment, unified platform
