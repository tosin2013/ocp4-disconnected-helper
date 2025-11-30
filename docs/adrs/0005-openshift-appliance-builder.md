# ADR 0005: OpenShift Appliance Builder Integration

**Status:** Accepted  
**Date:** 2025-11-29  
**Deciders:** Platform Team  
**PRD Reference:** Section 5.1 - New Ansible Playbook for Appliance Building

## Context

Deploying OpenShift in fully disconnected environments traditionally requires:
1. Setting up a bootstrap node with network access
2. Configuring PXE boot or ISO-based installation
3. Manual intervention during the installation process

The **OpenShift Appliance Builder** provides an alternative approach by creating self-contained disk images that include all necessary components for installation.

## Decision

Support two disconnected deployment methods, each with install and upgrade workflows:

1. **Appliance Method** - Self-contained disk image (no registry infrastructure needed)
2. **Agent + Mirror Registry Method** - Agent-based installer with mirrored registry

Implementation is provided via:
- Ansible playbook `build-appliance.yml` in [openshift-agent-install](https://github.com/tosin2013/openshift-agent-install)
- Airflow DAGs for orchestration in kcli-pipelines

### Target Version and Upgrade Path

- **Initial Deployment**: OCP 4.19 (current stable)
- **First Upgrade**: OCP 4.20 via upgrade-iso or mirror sync
- **Future Upgrade**: OCP 4.21 when released

## Two Disconnected Deployment Methods

| Method | Install | Upgrade | Best For |
|--------|---------|---------|----------|
| **Appliance** | `appliance.iso` + `agentconfig.noarch.iso` | `upgrade-4.20.iso` + MachineConfig | Edge, remote sites, true air-gap |
| **Agent + Mirror Registry** | `agent.x86_64.iso` | Sync new version to registry, standard OCP upgrade | Data centers with registry infrastructure |

## Install and Upgrade Workflows

### Method 1: Appliance (Self-Contained Air-Gap)

#### Install (4.19)
```
openshift_appliance_build DAG (build_type=appliance, ocp_version=4.19)
  └── build-appliance.yml
        ├── openshift-appliance build → appliance.iso
        └── openshift-install agent create config-image → agentconfig.noarch.iso

Deploy:
  1. Boot from appliance.iso (clones to disk)
  2. Mount agentconfig.noarch.iso
  3. Cluster installs automatically
```

#### Upgrade (4.19 → 4.20)
```
openshift_appliance_build DAG (build_type=upgrade-iso, ocp_version=4.20)
  └── build-appliance.yml
        └── openshift-appliance build upgrade-iso → upgrade-4.20.iso + upgrade-machine-config-4.20.yaml

Deploy:
  1. Attach upgrade-4.20.iso to each node
  2. oc apply -f upgrade-machine-config-4.20.yaml
  3. Nodes reboot and upgrade to 4.20
```

### Method 2: Agent + Mirror Registry (Disconnected with Infrastructure)

#### Install (4.19)
```
Prerequisites:
  - mirror_registry_deployment DAG (deploy registry)
  - ocp_daily_sync DAG (mirror 4.19 images)

openshift_agent_install DAG (ocp_version=4.19)
  └── create-iso.sh (with disconnected_registries)
        └── agent.x86_64.iso

Deploy:
  1. Boot from agent.x86_64.iso
  2. Cluster installs, pulls images from mirror registry
```

#### Upgrade (4.19 → 4.20)
```
ocp_daily_sync DAG (ocp_version=4.20)
  └── Mirrors 4.20 images to registry

On cluster:
  1. oc adm upgrade --to=4.20.x
  2. Cluster pulls new images from mirror registry
  3. Standard OCP upgrade process
```

## Rationale

### Why Two Methods?

| Consideration | Appliance | Agent + Mirror Registry |
|---------------|-----------|------------------------|
| Infrastructure needed | None | Registry server |
| Image size | Large (100+ GB) | Small ISO, images in registry |
| Upgrade process | Attach ISO, apply MachineConfig | Standard OCP upgrade |
| Best for | Edge, remote, true air-gap | Data centers, multiple clusters |

### Why Appliance-Based Deployment?
1. **Simplified air-gap installation**: Single disk image contains everything needed
2. **Reproducibility**: Same image can deploy identical clusters
3. **Reduced complexity**: No PXE, DHCP, or bootstrap node required
4. **Edge-friendly**: Compact 3-node architecture suits edge deployments

### Why Agent + Mirror Registry?
1. **Shared infrastructure**: One registry serves multiple clusters
2. **Standard upgrades**: Use familiar `oc adm upgrade` workflow
3. **Incremental updates**: Only sync changed images
4. **Flexibility**: Add operators and images to registry as needed

## Consequences

### Positive
- **Two deployment options**: Choose based on environment constraints
- **Complete lifecycle**: Both install and upgrade workflows documented
- **Automation**: DAG orchestration for repeatable deployments
- **Offline-first**: Both methods designed for disconnected scenarios

### Negative
- **Disk space**: Large appliance images (100+ GB)
- **Build time**: Initial appliance build is time-consuming
- **Complexity**: Two methods to maintain and document
- **Dependencies**: Different tooling for each method

## Implementation

### Playbook Location
The `build-appliance.yml` playbook is located in [openshift-agent-install](https://github.com/tosin2013/openshift-agent-install):
```
/root/openshift-agent-install/
├── playbooks/
│   ├── build-appliance.yml      # Appliance method
│   └── create-manifests.yml     # Existing manifest templating
├── hack/
│   ├── create-iso.sh            # Agent ISO method
│   ├── deploy-on-kvm.sh         # Lab testing
│   └── destroy-on-kvm.sh        # Cleanup
└── examples/
    ├── appliance-sno-4.19/      # Appliance SNO example
    ├── appliance-upgrade-4.20/  # Upgrade example
    └── sno-disconnected/        # Agent + registry example
```

### DAG Orchestration
DAGs in kcli-pipelines:
- `openshift_appliance_build.py` - Appliance install and upgrade
- `openshift_agent_install.py` - Agent + mirror registry install

### Required Dependencies (Appliance Method)
```yaml
dependencies:
  - podman
  - libguestfs-tools (for virt-resize)
```

### Playbook Variables
```yaml
# build-appliance.yml variables
build_type: "appliance"        # appliance, live-iso, upgrade-iso
ocp_version: "4.19"
ocp_channel: "stable"
disk_size_gb: 200
target_device: "/dev/sda"
assets_dir: "/opt/appliance-assets"
```

## Integration Points

### With openshift-agent-install
- Playbook and examples hosted in openshift-agent-install repo
- Uses existing `create-manifests.yml` for config-image generation
- Leverages hack scripts for KVM lab testing

### With ocp4-disconnected-helper
- Agent + Mirror Registry method uses `ocp_daily_sync` DAG for image mirroring
- Uses registries deployed by `mirror_registry_deployment` DAG
- Certificates from `step_ca_deployment` DAG

### With kcli-pipelines
- DAGs orchestrate playbook execution
- Clone repos to target machine
- Optional KVM deployment for lab testing

## Related ADRs
- ADR 0003: oc-mirror for Image Mirroring
- ADR 0006: Lifecycle Management Strategy
- ADR 0007: 3-Node Compact Cluster Architecture
- ADR 0019: OpenShift Agent-Install Integration

## References

- [OpenShift Appliance GitHub](https://github.com/openshift/appliance)
- [OpenShift Appliance User Guide](https://github.com/openshift/appliance/blob/main/docs/user-guide.md)
- [Upgrade ISO Documentation](https://github.com/openshift/appliance/blob/main/docs/user-guide.md#upgrade-iso)
- [OpenShift Agent Install](https://github.com/tosin2013/openshift-agent-install)
- [ocp4-disconnected-helper](https://github.com/tosin2013/ocp4-disconnected-helper)
