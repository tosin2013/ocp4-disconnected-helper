# ADR 0012: Airflow DAG Orchestration Strategy

**Status:** Accepted  
**Date:** 2025-11-25  
**Revised:** 2025-12-06  
**Deciders:** Platform Team  
**PRD Reference:** Section 3.2 - Orchestration with kcli-pipelines

## Context

The ocp4-disconnected-helper project requires workflow orchestration for:
- Initial deployment (full mirror → registry → appliance → deploy)
- Incremental updates (delta mirror → registry → cluster update)
- Registry setup (Harbor or JFrog configuration)
- Maintenance tasks (cleanup, validation, health checks)

Currently, workflows are executed manually or via simple shell scripts (`cicd.sh`). This lacks:
- Visibility into workflow progress
- Retry handling and failure recovery
- Scheduling capabilities
- Audit trail of executions

## Decision

Adopt **Apache Airflow** for workflow orchestration using a **script-based DAG approach**:

1. **DAGs MUST call Ansible playbooks** via BashOperator (not custom operators or inline commands)
2. **Leverage qubinode_navigator's Airflow infrastructure** for deployment
3. **MCP server integration** for AI-powered workflow management

### Critical Requirement: Use Playbooks

**DAGs must NOT contain inline oc-mirror, podman, or other complex commands.**

Instead, DAGs should call the Ansible playbooks in `playbooks/`:

| Task | Correct Approach | Wrong Approach |
|------|------------------|----------------|
| Download images | Call `download-to-tar.yml` | Inline `oc-mirror` command |
| Push to registry | Call `push-tar-to-registry.yml` | Inline `oc-mirror --from` |
| Setup registry | Call `setup-*-registry.yml` | Inline podman/docker commands |

This ensures:
- Consistent behavior between DAG and manual execution
- Proper error handling via Ansible
- Configuration via `extra_vars/` files
- Tested and validated automation

### Proposed DAGs

| DAG | Purpose | Trigger |
|-----|---------|---------|
| `ocp_initial_deployment` | Full mirror + appliance build | Manual |
| `ocp_incremental_update` | Delta sync + cluster update | Manual/Scheduled |
| `ocp_registry_setup` | Harbor or JFrog configuration | Manual |
| `ocp_health_check` | Validate registry and mirror state | Scheduled |

## Rationale

### Why Script-Based DAGs?

Based on qubinode_navigator's experience (see `SCRIPT-BASED-DAGS-GUIDE.md`):

| Aspect | Custom Operators | Script-Based DAGs |
|--------|------------------|-------------------|
| Debugging | Check Python code, rebuild | See exact command in logs |
| Testing | Need full DAG run | Test script directly |
| Bug fixes | Rebuild container image | Edit DAG file, auto-reload |
| Transparency | Hidden in code | Visible in task logs |

### Why Airflow over Alternatives?

| Alternative | Reason Not Selected |
|-------------|---------------------|
| GitHub Actions | Limited visibility, no central dashboard |
| Jenkins | More operational overhead |
| Tekton | Kubernetes-native but more complex |
| Shell scripts | No retry, scheduling, or monitoring |

## Consequences

### Positive
- **Visibility**: Web UI shows workflow progress and history
- **Reliability**: Built-in retry and failure handling
- **Scheduling**: Cron-based scheduling for updates
- **Integration**: MCP server enables AI-assisted operations
- **Reuse**: Leverage qubinode_navigator's Airflow setup

### Negative
- **Infrastructure**: Requires Airflow deployment (containers)
- **Learning curve**: Teams need Airflow familiarity
- **Dependency**: Adds qubinode_navigator as runtime dependency

## Implementation

### Directory Structure
```
ocp4-disconnected-helper/
└── airflow/
    ├── dags/
    │   ├── ocp_initial_deployment.py
    │   ├── ocp_incremental_update.py
    │   ├── ocp_registry_setup.py
    │   └── ocp_health_check.py
    ├── scripts/
    │   ├── validate-environment.sh
    │   ├── download-content.sh
    │   ├── push-to-registry.sh
    │   └── build-appliance.sh
    └── README.md
```

### DAG Pattern
```python
from airflow import DAG
from airflow.operators.bash import BashOperator

# Script-based approach - calls Ansible playbooks directly
download_task = BashOperator(
    task_id='download_to_tar',
    bash_command='''
    cd /root/ocp4-disconnected-helper
    ansible-playbook playbooks/download-to-tar.yml \
        -e ocp_release_version={{ params.ocp_version }} \
        -e clean_mirror_path={{ params.clean_mirror }}
    ''',
)
```

### Integration with qubinode_navigator
```yaml
# Deploy using qubinode_navigator's Airflow
cd /root/qubinode_navigator/airflow
./deploy-airflow.sh

# DAGs from ocp4-disconnected-helper mounted to:
# /opt/airflow/dags/ocp4-disconnected-helper/
```

## Workflow Diagrams

### Initial Deployment DAG
```
validate_environment
        │
        ▼
  download_to_tar (clean_mirror_path=true)
        │
        ▼
   setup_registry
        │
        ▼
  push_to_registry
        │
        ▼
  build_appliance
        │
        ▼
deployment_summary
```

### Incremental Update DAG
```
pre_update_validation
        │
        ▼
download_incremental (clean_mirror_path=false)
        │
        ▼
  push_to_registry
        │
        ▼
   update_cluster
        │
        ▼
  update_summary
```

## Future Considerations

1. **Sensors**: Add sensors to wait for external events (e.g., new OCP release)
2. **Branching**: Conditional paths based on registry type
3. **Notifications**: Slack/email alerts on completion/failure
4. **Metrics**: Export DAG metrics to Prometheus

## Related ADRs
- ADR 0001: Three-Tier Architecture
- ADR 0006: Lifecycle Management Strategy
- ADR 0008: GitHub Actions Automation
- ADR 0011: qubinode_navigator Integration
