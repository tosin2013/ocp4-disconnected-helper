# ADR 0021: Deprecate Airflow and Adopt Ansible Automation Platform (AAP)

**Status:** Accepted  
**Date:** 2026-06-02  
**Deciders:** Platform Team, Product Owner (Tosin)  
**Supersedes:** ADR 0012 (Airflow DAG Orchestration), ADR 0014 (Airflow Replaces kcli-pipelines)  
**PRD Reference:** PRD v4.21.0 Section 4 - Execution Tiers

## Context

The ocp4-disconnected-helper project currently uses **Apache Airflow** (community edition) for workflow orchestration, with ~2000+ lines of production DAG code implementing:
- `ocp_initial_deployment.py` - Full deployment workflow (8 tasks)
- `ocp_incremental_update.py` - Cluster update workflow
- `ocp_registry_sync.py` - Registry synchronization
- `ocp_harbor_registry.py` - Harbor deployment
- `ocp_jfrog_agent_deployment.py` - JFrog deployment

This architecture was formalized in ADR 0012 and ADR 0014, establishing Airflow as the accepted orchestration layer integrated with qubinode_navigator.

However, the **PRD v4.21.0** (dated 2026-05-28) introduces new strategic requirements:

1. **Enterprise Support Requirements**: Need for Red Hat-supported orchestration platform
2. **Standardization on AAP**: Ansible Automation Platform 2.5 as the primary advanced orchestration engine
3. **All-VMs-on-KVM Development Model**: AAP must be deployable as a single KVM VM for local testing
4. **Two-Tier Execution Model**: Shell/Ansible (Tier 1) + AAP (Tier 2)
5. **Elimination of qubinode_navigator dependency**: Move to pure Ansible + AAP stack

## Decision

**Deprecate Apache Airflow** and **adopt Red Hat Ansible Automation Platform (AAP) 2.6** as the orchestration layer for ocp4-disconnected-helper.

**Update 2026-06-04**: AAP 2.6 is now the recommended version (released 2025-10-08). See "AAP Version Selection" section below.

### Key Changes

1. **Remove Airflow DAGs**: Archive all DAG files in `airflow/dags/` directory
2. **Implement AAP Job Templates**: Convert existing DAG workflows to AAP Job Templates
3. **Deploy AAP on KVM**: Create `provision-aap-vm.yml` playbook using `community.libvirt`
4. **Maintain Backward Compatibility**: Preserve Tier 1 (shell + ansible-playbook CLI) execution
5. **Tag Legacy Code**: Tag current main branch as `v4.20.0-airflow` before migration

## AAP Version Selection (Updated 2026-06-04)

### AAP 2.6 vs AAP 2.5

| Feature | AAP 2.5 | AAP 2.6 (Recommended) |
|---------|---------|------------------------|
| **Release Date** | 2024-11 | **2025-10-08** |
| **RHEL Support** | RHEL 8.8+, RHEL 9.2+ | **RHEL 9.2+, RHEL 10** |
| **Installation Method** | Containerized + RPM | **Containerized only** (RHEL 9) |
| **RPM Installer** | Deprecated | **Last version** (RHEL 9 only) |
| **Ansible Core** | 2.16+ | 2.16+ |
| **Lifecycle** | Standard | Extended support |
| **Maturity** | Stable | Latest stable |

**Recommendation**: Deploy **AAP 2.6** for new installations.

**Why AAP 2.6?**
- Future-proof: RPM installation method deprecated (containerized is primary)
- Extended RHEL support (RHEL 9 + RHEL 10)
- Latest features and security updates
- Containerized-first architecture aligns with modern DevOps

**References**:
- [AAP 2.6 System Requirements](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/rpm_installation/platform-system-requirements)
- [AAP 2.6 Containerized Installation](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html-single/containerized_installation/index)
- [AAP 2.6 Installation Guide Blog](https://www.redhat.com/en/blog/installation-and-upgrade-guide-ansible-automation-platform-26)

## Rationale

### Why Deprecate Airflow?

| Concern | Airflow (Current) | AAP (New) |
|---------|-------------------|-----------|
| **Enterprise Support** | Community only, no Red Hat support | Fully supported by Red Hat |
| **Integration with RHEL ecosystem** | External dependency | Native to Red Hat portfolio |
| **Licensing** | Apache 2.0 (free) | Requires AAP subscription |
| **Learning curve** | Python DAGs + Airflow concepts | Ansible-native (existing team skill) |
| **Dependency management** | Python packages, containers | Containerized AAP (managed) |
| **UI/UX** | Generic workflow UI | Tailored for Ansible workflows |
| **RBAC** | Airflow native | AAP native with LDAP/AD integration |
| **Audit/Compliance** | Airflow logs | AAP audit logs + compliance reporting |

### Why Adopt AAP?

1. **Red Hat Support**: Enterprise SLA and technical support for production environments
2. **Unified Stack**: Ansible Core (automation) + AAP (orchestration) = single vendor
3. **KVM Deployability**: AAP 2.5 containerized install supports single-node deployment on KVM (4 vCPU, 16GB RAM) [PRD Reference 1]
4. **Job Templates = DAGs**: AAP Job Templates provide equivalent workflow orchestration
5. **Development → Production Parity**: AAP on KVM (dev) → AAP on bare metal (prod) using identical job templates
6. **Elimination of qubinode_navigator**: No external dependency for orchestration layer

### Migration Path from Airflow DAGs to AAP Job Templates

| Airflow DAG | AAP Job Template | Notes |
|-------------|------------------|-------|
| `ocp_initial_deployment.py` | `OCP Initial Deployment` | 8-task workflow → Workflow Job Template |
| `ocp_incremental_update.py` | `OCP Incremental Update` | Update workflow → Workflow Job Template |
| `ocp_registry_sync.py` | `Registry Sync` | Simple job template |
| `ocp_harbor_registry.py` | `Setup Harbor Registry` | Simple job template |
| `ocp_jfrog_agent_deployment.py` | `Deploy JFrog with Agent Install` | Workflow job template |

**Key Conversion Pattern:**
- **BashOperator calling playbook** → **AAP Job Template** (already native!)
- **DAG task dependencies** → **Workflow Job Template** (node-based workflow)
- **DAG params** → **Job Template survey** (runtime variables)
- **Airflow schedules** → **AAP schedules** (cron-based)

## Consequences

### Positive

- ✅ **Enterprise support**: Red Hat-backed platform for production
- ✅ **Unified vendor**: Single point of contact for Ansible + orchestration
- ✅ **KVM deployability**: Full dev/test environment on local workstation
- ✅ **Simpler dependency tree**: No Python/Airflow containers to manage
- ✅ **Ansible-native**: Team already knows Ansible, reduces learning curve
- ✅ **Compliance**: AAP provides better audit logging and compliance reporting
- ✅ **No qubinode_navigator dependency**: Standalone architecture

### Negative

- ⚠️ **Licensing cost**: AAP requires subscription (Airflow was free)
- ⚠️ **Migration effort**: ~2000+ lines of DAG code to rewrite as Job Templates
- ⚠️ **Timeline**: 3-6 month migration project (HIGH RISK)
- ⚠️ **MCP integration loss**: qubinode_navigator's MCP server integration not available in AAP
- ⚠️ **Community contributions**: Airflow has larger OSS community than AAP
- ⚠️ **Testing overhead**: Need to validate all converted workflows
- ⚠️ **Breaking change**: Users on v4.20.x relying on Airflow workflows will need migration plan

### Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Workflow conversion bugs** | HIGH | Extensive testing, parallel runs during migration |
| **AAP licensing unavailable** | HIGH | Maintain Tier 1 (shell/Ansible) as fallback |
| **Performance regression** | MEDIUM | Benchmark AAP vs Airflow workflow execution times |
| **User adoption resistance** | MEDIUM | Clear migration guide, tag legacy branch |
| **Lost MCP integration** | LOW | Future: AAP + MCP integration via custom execution environments |

## Implementation Plan

### Phase 1: Preservation (Week 1)
```bash
# Tag current state before any changes
git tag v4.20.0-airflow
git push origin v4.20.0-airflow

# Create deprecation notice
echo "⚠️ DEPRECATED: Airflow orchestration is deprecated as of v4.21.0" > airflow/DEPRECATED.md
```

### Phase 2: AAP VM Provisioning (Weeks 2-3)

Create `playbooks/provision-aap-vm.yml` using `community.libvirt`:

```yaml
---
- name: Provision AAP VM on KVM
  hosts: localhost
  gather_facts: yes
  vars:
    aap_vm_name: "aap-controller"
    aap_vm_memory: 16384  # 16GB RAM (minimum for AAP 2.5)
    aap_vm_cpus: 4
    aap_vm_disk_size: 60  # 60GB disk
    aap_vm_network: default
    rhel_iso_path: "/var/lib/libvirt/images/rhel-9.4-x86_64-dvd.iso"
  
  tasks:
    - name: Create AAP VM
      community.libvirt.virt:
        name: "{{ aap_vm_name }}"
        command: define
        xml: "{{ lookup('template', 'aap-vm.xml.j2') }}"
    
    - name: Start AAP VM
      community.libvirt.virt:
        name: "{{ aap_vm_name }}"
        state: running
```

### Phase 3: AAP Installation (Weeks 3-4)

Create `playbooks/setup-aap-containerized.yml`:

```yaml
---
- name: Install AAP 2.5 Containerized (Growth Topology)
  hosts: aap
  become: yes
  vars:
    aap_installer_url: "https://access.redhat.com/downloads/content/aap/2.5/installer"
    aap_admin_password: "{{ vault_aap_admin_password }}"
  
  tasks:
    - name: Subscribe RHEL system
      community.general.redhat_subscription:
        state: present
        username: "{{ rh_username }}"
        password: "{{ rh_password }}"
    
    - name: Download AAP installer
      ansible.builtin.get_url:
        url: "{{ aap_installer_url }}"
        dest: /tmp/aap-installer.tar.gz
    
    - name: Run containerized installer
      ansible.builtin.shell: |
        cd /tmp
        tar -xzf aap-installer.tar.gz
        cd ansible-automation-platform-containerized-setup-2.5
        ./setup.sh
      args:
        creates: /var/lib/awx
```

### Phase 4: Job Template Migration (Weeks 5-10)

**Automated migration script** (`scripts/migrate-dags-to-aap.py`):

```python
#!/usr/bin/env python3
"""
Migrate Airflow DAGs to AAP Job Templates
Parses existing DAG Python files and generates AAP YAML definitions
"""

import re
import yaml
from pathlib import Path

def parse_dag_file(dag_path):
    """Extract BashOperator tasks from DAG file"""
    with open(dag_path) as f:
        content = f.read()
    
    # Find all BashOperator task definitions
    tasks = re.findall(r'(\w+)\s*=\s*BashOperator\((.*?)\)', content, re.DOTALL)
    
    job_templates = []
    for task_name, task_config in tasks:
        # Extract ansible-playbook command
        playbook_match = re.search(r'ansible-playbook\s+([^\s]+)', task_config)
        if playbook_match:
            playbook = playbook_match.group(1)
            job_templates.append({
                'name': task_name.replace('_', ' ').title(),
                'playbook': playbook,
                'inventory': 'inventory',
            })
    
    return job_templates

# Convert all DAGs to AAP Job Template YAML
dags_dir = Path('airflow/dags')
output_dir = Path('aap/job-templates')
output_dir.mkdir(exist_ok=True)

for dag_file in dags_dir.glob('ocp_*.py'):
    templates = parse_dag_file(dag_file)
    output_file = output_dir / f"{dag_file.stem}.yml"
    
    with open(output_file, 'w') as f:
        yaml.dump({'job_templates': templates}, f, default_flow_style=False)
    
    print(f"✅ Converted {dag_file.name} → {output_file.name}")
```

**Manual workflow conversion** (example: `ocp_initial_deployment`):

```yaml
# aap/workflows/ocp-initial-deployment.yml
---
workflow_job_templates:
  - name: OCP Initial Deployment
    description: Complete OCP deployment workflow for disconnected environments
    organization: Default
    schema:
      - identifier: validate_environment
        unified_job_template:
          name: Validate Environment
          type: job_template
        success_nodes:
          - provision_registry_vm
      
      - identifier: provision_registry_vm
        unified_job_template:
          name: Provision Registry VM
          type: job_template
        success_nodes:
          - setup_certificates
      
      - identifier: setup_certificates
        unified_job_template:
          name: Setup Certificates
          type: job_template
        success_nodes:
          - setup_registry
      
      # ... (continue for all 8 tasks)
      
      - identifier: deployment_summary
        unified_job_template:
          name: Deployment Summary
          type: job_template
    
    survey_enabled: yes
    survey_spec:
      name: OCP Initial Deployment Survey
      description: Configure deployment parameters
      spec:
        - question_name: OCP Version
          variable: ocp_version
          type: text
          default: "4.21.0"
          required: yes
        
        - question_name: Registry Type
          variable: registry_type
          type: multiplechoice
          choices:
            - mirror-registry
            - harbor
            - jfrog
          default: mirror-registry
          required: yes
        
        - question_name: Clean Mirror
          variable: clean_mirror
          type: multiplechoice
          choices:
            - "true"
            - "false"
          default: "false"
          required: yes
```

### Phase 5: Pre-load AAP with Job Templates (Week 11)

Create `playbooks/aap-preload-job-templates.yml`:

```yaml
---
- name: Pre-load AAP with ocp4-disconnected-helper Job Templates
  hosts: localhost
  gather_facts: no
  vars:
    aap_host: "{{ lookup('env', 'AAP_HOST') | default('https://aap-controller.example.com') }}"
    aap_token: "{{ lookup('env', 'AAP_TOKEN') }}"
  
  collections:
    - ansible.controller
  
  tasks:
    - name: Add ocp4-disconnected-helper project to AAP
      ansible.controller.project:
        name: ocp4-disconnected-helper
        organization: Default
        scm_type: git
        scm_url: https://github.com/yourorg/ocp4-disconnected-helper.git
        scm_branch: main
        scm_update_on_launch: yes
        controller_host: "{{ aap_host }}"
        controller_oauthtoken: "{{ aap_token }}"
    
    - name: Create job templates from YAML definitions
      ansible.controller.job_template:
        name: "{{ item.name }}"
        job_type: run
        organization: Default
        project: ocp4-disconnected-helper
        playbook: "{{ item.playbook }}"
        inventory: "{{ item.inventory }}"
        controller_host: "{{ aap_host }}"
        controller_oauthtoken: "{{ aap_token }}"
      loop: "{{ lookup('file', 'aap/job-templates/ocp_initial_deployment.yml') | from_yaml | json_query('job_templates') }}"
    
    - name: Create workflow job templates
      ansible.controller.workflow_job_template:
        name: "{{ item.name }}"
        organization: Default
        schema: "{{ item.schema }}"
        survey_enabled: "{{ item.survey_enabled }}"
        survey_spec: "{{ item.survey_spec }}"
        controller_host: "{{ aap_host }}"
        controller_oauthtoken: "{{ aap_token }}"
      loop: "{{ lookup('file', 'aap/workflows/ocp-initial-deployment.yml') | from_yaml | json_query('workflow_job_templates') }}"
```

### Phase 6: Testing & Validation (Weeks 12-14)

1. **Parallel execution testing**: Run Airflow DAG and AAP Workflow side-by-side
2. **Performance benchmarking**: Compare execution times
3. **Error handling validation**: Test retry logic and failure scenarios
4. **Documentation update**: Migrate all Airflow references to AAP

### Phase 7: Deprecation & Cleanup (Week 15)

```bash
# Archive Airflow code
mkdir -p archive/airflow-legacy
mv airflow/ archive/airflow-legacy/

# Update README
sed -i 's/Airflow/Ansible Automation Platform (AAP)/g' README.md

# Create migration guide
cat > docs/MIGRATION-AIRFLOW-TO-AAP.md <<EOF
# Migration Guide: Airflow → AAP

For users on v4.20.0 with Airflow deployments:

1. Tag your current deployment: \`git checkout v4.20.0-airflow\`
2. Review AAP system requirements (RHEL 9.4+, 16GB RAM, 60GB disk)
3. Obtain AAP subscription from Red Hat
4. Follow AAP installation guide in \`docs/aap-setup.md\`
5. Import job templates: \`ansible-playbook playbooks/aap-preload-job-templates.yml\`
6. Test workflows in AAP UI before decommissioning Airflow
EOF
```

## Directory Structure Changes

### Before (v4.20.0-airflow)
```
ocp4-disconnected-helper/
├── airflow/
│   ├── dags/
│   │   ├── ocp_initial_deployment.py      ❌ DEPRECATED
│   │   ├── ocp_incremental_update.py      ❌ DEPRECATED
│   │   ├── ocp_registry_sync.py           ❌ DEPRECATED
│   │   ├── ocp_harbor_registry.py         ❌ DEPRECATED
│   │   ├── ocp_jfrog_agent_deployment.py  ❌ DEPRECATED
│   │   └── dag_helpers.py                 ❌ DEPRECATED
│   └── README.md
├── playbooks/
│   └── (existing playbooks - NO CHANGES)
└── docs/adrs/
    ├── 0012-airflow-dag-orchestration.md  ⚠️ SUPERSEDED
    └── 0014-airflow-replaces-kcli-pipelines.md  ⚠️ SUPERSEDED
```

### After (v4.21.0)
```
ocp4-disconnected-helper/
├── aap/                                    ✅ NEW
│   ├── job-templates/
│   │   ├── ocp_initial_deployment.yml     ✅ NEW (converted from DAG)
│   │   ├── ocp_incremental_update.yml     ✅ NEW
│   │   ├── ocp_registry_sync.yml          ✅ NEW
│   │   ├── ocp_harbor_registry.yml        ✅ NEW
│   │   └── ocp_jfrog_agent_deployment.yml ✅ NEW
│   ├── workflows/
│   │   └── ocp-initial-deployment.yml     ✅ NEW (workflow definition)
│   └── README.md
├── playbooks/
│   ├── provision-aap-vm.yml               ✅ NEW (KVM provisioning)
│   ├── setup-aap-containerized.yml        ✅ NEW (AAP installation)
│   ├── aap-preload-job-templates.yml      ✅ NEW (auto-import)
│   └── (existing playbooks - preserved)
├── archive/
│   └── airflow-legacy/                    📦 ARCHIVED (for reference)
│       └── dags/
└── docs/
    ├── aap-setup.md                       ✅ NEW
    ├── MIGRATION-AIRFLOW-TO-AAP.md        ✅ NEW
    └── adrs/
        ├── 0012-airflow-dag-orchestration.md      (marked SUPERSEDED)
        ├── 0014-airflow-replaces-kcli-pipelines.md (marked SUPERSEDED)
        └── 0021-deprecate-airflow-adopt-aap.md    ✅ THIS ADR
```

## Verification Criteria

✅ AAP VM can be provisioned on KVM using `provision-aap-vm.yml`  
✅ AAP 2.5 containerized installation completes successfully  
✅ All 5 legacy Airflow DAGs converted to AAP Job Templates  
✅ Workflow Job Template for `ocp_initial_deployment` executes successfully  
✅ AAP survey collects runtime parameters (ocp_version, registry_type, clean_mirror)  
✅ Performance: AAP workflow execution time within 10% of Airflow DAG  
✅ Error handling: Failed tasks trigger proper retry logic in AAP  
✅ Documentation: README, migration guide, and ADR updated  
✅ Backward compatibility: Tier 1 (shell + ansible-playbook) still works  
✅ Tag `v4.20.0-airflow` preserved for users needing legacy Airflow support  

## Timeline

- **Week 1**: Tag legacy branch, create deprecation notice
- **Weeks 2-3**: Implement `provision-aap-vm.yml` with `community.libvirt`
- **Weeks 3-4**: Implement `setup-aap-containerized.yml`
- **Weeks 5-10**: Convert all DAGs to AAP Job Templates (6 weeks)
- **Week 11**: Implement `aap-preload-job-templates.yml`
- **Weeks 12-14**: Testing and validation (3 weeks)
- **Week 15**: Archive Airflow code, update docs, release v4.21.0

**Total Estimated Timeline: 15 weeks (~3.5 months)**

## Cost Considerations

| Item | Airflow (Old) | AAP (New) |
|------|---------------|-----------|
| Software License | $0 (Apache 2.0) | **~$5,000-15,000/year** (AAP subscription) |
| Infrastructure | Self-managed containers | Self-managed containers |
| Support | Community forums | Red Hat Enterprise Support |
| Training | Online resources | Red Hat training courses |

**⚠️ Budget Impact**: AAP adoption requires annual subscription cost. Ensure budget approval before proceeding.

## Related ADRs

- **Supersedes:**
  - ADR 0012: Airflow DAG Orchestration Strategy
  - ADR 0014: Airflow Replaces kcli-pipelines for Orchestration

- **Superseded By:** (none yet)

- **Related:**
  - ADR 0001: Two-Tier Architecture (updated by ADR 0022)
  - ADR 0011: qubinode_navigator Integration (superseded by ADR 0022)
  - ADR 0022: Deprecate qubinode_navigator Dependency
  - ADR 0023: Pure Ansible with community.libvirt Migration

## References

1. Red Hat, "Chapter 3. Container topologies", AAP 2.5 Documentation - https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/tested_deployment_models/container-topologies
2. PRD v4.21.0 (2026-05-28), Section 4 - Execution Tiers: Shell/Ansible vs. AAP
3. PRD v4.21.0, Section 4.2 - Ansible Automation Platform (AAP) on KVM
