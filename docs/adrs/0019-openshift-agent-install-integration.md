# ADR 0019: OpenShift Agent-Install Integration

**Status:** Accepted  
**Date:** 2025-11-29  
**Deciders:** Platform Team  
**Related ADRs:** ADR 0005, ADR 0012

## Context

The [openshift-agent-install](https://github.com/tosin2013/openshift-agent-install) repository provides utilities for the OpenShift Agent-Based Installer, supporting bare metal, vSphere, and platform=none deployments in SNO/3-Node/HA configurations.

To provide a complete disconnected OpenShift deployment solution, we need to integrate:
1. **ocp4-disconnected-helper** - Image mirroring and registry management
2. **openshift-agent-install** - Cluster configuration and ISO generation
3. **openshift-appliance** - Self-contained disk image building
4. **kcli-pipelines** - DAG orchestration

## Decision

Create two Airflow DAGs that orchestrate disconnected OpenShift deployments:

1. **`openshift_appliance_build`** - Builds self-contained appliance ISOs
2. **`openshift_agent_install`** - Builds agent ISOs using mirror registry

Both DAGs:
- Clone required repositories to the target machine
- Execute Ansible playbooks for configuration
- Support optional KVM deployment for lab testing
- Provide install and upgrade workflows

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                     EXISTING DAGs                                   │
├─────────────────────────────────────────────────────────────────────┤
│  ocp_daily_sync              - Mirror images to registries          │
│  mirror_registry_deployment  - Deploy Quay/Harbor/JFrog             │
│  step_ca_deployment          - Deploy Step-CA for certificates      │
│  freeipa_deployment          - Deploy FreeIPA for DNS               │
└─────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      NEW DAGs                                       │
├─────────────────────────────────────────────────────────────────────┤
│  openshift_appliance_build                                          │
│  └── Self-contained appliance (no registry needed)                  │
│      Best for: Edge, remote sites, true air-gap                     │
│                                                                     │
│  openshift_agent_install                                            │
│  └── Agent-based with mirror registry                               │
│      Best for: Data centers with registry infrastructure            │
│      Requires: ocp_daily_sync + mirror_registry_deployment          │
└─────────────────────────────────────────────────────────────────────┘
```

## DAG Specifications

### openshift_appliance_build DAG

**Purpose:** Build self-contained appliance disk images and ISOs for true air-gap deployments.

**Parameters:**
```python
params = {
    'action': 'install',           # install, upgrade
    'build_type': 'appliance',     # appliance, live-iso, upgrade-iso
    'ocp_version': '4.19',         # 4.19, 4.20, 4.21
    'cluster_config': 'examples/appliance-sno-4.19',
    'deploy_to_kvm': False,        # optional lab testing
}
```

**Tasks:**
1. `clone_repos` - Clone openshift-agent-install to target machine
2. `validate_prerequisites` - Check podman, disk space, pull secret
3. `build_appliance` - Run build-appliance.yml playbook
4. `generate_config_image` - Create agentconfig.noarch.iso
5. `deploy_to_kvm` (optional) - Deploy VMs for testing

**Outputs:**
- Install: `appliance.iso`, `agentconfig.noarch.iso`
- Upgrade: `upgrade-4.20.iso`, `upgrade-machine-config-4.20.yaml`

### openshift_agent_install DAG

**Purpose:** Build agent ISOs for disconnected deployments using mirror registry.

**Prerequisites:**
- `mirror_registry_deployment` DAG completed
- `ocp_daily_sync` DAG completed (images mirrored)

**Parameters:**
```python
params = {
    'ocp_version': '4.19',
    'registry_server': 'mirror-registry.example.com:8443',
    'cluster_config': 'examples/sno-disconnected',
    'deploy_to_kvm': False,        # optional lab testing
}
```

**Tasks:**
1. `clone_repos` - Clone openshift-agent-install to target machine
2. `validate_registry` - Check mirror registry is accessible
3. `inject_disconnected_config` - Add disconnected_registries to cluster.yml
4. `create_iso` - Run hack/create-iso.sh
5. `deploy_to_kvm` (optional) - Deploy VMs for testing

**Outputs:**
- `agent.x86_64.iso`

## Repository Integration

### openshift-agent-install Structure
```
/root/openshift-agent-install/
├── playbooks/
│   ├── build-appliance.yml      # NEW - Appliance build playbook
│   └── create-manifests.yml     # Existing - Manifest templating
├── hack/
│   ├── create-iso.sh            # Agent ISO creation
│   ├── deploy-on-kvm.sh         # KVM deployment
│   ├── destroy-on-kvm.sh        # KVM cleanup
│   └── watch-and-reboot-kvm-vms.sh
├── examples/
│   ├── appliance-sno-4.19/      # NEW - Appliance SNO
│   │   ├── cluster.yml
│   │   ├── nodes.yml
│   │   └── appliance-vars.yml
│   ├── appliance-upgrade-4.20/  # NEW - Upgrade example
│   │   └── appliance-vars.yml
│   ├── sno-disconnected/        # NEW - Agent + registry
│   │   ├── cluster.yml
│   │   └── nodes.yml
│   └── sno-bond0-signal-vlan/   # Existing examples
└── docs/
    └── adr/
        └── 0014-disconnected-deployment-methods.md  # NEW
```

### kcli-pipelines DAGs
```
/root/kcli-pipelines/dags/
├── openshift_appliance_build.py  # NEW
├── openshift_agent_install.py    # NEW
├── mirror_registry_deployment.py # Existing
├── ocp_daily_sync.py             # Existing (in ocp4-disconnected-helper)
└── ...
```

## Workflow Examples

### Appliance Install (4.19)
```bash
# Via DAG
airflow dags trigger openshift_appliance_build \
  --conf '{"build_type": "appliance", "ocp_version": "4.19", "cluster_config": "examples/appliance-sno-4.19"}'

# Or manually
cd /root/openshift-agent-install
ansible-playbook playbooks/build-appliance.yml \
  -e @examples/appliance-sno-4.19/cluster.yml \
  -e @examples/appliance-sno-4.19/nodes.yml \
  -e @examples/appliance-sno-4.19/appliance-vars.yml
```

### Appliance Upgrade (4.19 → 4.20)
```bash
# Via DAG
airflow dags trigger openshift_appliance_build \
  --conf '{"build_type": "upgrade-iso", "ocp_version": "4.20"}'

# Then on cluster
oc apply -f upgrade-machine-config-4.20.yaml
```

### Agent + Registry Install (4.19)
```bash
# Prerequisites
airflow dags trigger mirror_registry_deployment
airflow dags trigger ocp_daily_sync --conf '{"ocp_version": "4.19"}'

# Then
airflow dags trigger openshift_agent_install \
  --conf '{"ocp_version": "4.19", "cluster_config": "examples/sno-disconnected"}'
```

### Agent + Registry Upgrade (4.19 → 4.20)
```bash
# Mirror new version
airflow dags trigger ocp_daily_sync --conf '{"ocp_version": "4.20"}'

# Then on cluster
oc adm upgrade --to=4.20.x
```

## Consequences

### Positive
- **Complete solution**: Both install and upgrade workflows
- **Two deployment options**: Choose based on environment
- **Automation**: DAG orchestration for repeatability
- **Lab testing**: Optional KVM deployment for validation
- **Reuse**: Leverages existing openshift-agent-install infrastructure

### Negative
- **Multiple repos**: Code spread across three repositories
- **Coordination**: DAG dependencies must be managed
- **Complexity**: Two methods to maintain

## Related ADRs
- ADR 0005: OpenShift Appliance Builder Integration
- ADR 0012: Airflow DAG Orchestration
- ADR 0003: oc-mirror for Image Mirroring
- ADR 0017: Quay Mirror Registry

## References

- [OpenShift Agent Install](https://github.com/tosin2013/openshift-agent-install)
- [OpenShift Appliance](https://github.com/openshift/appliance)
- [ocp4-disconnected-helper](https://github.com/tosin2013/ocp4-disconnected-helper)
- [kcli-pipelines](https://github.com/tosin2013/kcli-pipelines)










