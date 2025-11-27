# Airflow DAGs for ocp4-disconnected-helper

This directory contains Apache Airflow DAGs for orchestrating OpenShift deployment and lifecycle management in disconnected environments.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    qubinode_navigator                            │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                 Apache Airflow                           │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐      │    │
│  │  │  Scheduler  │  │  Webserver  │  │ MCP Server  │      │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘      │    │
│  │         │                │                │              │    │
│  │         └────────────────┼────────────────┘              │    │
│  │                          │                               │    │
│  │                    ┌─────▼─────┐                         │    │
│  │                    │   DAGs    │◄── Mounted from         │    │
│  │                    └───────────┘    ocp4-disconnected-   │    │
│  └─────────────────────────────────────helper/airflow/dags  │    │
└─────────────────────────────────────────────────────────────────┘
```

## Available DAGs

| DAG ID | Description | ADR Reference |
|--------|-------------|---------------|
| `ocp_initial_deployment` | Complete initial deployment workflow | ADR 0012, 0014 |
| `ocp_incremental_update` | Incremental cluster update workflow | ADR 0006, 0012 |

## DAG Details

### ocp_initial_deployment

Orchestrates the complete initial deployment:

```
validate_environment → setup_certificates → setup_registry → download_to_tar → push_to_registry → build_appliance → deployment_summary
```

**Parameters:**
- `ocp_version`: OpenShift version (default: 4.20.0)
- `registry_type`: harbor or jfrog (default: harbor)
- `clean_mirror`: true for full mirror, false for incremental

**Estimated Duration:** 2-6 hours (first run)

### ocp_incremental_update

Orchestrates incremental cluster updates:

```
pre_update_validation → download_incremental → push_to_registry → apply_manifests → trigger_update → monitor_update → update_summary
```

**Parameters:**
- `current_version`: Current cluster version
- `target_version`: Target update version
- `kubeconfig_path`: Path to kubeconfig

**Estimated Duration:** 1-3 hours

## Setup

### 1. Deploy DAGs to qubinode_navigator

DAGs are maintained in this repository and deployed to qubinode_navigator's Airflow instance.

#### Using the Deploy Script (Recommended)

```bash
# Deploy DAGs
./airflow/deploy-dags.sh

# Check deployment status
./airflow/deploy-dags.sh --check

# Remove deployed DAGs
./airflow/deploy-dags.sh --remove
```

#### Manual Deployment

```bash
# Copy DAGs to qubinode_navigator
cp /root/ocp4-disconnected-helper/airflow/dags/ocp_*.py \
   /root/qubinode_navigator/airflow/dags/

# Force Airflow to pick up new DAGs
podman exec airflow_airflow-scheduler_1 airflow dags reserialize
```

#### Why This Approach?

| Approach | Pros | Cons |
|----------|------|------|
| **Keep in ocp4-disconnected-helper** | DAGs versioned with project, clear ownership | Requires deploy step |
| Commit to qubinode_navigator | Immediate availability | Couples infrastructure to automation |
| Git submodule | Clean separation | Complex git workflow |

We chose to keep DAGs in this project because:
- DAGs are tightly coupled to the playbooks they orchestrate
- Version changes should be atomic (DAG + playbook together)
- Clear ownership and maintenance responsibility

### 2. Verify DAGs are Loaded

```bash
# Check Airflow UI
open http://localhost:8888

# Or via CLI
podman exec airflow_airflow-scheduler_1 airflow dags list | grep ocp
```

### 3. Configure Extra Variables

Create configuration files in `extra_vars/`:

```bash
# For download-to-tar
cat > /root/ocp4-disconnected-helper/extra_vars/download-to-tar.yml << EOF
target_mirror_path: /opt/openshift-mirror
openshift_releases:
  - version: "4.20.0"
    channel: stable
operators:
  - name: local-storage-operator
    channel: stable
EOF

# For push-tar-to-registry
cat > /root/ocp4-disconnected-helper/extra_vars/push-tar-to-registry.yml << EOF
target_registry: registry.disconnected.local:5000
target_registry_user: admin
target_registry_password: "{{ vault_registry_password }}"
EOF
```

## Triggering DAGs

### Via Airflow UI

1. Navigate to http://localhost:8888
2. Login (default: admin/admin)
3. Find the DAG (e.g., `ocp_initial_deployment`)
4. Click the play button ▶️
5. Configure parameters if needed
6. Click "Trigger"

### Via Airflow CLI

```bash
# Trigger with default parameters
airflow dags trigger ocp_initial_deployment

# Trigger with custom parameters
airflow dags trigger ocp_initial_deployment \
    --conf '{"ocp_version": "4.20.0", "registry_type": "harbor"}'
```

### Via MCP Server

Using the qubinode-airflow MCP tools:

```python
# List available DAGs
list_dags()

# Get DAG details
get_dag_info("ocp_initial_deployment")

# Trigger DAG
trigger_dag("ocp_initial_deployment", {
    "ocp_version": "4.20.0",
    "registry_type": "harbor",
    "clean_mirror": "false"
})
```

### Via Python/API

```python
import requests

AIRFLOW_URL = "http://localhost:8888"
AUTH = ("admin", "admin")

# Trigger DAG
response = requests.post(
    f"{AIRFLOW_URL}/api/v1/dags/ocp_initial_deployment/dagRuns",
    auth=AUTH,
    json={
        "conf": {
            "ocp_version": "4.20.0",
            "registry_type": "harbor"
        }
    }
)
print(response.json())
```

## Monitoring

### Airflow UI

- **DAG View:** Overview of all DAGs and their status
- **Graph View:** Visual representation of task dependencies
- **Gantt View:** Task execution timeline
- **Logs:** Detailed task output

### CLI Commands

```bash
# Check DAG status
airflow dags state ocp_initial_deployment <execution_date>

# List recent runs
airflow dags list-runs -d ocp_initial_deployment

# Get task logs
airflow tasks logs ocp_initial_deployment validate_environment <execution_date>
```

## Troubleshooting

### DAG Not Appearing

1. Check DAG file syntax:
   ```bash
   python3 -c "import dags.ocp_initial_deployment"
   ```

2. Check Airflow logs:
   ```bash
   podman logs airflow_airflow-scheduler_1 | grep -i error
   ```

3. Verify file permissions:
   ```bash
   ls -la /root/qubinode_navigator/airflow/dags/
   ```

### Task Failures

1. Check task logs in Airflow UI
2. Review Ansible playbook output
3. Verify prerequisites:
   - Pull secret exists
   - Sufficient disk space
   - Network connectivity (for connected tasks)

### Common Issues

| Issue | Solution |
|-------|----------|
| "Pull secret not found" | Copy to `/root/pull-secret.json` |
| "Disk space insufficient" | Free up space or change `mirror_path` |
| "Registry connection failed" | Check certificates (ADR 0016) |
| "oc-mirror timeout" | Increase `execution_timeout` in DAG |
| "Cluster unreachable" | Verify kubeconfig and network |

## Directory Structure

```
airflow/
├── README.md                      # This file
├── deploy-dags.sh                 # Script to deploy DAGs to qubinode_navigator
├── dags/
│   ├── ocp_initial_deployment.py  # Initial deployment DAG
│   └── ocp_incremental_update.py  # Incremental update DAG
└── scripts/                       # Helper scripts (optional)
    ├── validate-environment.sh
    └── health-check.sh
```

## Deployment Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│  ocp4-disconnected-helper (this repo)                           │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  airflow/dags/                                           │    │
│  │    ├── ocp_initial_deployment.py                         │    │
│  │    └── ocp_incremental_update.py                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                          │                                       │
│                          │ ./deploy-dags.sh                      │
│                          ▼                                       │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  qubinode_navigator                                              │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  airflow/dags/                                           │    │
│  │    ├── example_kcli_*.py        (qubinode examples)      │    │
│  │    ├── ocp_initial_deployment.py (deployed from ocp4)    │    │
│  │    └── ocp_incremental_update.py (deployed from ocp4)    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                          │                                       │
│                          │ Volume mount                          │
│                          ▼                                       │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  Airflow Scheduler Container                             │    │
│  │    /opt/airflow/dags/                                    │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## Related Documentation

- [ADR 0012: Airflow DAG Orchestration](../docs/adrs/0012-airflow-dag-orchestration.md)
- [ADR 0013: Flexible Execution Model](../docs/adrs/0013-flexible-execution-model.md)
- [ADR 0014: Airflow Replaces kcli-pipelines](../docs/adrs/0014-airflow-replaces-kcli-pipelines.md)
- [ADR 0016: Trusted Certificate Management](../docs/adrs/0016-trusted-certificate-management.md)
- [qubinode_navigator Airflow Documentation](https://github.com/Qubinode/qubinode_navigator/tree/main/airflow)

## Contributing

When adding new DAGs:

1. Follow the existing naming convention: `ocp_<workflow_name>.py`
2. Include comprehensive docstrings
3. Add appropriate tags for filtering
4. Set `schedule_interval=None` for manual-only DAGs
5. Use `BashOperator` for Ansible playbook execution
6. Include proper error handling and logging
7. Update this README with the new DAG details
