# ADR 0018: Registry Deployment on Dedicated VM via kcli

## Status
Proposed

## Date
2025-11-27

## Context

The current playbooks (`setup-mirror-registry.yml`, `setup-harbor-registry.yml`, `setup-jfrog-registry.yml`) assume the registry runs on `localhost`. However, in production disconnected environments:

1. **Separation of concerns** - The orchestration host (running Airflow/qubinode_navigator) should not also host the registry
2. **Resource isolation** - Registries require significant disk I/O and storage (200GB+)
3. **Network architecture** - Registry needs to be accessible from multiple hosts (build host, OCP nodes)
4. **Persistence** - Registry data must survive orchestration host rebuilds
5. **Scalability** - Registry VM can be sized independently

### Current Architecture (Problematic)
```
┌─────────────────────────────────────────────────────────────┐
│  Orchestration Host (qubinode_navigator)                     │
│  ├── Airflow                                                 │
│  ├── oc-mirror                                               │
│  ├── Registry (mirror-registry/harbor) ← WRONG LOCATION     │
│  └── Appliance Builder                                       │
└─────────────────────────────────────────────────────────────┘
```

### Proposed Architecture
```
┌─────────────────────────────────────────────────────────────┐
│  Orchestration Host (qubinode_navigator)                     │
│  ├── Airflow + MCP Server                                    │
│  ├── oc-mirror (downloads to TAR)                            │
│  └── Appliance Builder                                       │
└──────────────────────────┬──────────────────────────────────┘
                           │ Ansible over SSH
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  Registry VM (deployed via kcli)                             │
│  ├── mirror-registry / Harbor / JFrog                        │
│  ├── TLS certificates                                        │
│  └── Persistent storage (200GB+ disk)                        │
│                                                              │
│  Accessible at: registry.disconnected.local:8443             │
└─────────────────────────────────────────────────────────────┘
```

## Decision

Modify the registry deployment workflow to:

1. **Create a dedicated Registry VM** using kcli via qubinode_navigator
2. **Deploy registry software** to the VM using Ansible over SSH
3. **Update inventory** to target the registry VM, not localhost
4. **Store registry credentials** securely for use by other playbooks

### Implementation

#### 1. New Playbook: `provision-registry-vm.yml`
Uses kcli (via qubinode_navigator) to create the registry VM:

```yaml
# Variables
registry_vm_name: "registry"
registry_vm_image: "centos10stream"
registry_vm_memory: 8192      # 8GB RAM
registry_vm_cpus: 4
registry_vm_disk_size: 500    # 500GB for images
registry_vm_network: "default"
```

#### 2. Updated Inventory Structure
```ini
[orchestration]
localhost ansible_connection=local

[registry]
registry.disconnected.local ansible_user=root

[all:vars]
registry_hostname=registry.disconnected.local
registry_port=8443
```

#### 3. Modified Registry Playbooks
Change `hosts: localhost` to `hosts: registry`:

```yaml
- name: Setup Mirror Registry
  hosts: registry    # ← Changed from localhost
  become: true
  ...
```

#### 4. Airflow DAG Updates
Add VM provisioning task before registry setup:

```
validate_environment 
    → provision_registry_vm (NEW)
    → setup_certificates 
    → setup_registry 
    → download_to_tar 
    → push_to_registry 
    → build_appliance
```

### VM Specifications

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4 cores |
| RAM | 4 GB | 8 GB |
| Disk | 200 GB | 500 GB |
| Network | 1 NIC | 1 NIC |
| OS | CentOS Stream 10 | CentOS Stream 10 |

## Consequences

### Positive

- **Proper isolation** - Registry runs independently of orchestration
- **Scalable storage** - VM disk can be sized for image storage needs
- **Survivability** - Registry persists if orchestration host is rebuilt
- **Network accessibility** - Other hosts can pull from registry
- **Production-ready** - Matches real-world deployment patterns

### Negative

- **Added complexity** - Extra VM to manage
- **Resource overhead** - Requires additional compute resources
- **Network dependency** - SSH connectivity required between hosts
- **DNS/hostname** - Requires proper name resolution

### Trade-offs

| Scenario | Recommendation |
|----------|----------------|
| Development/testing | localhost OK for quick tests |
| Lab environment | Dedicated VM recommended |
| Production | Dedicated VM required |
| Air-gapped | Dedicated VM required |

## Alternatives Considered

### 1. Container on Orchestration Host
**Current approach** - Registry runs as container on localhost.
- ✅ Simple setup
- ❌ Resource contention
- ❌ Not production-ready

### 2. Separate Physical Host
- ✅ Maximum isolation
- ❌ Requires additional hardware
- ❌ Not automated

### 3. Registry on OCP Cluster
- ✅ Uses cluster resources
- ❌ Chicken-and-egg problem (need registry to deploy cluster)
- ❌ Not suitable for initial deployment

## Implementation Tasks

1. [ ] Create `playbooks/provision-registry-vm.yml`
2. [ ] Create `templates/registry-vm-cloudinit.yml.j2`
3. [ ] Update `playbooks/inventory` with registry host group
4. [ ] Modify `setup-mirror-registry.yml` to target registry host
5. [ ] Modify `setup-harbor-registry.yml` to target registry host
6. [ ] Modify `setup-jfrog-registry.yml` to target registry host
7. [ ] Update `setup-certificates.yml` to generate certs for registry VM hostname
8. [ ] Update Airflow DAG with `provision_registry_vm` task
9. [ ] Create `extra_vars/registry-vm-example.yml`
10. [ ] Update documentation

## Integration with qubinode_navigator

The registry VM will be provisioned using qubinode_navigator's kcli integration:

```python
# Via MCP server
mcp4_create_vm(
    name="registry",
    image="centos10stream",
    memory=8192,
    cpus=4,
    disk_size=500
)
```

Or via Airflow DAG:
```python
provision_registry_vm = BashOperator(
    task_id='provision_registry_vm',
    bash_command='''
    kcli create vm registry \
        -i centos10stream \
        -P memory=8192 \
        -P numcpus=4 \
        -P disks=[500]
    ''',
)
```

## Related ADRs

- [ADR 0004: Dual Registry Support](0004-dual-registry-support.md)
- [ADR 0011: qubinode_navigator Integration](0011-qubinode-navigator-integration.md)
- [ADR 0016: Trusted Certificate Management](0016-trusted-certificate-management.md)
- [ADR 0017: Quay Mirror Registry](0017-quay-mirror-registry.md)

## References

- [kcli documentation](https://kcli.readthedocs.io/)
- [qubinode_navigator VM provisioning](https://github.com/Qubinode/qubinode_navigator)
- [mirror-registry requirements](https://docs.openshift.com/container-platform/latest/installing/disconnected_install/installing-mirroring-creating-registry.html)
