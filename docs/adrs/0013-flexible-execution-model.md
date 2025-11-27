# ADR 0013: Flexible Execution Model

**Status:** Accepted  
**Date:** 2025-11-25  
**Deciders:** Platform Team  
**PRD Reference:** Section 3.2 - Objectives

## Context

Users of ocp4-disconnected-helper have varying infrastructure setups:

1. **Full stack users**: Running qubinode_navigator with Airflow for orchestration
2. **Standalone users**: Running ocp4-disconnected-helper directly without qubinode_navigator
3. **CI/CD users**: Integrating with existing pipelines (GitHub Actions, Jenkins, GitLab CI)
4. **Manual users**: Running playbooks ad-hoc for testing or one-off deployments

The project must support all these use cases without forcing a specific execution method.

## Decision

Implement a **flexible execution model** with three tiers:

### Tier 1: Manual Execution (Always Available)
- Direct `ansible-playbook` commands
- Shell wrapper script (`cicd.sh`)
- No additional infrastructure required

### Tier 2: Airflow DAGs (Optional)
- Pre-built DAGs for common workflows
- Requires Airflow (via qubinode_navigator or standalone)
- Provides scheduling, monitoring, and retry capabilities

### Tier 3: CI/CD Integration (Optional)
- GitHub Actions workflows
- GitLab CI templates
- Jenkins pipeline examples

## Rationale

### Why Multiple Execution Methods?

| User Type | Preferred Method | Reason |
|-----------|------------------|--------|
| Lab/Demo | Manual | Quick setup, no overhead |
| Production | Airflow DAGs | Monitoring, scheduling, audit |
| Enterprise | CI/CD | Integration with existing tools |
| Development | Manual + CI | Fast iteration with PR validation |

### Design Principles

1. **Playbooks are the source of truth**: All execution methods call the same Ansible playbooks
2. **No lock-in**: Users can switch methods without changing playbooks
3. **Progressive enhancement**: Start manual, add orchestration as needed
4. **Documentation-first**: Clear docs for each execution method

## Consequences

### Positive
- **Accessibility**: Low barrier to entry for new users
- **Flexibility**: Adapts to existing infrastructure
- **Consistency**: Same playbooks regardless of execution method
- **Scalability**: Can grow from manual to fully orchestrated

### Negative
- **Documentation overhead**: Must maintain docs for all methods
- **Testing complexity**: Need to validate all execution paths
- **Feature parity**: Some features may be easier in one method

## Implementation

### Directory Structure
```
ocp4-disconnected-helper/
├── playbooks/                    # Core automation (Tier 1)
│   ├── download-to-tar.yml
│   ├── push-tar-to-registry.yml
│   ├── setup-harbor-registry.yml
│   ├── setup-jfrog-registry.yml
│   ├── build-appliance.yml
│   └── update-cluster.yml
├── cicd.sh                       # Shell wrapper (Tier 1)
├── airflow/                      # Airflow DAGs (Tier 2)
│   ├── dags/
│   └── README.md
├── .github/workflows/            # GitHub Actions (Tier 3)
│   ├── lint.yml
│   ├── deploy.yml
│   └── update.yml
└── docs/
    ├── manual-execution.md       # Tier 1 docs
    ├── airflow-setup.md          # Tier 2 docs
    └── cicd-integration.md       # Tier 3 docs
```

---

## Tier 1: Manual Execution

### Quick Start
```bash
# Clone the repository
git clone https://github.com/tosin2013/ocp4-disconnected-helper.git
cd ocp4-disconnected-helper

# Set up variables
cp extra_vars/example.yml extra_vars/my-env.yml
vim extra_vars/my-env.yml

# Run playbooks directly
ansible-playbook playbooks/download-to-tar.yml \
    -e @extra_vars/my-env.yml \
    -e ocp_release_version=4.20.0 \
    -e clean_mirror_path=true
```

### Using cicd.sh Wrapper
```bash
# Initial deployment
./cicd.sh deploy --version 4.20.0 --registry harbor

# Incremental update
./cicd.sh update --version 4.20.1

# Health check
./cicd.sh health-check
```

### Workflow: Initial Deployment (Manual)
```bash
# Step 1: Download content (full mirror)
ansible-playbook playbooks/download-to-tar.yml \
    -e ocp_release_version=4.20.0 \
    -e clean_mirror_path=true

# Step 2: Setup registry
ansible-playbook playbooks/setup-harbor-registry.yml

# Step 3: Push to registry
ansible-playbook playbooks/push-tar-to-registry.yml

# Step 4: Build appliance
ansible-playbook playbooks/build-appliance.yml \
    -e ocp_release_version=4.20.0
```

### Workflow: Incremental Update (Manual)
```bash
# Step 1: Download incremental content
ansible-playbook playbooks/download-to-tar.yml \
    -e ocp_release_version=4.20.1 \
    -e clean_mirror_path=false

# Step 2: Push to registry
ansible-playbook playbooks/push-tar-to-registry.yml

# Step 3: Update cluster
ansible-playbook playbooks/update-cluster.yml \
    -e update_ocp_release_version=4.20.1 \
    -e cluster_kubeconfig=/path/to/kubeconfig
```

---

## Tier 2: Airflow DAGs

### Prerequisites
- Airflow deployed (via qubinode_navigator or standalone)
- DAGs mounted to Airflow's dags folder

### Setup with qubinode_navigator
```bash
# Deploy Airflow via qubinode_navigator
cd /root/qubinode_navigator/airflow
./deploy-airflow.sh

# Mount ocp4-disconnected-helper DAGs
ln -s /root/ocp4-disconnected-helper/airflow/dags \
      /opt/airflow/dags/ocp4-disconnected-helper
```

### Setup Standalone Airflow
```bash
# Using Docker Compose
cd /root/ocp4-disconnected-helper/airflow
docker-compose up -d

# Or using podman
podman-compose up -d
```

### Available DAGs

| DAG | Description | Trigger |
|-----|-------------|---------|
| `ocp_initial_deployment` | Full mirror → registry → appliance | Manual |
| `ocp_incremental_update` | Delta sync → registry → cluster update | Manual/Scheduled |
| `ocp_registry_setup` | Configure Harbor or JFrog | Manual |
| `ocp_health_check` | Validate mirror and registry state | Scheduled (daily) |

### Triggering DAGs

**Via Web UI:**
1. Navigate to http://localhost:8888
2. Find the DAG (e.g., `ocp_initial_deployment`)
3. Click the play button ▶️
4. Configure parameters and trigger

**Via CLI:**
```bash
# Trigger with default parameters
airflow dags trigger ocp_initial_deployment

# Trigger with custom parameters
airflow dags trigger ocp_initial_deployment \
    --conf '{"ocp_version": "4.20.0", "registry_type": "harbor"}'
```

**Via MCP Server (AI-assisted):**
```bash
# Using qubinode_navigator's Airflow MCP server
# Natural language: "Trigger the initial deployment DAG for OCP 4.20"
```

### Monitoring
- **Web UI**: Real-time task status at http://localhost:8888
- **Logs**: Task logs visible in UI or via `airflow tasks logs`
- **Alerts**: Configure email/Slack notifications on failure

---

## Tier 3: CI/CD Integration

### GitHub Actions
```yaml
# .github/workflows/deploy.yml
name: Deploy OCP Disconnected
on:
  workflow_dispatch:
    inputs:
      ocp_version:
        description: 'OpenShift version'
        required: true
        default: '4.20.0'
      deployment_type:
        description: 'initial or update'
        required: true
        default: 'initial'

jobs:
  deploy:
    runs-on: self-hosted
    steps:
      - uses: actions/checkout@v4
      
      - name: Run deployment
        run: |
          if [ "${{ inputs.deployment_type }}" == "initial" ]; then
            ./cicd.sh deploy --version ${{ inputs.ocp_version }}
          else
            ./cicd.sh update --version ${{ inputs.ocp_version }}
          fi
```

### GitLab CI
```yaml
# .gitlab-ci.yml
stages:
  - deploy
  - update

deploy:initial:
  stage: deploy
  script:
    - ./cicd.sh deploy --version ${OCP_VERSION:-4.20.0}
  when: manual
  tags:
    - disconnected-runner

deploy:update:
  stage: update
  script:
    - ./cicd.sh update --version ${OCP_VERSION:-4.20.0}
  when: manual
  tags:
    - disconnected-runner
```

### Jenkins Pipeline
```groovy
// Jenkinsfile
pipeline {
    agent { label 'disconnected' }
    
    parameters {
        string(name: 'OCP_VERSION', defaultValue: '4.20.0')
        choice(name: 'DEPLOYMENT_TYPE', choices: ['initial', 'update'])
    }
    
    stages {
        stage('Deploy') {
            steps {
                sh "./cicd.sh ${params.DEPLOYMENT_TYPE} --version ${params.OCP_VERSION}"
            }
        }
    }
}
```

---

## Decision Matrix: Which Method to Use?

| Scenario | Recommended Method | Reason |
|----------|-------------------|--------|
| First-time setup / testing | Manual (Tier 1) | Simplest, no dependencies |
| Production with scheduling | Airflow (Tier 2) | Monitoring, retries, audit |
| Existing CI/CD infrastructure | CI/CD (Tier 3) | Integration with current tools |
| Air-gapped with no orchestration | Manual (Tier 1) | Minimal footprint |
| Multiple clusters to manage | Airflow (Tier 2) | Centralized management |
| PR validation / linting | CI/CD (Tier 3) | Automated checks |

---

## Migration Paths

### Manual → Airflow
1. Deploy Airflow (via qubinode_navigator or standalone)
2. Mount DAGs from `airflow/dags/`
3. Test DAGs with same parameters used manually
4. Transition to DAG-based execution

### Manual → CI/CD
1. Copy workflow templates from `.github/workflows/`
2. Configure self-hosted runner with access to infrastructure
3. Set up secrets for credentials
4. Trigger workflows instead of manual commands

### Airflow → CI/CD (or vice versa)
- Both call the same playbooks
- Simply change the triggering mechanism
- No playbook modifications needed

## Related ADRs
- ADR 0002: Ansible as Automation Framework
- ADR 0008: GitHub Actions Automation
- ADR 0011: qubinode_navigator Integration
- ADR 0012: Airflow DAG Orchestration Strategy
