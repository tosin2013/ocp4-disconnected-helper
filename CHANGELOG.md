# Changelog

All notable changes to ocp4-disconnected-helper will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added

#### 🚀 OpenShift Cluster Deployment - Agent-Based Installer (ADR-0035)

- **Complete Agent-Based Installer Integration**:
  - Deploys SNO, Compact (3-node), and HA (6+ node) topologies
  - Bootable ISO generation with embedded cluster configuration
  - Multi-registry support: Quay (primary), Harbor, JFrog
  - DNS integration: dnsmasq (automated), Route53 (cloud), manual
  - Installation monitoring: Bootstrap → Control Plane → Workers → Operators
  - Credential export with access instructions

- **New Ansible Role**: `openshift_cluster_deploy`
  - Atomic task structure following ADR-0024 pattern
  - 6-phase deployment workflow:
    - Phase 0: Prerequisites validation
    - Phase 1-2: Installation preparation and manifest generation
    - Phase 3: Bootable ISO creation (agent.x86_64.iso)
    - Phase 4: DNS configuration
    - Phase 5: VM provisioning (KVM) or manual boot instructions (bare metal)
    - Phase 6: Installation monitoring to completion

- **Main Orchestration Playbook**: `playbooks/deploy-openshift-cluster.yml`
  - Tag-based execution support (phase0-phase6)
  - Pre-task banner with deployment details
  - Post-task summary with cluster access instructions
  - Full automation for KVM environments
  - Guided workflow for bare metal deployments

- **AAP Workflow 3**: OpenShift Cluster Deployment
  - 5 job templates (one per deployment phase)
  - Sequential workflow with on_success links
  - 9 survey parameters (cluster_name, topology, registry, etc.)
  - 35-90 minute total deployment time (topology-dependent)
  - 2-hour timeout for full installation monitoring

- **Cluster Configuration Examples** (`extra_vars/cluster-configs/`):
  - SNO: sno-quay.yml, sno-harbor.yml, sno-jfrog.yml
  - Compact: compact-3node-quay.yml, compact-3node-harbor.yml, compact-3node-jfrog.yml
  - HA: ha-cluster-quay.yml, ha-cluster-harbor.yml
  - All with comprehensive README and validation

- **Comprehensive Documentation**:
  - How-to: `docs/how-to/deploy-openshift-cluster-agent-based.md`
    - Complete guide for KVM and bare metal deployments
    - Clear distinction between automated (KVM) and manual (bare metal) workflows
    - Environment-specific requirements and limitations
    - Troubleshooting section
  - Tutorial: `docs/tutorials/your-first-openshift-cluster.md`
    - Step-by-step SNO deployment on KVM
    - First application deployment
    - Web Console access and exploration
  - Reference: `docs/reference/cluster-topologies.md`
    - SNO, Compact, HA comparison and decision matrix
    - Resource requirements and availability characteristics
    - Use case recommendations
  - Reference: `docs/reference/registry-integration.md`
    - Quay, Harbor, JFrog integration details
    - ImageDigestMirrorSet configuration
    - Certificate management
    - Switching between registries

- **Test Playbooks**:
  - `playbooks/test-iso-generation.yml` - ISO generation simulation
  - `playbooks/test-installation-monitoring.yml` - Monitoring workflow validation
  - `playbooks/test-main-playbook.yml` - Main playbook structure verification

---

## [1.2.0] - 2026-06-11

### Added

#### 🎯 Operator Catalog Validation Framework (ADR-0034)

- **Pre-flight Validation Playbook**: `playbooks/validate-operator-selection.yml`
  - Validates operator names/channels against Red Hat catalogs before expensive mirroring
  - Fuzzy matching with similarity threshold 0.6 (catches typos like "local-storage" → "local-storage-operator")
  - Catalog caching at `~/.cache/oc-mirror/catalogs/` (24h TTL, ~73 KB vs 50-100 GB full mirror)
  - Actionable error messages with suggestions
  - Integrated as AAP workflow preflight node (Workflow ID 36, Job Template ID 34)

- **Operator Discovery Tool**: `scripts/discover-operators.sh`
  - Search operator catalogs by keyword (e.g., `--search storage`)
  - Display available channels and versions
  - Generate valid YAML snippets for copy-paste into extra_vars

- **8 Curated Operator Preset Bundles** (`extra_vars/operators/`):
  - `storage-operators.yml` (5 operators: ODF, LVMS, Local Storage, NFS, Rook Ceph)
  - `rhacm-operators.yml` (4 operators: RHACM 2.16, MCE 2.11, Submariner 0.24, GitOps)
  - `openshift-ai-operators.yml` (5 operators: RHODS, Authorino, Service Mesh, Serverless, GPU)
  - `virtualization-operators.yml` (4 operators: KubeVirt, ODF, NMState, MetalLB)
  - `service-mesh-operators.yml` (3 operators: Service Mesh, Kiali, Tempo)
  - `observability-operators.yml` (5 operators: Logging, Loki, Tempo, Observability, GitOps)
  - `security-operators.yml` (4 operators: Compliance, FIM, Quay, Quay Bridge)
  - `networking-operators.yml` (4 operators: MetalLB, NMState, Submariner, Service Mesh)
  - **All presets validated**: 100% pass rate (32 operators tested)

- **Comprehensive Preset Documentation**: `extra_vars/operators/README.md`
  - Use cases, requirements, size estimates for each preset
  - Quick start guide
  - Combining presets guide
  - Custom preset creation guide
  - Troubleshooting section

#### 🔧 AAP Workflow Orchestration (ADR-0032, ADR-0033)

- **AAP 3-Node Workflow with Validation Preflight**: `playbooks/aap-configuration/configure-oc-mirror-workflow.yml`
  - Node 1: Validate Operator Selection (pre-flight, fails fast <5s on invalid config)
  - Node 2: Download OpenShift Images (Phase 1: mirrorToDisk)
  - Node 3: Mirror Images to Registry (Phase 2: diskToMirror)
  - **Deployed as**: Workflow ID 36 "Disconnected OpenShift Image Mirroring"
  - **Production-Validated**: Workflow Job #118 successful (all 3 nodes passed)

- **AAP Workflow Validation Framework** (ADR-0033):
  - Shell health check scripts: `scripts/validate-aap-health.sh`, `scripts/validate-aap-workflow-templates.sh`
  - E2E test playbooks: `playbooks/test-registry-vm-workflow.yml`, `playbooks/test-oc-mirror-workflow.yml`
  - GitHub Actions workflow: `.github/workflows/validate-aap-workflows.yml`
  - Testing documentation: `docs/TESTING.md`
  - Validates ADR-0031 (Control Plane EE registry auth), ADR-0028 (dual password architecture), ADR-0032 (workflow orchestration)

### Changed

- **Operator Validation Workflow Integration**:
  - oc-mirror workflows now start with operator validation node (prevent wasted bandwidth)
  - Validation failures stop workflow before Phase 1 download (save 10-30 min on invalid configs)

- **ADR Status Updates** (Production Validation):
  - ADR-0034: Proposed → **Validated in Production (v1.2)**
  - ADR-0033: Proposed → **Validated in Production (v1.2)**
  - ADR-0032: Proposed → **Validated in Production (v1.2)**

### Fixed

- **Undefined Variable in Download Playbook** (Commit `3e155c0`):
  - Fixed `'oc_path' is undefined` error in `playbooks/tasks/get-operator-catalog-channels.yml`
  - Changed from undefined `{{ oc_path.stdout }}` to hardcoded `/usr/local/bin/oc-mirror --v2`

- **Host Targeting Mismatch in Validation Job Template** (Commit `1dcb768`):
  - Removed `limit: "kvm-host"` from validation job template (playbook runs on localhost)
  - Fixed "skipping: no hosts matched" error in AAP Workflow Job #115

### Performance

- **Operator Validation Speed**: <5 seconds (vs 10-30 minutes with oc-mirror)
- **Catalog Cache Efficiency**: ~73 KB per catalog (vs 50-100 GB full mirror) = **99.999% size reduction**
- **Workflow Job #118 Execution Times**:
  - Validation Node: 3.6 seconds
  - Download Node: 102 seconds
  - Push Node: 343 seconds
  - **Total**: 448.6 seconds (~7.5 minutes)

### Documentation

- **Operator Presets Quick Start**: `extra_vars/operators/README.md`
  - Comparison table with size estimates
  - Detailed descriptions of each preset
  - Best practices and troubleshooting

- **AAP Workflow Deployment Guide**: `docs/AAP_WORKFLOW_DEPLOYMENT_GUIDE.md`
  - Step-by-step workflow configuration
  - Troubleshooting workflow execution issues

---

## [4.21.0] - TBD (Target: Q4 2026)

### ⚠️ BREAKING CHANGES

This release introduces **revolutionary architectural changes** that affect all users. Please review carefully.

#### 🚨 Removed Dependencies

Three major dependencies have been removed:

1. **Apache Airflow (Orchestration)**  
   - **What Changed**: All DAG-based workflows removed  
   - **Migration Required**: ✅ **YES** - Follow [MIGRATION-AIRFLOW-TO-AAP.md](docs/MIGRATION-AIRFLOW-TO-AAP.md)  
   - **Replacement**: Red Hat Ansible Automation Platform (AAP) 2.5  
   - **Timeline**: 15-week migration path

2. **qubinode_navigator (Infrastructure Provider)**  
   - **What Changed**: No longer required for Tier 1 setup  
   - **Migration Required**: ✅ **YES** - Follow [MIGRATION-QUBINODE-TO-STANDALONE.md](docs/MIGRATION-QUBINODE-TO-STANDALONE.md)  
   - **Replacement**: `playbooks/setup-dependencies.yml` (self-contained setup)  
   - **Setup Time**: Reduced from 2-3 hours → 30 minutes

3. **kcli (VM Provisioning Tool)**  
   - **What Changed**: All VM provisioning migrated to pure Ansible  
   - **Migration Required**: ✅ **YES** - Update playbooks per [libvirt-vm-provisioning.md](docs/libvirt-vm-provisioning.md)  
   - **Replacement**: `community.libvirt` Ansible collection  
   - **Benefit**: Infrastructure-as-Code, better idempotency

#### ❌ Removed Features

- **MCP Integration** (previously via qubinode_navigator)  
  - No replacement in v4.21.0  
  - Consider this an acceptable trade-off for enterprise support  
  - Future: May explore AAP + MCP integration via custom execution environments

- **Airflow Web UI** (workflow visualization)  
  - Replacement: AAP Web UI at https://aap-controller

- **kcli CLI Commands** (VM management)  
  - Replacement: `virsh` CLI or `ansible-playbook` with libvirt tasks

#### 📚 Migration Paths by User Type

| Current Setup | Action Required | Est. Migration Time |
|---------------|----------------|---------------------|
| Using Airflow DAGs | [Migrate to AAP](docs/MIGRATION-AIRFLOW-TO-AAP.md) | 1-2 days |
| Using qubinode_navigator | [Migrate to Standalone](docs/MIGRATION-QUBINODE-TO-STANDALONE.md) | 2-4 hours |
| Using kcli for VMs | Update playbooks (auto-detected) | 1 hour |
| Fresh install (no migration) | Follow [PREREQUISITES.md](docs/PREREQUISITES.md) | 30 minutes |

#### 🏷️ Legacy Support Tag

Users wishing to **remain on the legacy architecture** should use:

```bash
git checkout v4.20.0-airflow
```

**⚠️ Note**: No backports will be provided to v4.20.0-airflow. This tag is **frozen** for reference only.

---

### Added

#### 🎯 New Orchestration Platform

- **Ansible Automation Platform (AAP) 2.5** support
  - Job Templates for all workflows (8 converted from Airflow DAGs)
  - Workflow Job Templates for complex pipelines (5 workflows)
  - AAP deployable on KVM (4 vCPU, 16GB RAM) for development
  - Web UI for workflow management at https://aap-controller
  - Enterprise support from Red Hat (included in subscription)
  - RBAC, audit logging, and compliance reporting
  - Survey-based runtime parameter collection
  - Email/Slack notifications on workflow failure
  - Retry logic and error handling

#### 📝 New Playbooks

**Infrastructure Setup**:
- `playbooks/setup-dependencies.yml` - Install base system dependencies (replaces qubinode setup)
  - Installs: ansible-core, libvirt, qemu-kvm, python3-libvirt, genisoimage
  - Enables libvirtd service
  - Installs Ansible collections: community.libvirt, ansible.posix
  - Verifies libvirt connection
  - Creates required directories

**AAP Deployment**:
- `playbooks/provision-aap-vm.yml` - Provision AAP VM on KVM using community.libvirt
  - 4 vCPU, 16GB RAM, 60GB disk
  - RHEL 9.4 base image
  - Cloud-init for automated setup
  
- `playbooks/setup-aap-containerized.yml` - Install AAP 2.5 containerized (Growth Topology)
  - Downloads AAP installer from Red Hat portal
  - Subscribes RHEL system
  - Runs containerized installer
  - Verifies AAP UI accessibility

- `playbooks/aap-preload-job-templates.yml` - Auto-import job templates to AAP
  - Imports all 8 job templates from YAML
  - Imports all 5 workflow templates
  - Creates AAP project from git repository
  - Configures surveys for runtime parameters

**VM Provisioning** (community.libvirt):
- `playbooks/provision-haproxy-vm.yml` - HAProxy load balancer VM (NEW)
- `playbooks/provision-ocp-nodes-vms.yml` - OCP master/worker nodes (NEW, loop-based)
- **UPDATED**: `playbooks/provision-registry-vm.yml` - Now uses community.libvirt (was kcli)

#### 🗂️ New Templates

**Libvirt Domain Definitions** (`templates/libvirt/*.xml.j2`):
- `registry-vm.xml.j2` - Mirror registry / Harbor / JFrog VM
- `aap-vm.xml.j2` - AAP controller VM (4 vCPU, 16GB RAM)
- `haproxy-vm.xml.j2` - HAProxy load balancer VM
- `ocp-node-vm.xml.j2` - OCP master/worker node template

**Cloud-Init Configurations** (`templates/cloud-init/*.yml.j2`):
- `<vm-type>-user-data.yml.j2` - User account, SSH keys, packages
- `<vm-type>-meta-data.yml.j2` - Instance ID, hostname
- `<vm-type>-network-config.yml.j2` - Static IP configuration

*(Where `<vm-type>` = registry, aap, haproxy, ocp-node)*

#### 🔧 New Reusable Tasks

- `tasks/provision-vm-libvirt.yml` - Reusable libvirt VM provisioning task
  - Idempotency check (skip if VM exists)
  - VM disk creation from base image
  - Cloud-init ISO generation
  - VM definition and startup
  - Parameterized for all VM types

#### 📖 New Documentation

**Setup Guides**:
- `docs/PREREQUISITES.md` - OS installation and system requirements
  - Supported OS: RHEL 9.4+, CentOS Stream 9.4+
  - Hardware requirements (CPU, RAM, disk)
  - Network requirements
  - Step-by-step setup instructions

- `docs/aap-setup.md` - AAP installation and configuration guide
  - System requirements
  - Containerized vs. RPM installation
  - Growth topology deployment
  - RBAC configuration
  - Backup and recovery procedures

- `docs/libvirt-vm-provisioning.md` - Pure Ansible VM provisioning guide
  - community.libvirt collection usage
  - Libvirt XML template structure
  - Cloud-init configuration patterns
  - Idempotency best practices
  - Troubleshooting common issues

**Migration Guides**:
- `docs/MIGRATION-AIRFLOW-TO-AAP.md` - Airflow users migration guide
  - Pre-migration checklist
  - Step-by-step migration instructions
  - Airflow → AAP concept mapping (DAG → Workflow, Task → Job Template)
  - Performance comparison notes
  - Troubleshooting section

- `docs/MIGRATION-QUBINODE-TO-STANDALONE.md` - qubinode users migration guide
  - Backup current configuration
  - Fresh RHEL 9.4 host provisioning
  - setup-dependencies.yml execution
  - Inventory and variable migration
  - Rollback procedures

**Release Documentation**:
- `RELEASE_PLAN.md` - v4.21.0 migration roadmap
  - Executive summary
  - Migration phases (Gantt chart)
  - Risk matrix
  - Cost considerations
  - Go/No-Go decision points

- `CHANGELOG.md` - This file (Keep a Changelog format)

- `TODO.md` - Development task tracker with dependencies

#### 🏛️ New ADRs

- **ADR 0021**: Deprecate Airflow and Adopt AAP ([docs/adrs/0021-deprecate-airflow-adopt-aap.md](docs/adrs/0021-deprecate-airflow-adopt-aap.md))
  - Supersedes: ADR 0012 (Airflow DAG Orchestration), ADR 0014 (Airflow Replaces kcli-pipelines)
  - Decision: Replace Apache Airflow with Red Hat AAP 2.5
  - Timeline: 15 weeks
  - Cost impact: $5k-15k/year (AAP subscription)

- **ADR 0022**: Deprecate qubinode_navigator Dependency ([docs/adrs/0022-deprecate-qubinode-navigator.md](docs/adrs/0022-deprecate-qubinode-navigator.md))
  - Supersedes: ADR 0001 (Two-Tier Architecture), ADR 0011 (qubinode_navigator Integration)
  - Decision: Make repository self-contained
  - Timeline: 6 weeks
  - Benefit: Setup time reduced from 2-3 hours → 30 minutes

- **ADR 0023**: Pure Ansible with community.libvirt Migration ([docs/adrs/0023-pure-ansible-community-libvirt.md](docs/adrs/0023-pure-ansible-community-libvirt.md))
  - Supersedes: ADR 0018 (Registry VM Deployment)
  - Decision: Replace kcli with pure Ansible + community.libvirt
  - Timeline: 4 weeks
  - Benefit: Infrastructure-as-Code, better idempotency

#### 🛠️ New Scripts

- `scripts/migrate-dags-to-aap.py` - Automated DAG to Job Template converter
  - Parses Airflow DAG Python files
  - Extracts BashOperator tasks and dependencies
  - Generates AAP YAML definitions (job templates + workflows)
  - Handles 8 production DAGs automatically

#### 📁 New Directory Structure

```
ocp4-disconnected-helper/
├── aap/                                    ✅ NEW
│   ├── job-templates/
│   │   ├── ocp_initial_deployment.yml
│   │   ├── ocp_incremental_update.yml
│   │   ├── ocp_registry_sync.yml
│   │   ├── ocp_harbor_registry.yml
│   │   ├── ocp_jfrog_agent_deployment.yml
│   │   ├── ocp_disconnected_workflow.yml
│   │   ├── ocp_pre_deployment_validation.yml
│   │   └── README.md
│   └── workflows/
│       ├── ocp-initial-deployment.yml
│       ├── ocp-incremental-update.yml
│       ├── ocp-jfrog-agent-deployment.yml
│       ├── ocp-disconnected-workflow.yml
│       ├── ocp-pre-deployment-validation.yml
│       └── README.md
│
├── templates/                              ✅ NEW
│   ├── libvirt/
│   │   ├── registry-vm.xml.j2
│   │   ├── aap-vm.xml.j2
│   │   ├── haproxy-vm.xml.j2
│   │   └── ocp-node-vm.xml.j2
│   └── cloud-init/
│       ├── registry-user-data.yml.j2
│       ├── registry-meta-data.yml.j2
│       ├── registry-network-config.yml.j2
│       └── ... (similar for aap, haproxy, ocp-node)
│
├── tasks/
│   └── provision-vm-libvirt.yml            ✅ NEW
│
├── archive/                                ✅ NEW
│   ├── airflow-legacy/                    📦 ARCHIVED
│   │   ├── DEPRECATED.md
│   │   └── dags/
│   └── kcli-legacy/                       📦 ARCHIVED
│       └── provision-registry-vm.yml.bak
│
└── docs/
    ├── PREREQUISITES.md                    ✅ NEW
    ├── MIGRATION-AIRFLOW-TO-AAP.md         ✅ NEW
    ├── MIGRATION-QUBINODE-TO-STANDALONE.md ✅ NEW
    ├── aap-setup.md                        ✅ NEW
    ├── libvirt-vm-provisioning.md          ✅ NEW
    └── adrs/
        ├── 0021-deprecate-airflow-adopt-aap.md  ✅ NEW
        ├── 0022-deprecate-qubinode-navigator.md ✅ NEW
        └── 0023-pure-ansible-community-libvirt.md ✅ NEW
```

---

### Changed

#### 🔄 Architecture

- **Two-Tier Architecture → Self-Contained Standalone**
  - **Before (v4.20.0)**: qubinode_navigator (Tier 1) + ocp4-disconnected-helper (Tier 2)
  - **After (v4.21.0)**: ocp4-disconnected-helper (standalone) with optional AAP (Tier 2)
  - **Impact**: Single repository, simpler setup, no external dependencies

#### 🔄 Execution Tiers

- **Tier 1** (Required): Shell + `ansible-playbook` CLI
  - **Before**: Provided by qubinode_navigator
  - **After**: Native to ocp4-disconnected-helper via `setup-dependencies.yml`

- **Tier 2** (Optional): Advanced orchestration
  - **Before**: Apache Airflow (community)
  - **After**: Red Hat AAP 2.5 (enterprise)

#### 🔄 VM Provisioning Approach

- **All VM provisioning** now uses `community.libvirt` Ansible collection
  - **Before**: kcli CLI commands (black box)
  - **After**: Declarative libvirt XML templates + cloud-init
  - **Benefit**: Infrastructure-as-Code, version-controlled, idempotent

#### 🔄 Documentation

- **README.md**
  - Removed all qubinode_navigator references
  - Removed Airflow setup instructions
  - Updated "Quick Start" to point to PREREQUISITES.md
  - Added "Execution Tiers" section (Tier 1 shell/Ansible, Tier 2 AAP optional)
  - Added note about v4.20.0-airflow tag for legacy users

---

### Deprecated

The following ADRs are marked **SUPERSEDED** as of v4.21.0:

- **ADR 0001**: Two-Tier Architecture  
  → Superseded by ADR 0022 (Standalone architecture)

- **ADR 0011**: qubinode_navigator Integration  
  → Superseded by ADR 0022 (No external dependency)

- **ADR 0012**: Airflow DAG Orchestration Strategy  
  → Superseded by ADR 0021 (AAP Job Templates)

- **ADR 0014**: Airflow Replaces kcli-pipelines for Orchestration  
  → Superseded by ADR 0021 (AAP Workflow Job Templates)

- **ADR 0018**: Registry VM Deployment  
  → Superseded by ADR 0023 (community.libvirt approach)

**⚠️ Note**: Legacy ADRs remain in repository for historical reference but are no longer active.

---

### Removed

#### 🗑️ Archived Code

The following code has been moved to `archive/` for reference:

- **`airflow/` directory** (moved to `archive/airflow-legacy/`)
  - `airflow/dags/ocp_initial_deployment.py` (~596 lines)
  - `airflow/dags/ocp_incremental_update.py`
  - `airflow/dags/ocp_registry_sync.py`
  - `airflow/dags/ocp_harbor_registry.py`
  - `airflow/dags/ocp_jfrog_agent_deployment.py`
  - `airflow/dags/ocp_disconnected_workflow.py`
  - `airflow/dags/ocp_pre_deployment_validation.py`
  - `airflow/dags/dag_helpers.py`
  - Total: ~2000+ lines of Python code

#### 🗑️ Dependencies Removed

From all documentation and setup instructions:
- qubinode_navigator setup requirements
- kcli installation instructions
- Airflow container deployment

---

### Fixed

#### ✅ Development → Production Parity

- **Before**: Development used qubinode + kcli, production used different tools
- **After**: Identical playbooks for development and production, only inventory differs
- **Benefit**: "Works on my machine" problems eliminated

#### ✅ Idempotency

- **Before**: kcli commands not always idempotent (re-run could create duplicate VMs)
- **After**: All VM provisioning playbooks check for existing VMs and skip creation
- **Benefit**: Safe to re-run playbooks without side effects

#### ✅ Setup Complexity

- **Before**: Install qubinode (2-3 hours) → clone ocp4-disconnected-helper
- **After**: Clone ocp4-disconnected-helper → run `setup-dependencies.yml` (30 minutes)
- **Benefit**: Faster onboarding, fewer failure points

#### ✅ Dependency Transparency

- **Before**: kcli black box (unclear what it does under the hood)
- **After**: Libvirt XML templates (declarative, inspectable)
- **Benefit**: Full control over VM configuration

---

### Security

#### 🔒 Enhanced Security

- **SSL Certificate Management**
  - All certificates now managed via Ansible templates (no kcli black box)
  - Certificate files version-controlled where appropriate
  - Clear separation of CA cert, server cert, and private key

- **Cloud-Init User Data**
  - User data files properly secured (file permissions 0600)
  - Sensitive data (SSH keys, passwords) encrypted with Ansible Vault where applicable
  - Cloud-init ISOs cleaned up after VM boot

- **AAP RBAC**
  - Role-based access control for workflow execution
  - Audit logs for all job template launches
  - Credential management (no plain-text passwords in playbooks)

---

## [4.20.0-airflow] - 2026-06-02 (LEGACY TAG)

This tag preserves the last working Airflow-based architecture before v4.21.0 migration.

### Legacy Features (Preserved for Reference)

- Apache Airflow orchestration with 8 production DAGs:
  - `ocp_initial_deployment.py` (596 lines, 8-task workflow)
  - `ocp_incremental_update.py`
  - `ocp_registry_sync.py`
  - `ocp_harbor_registry.py`
  - `ocp_jfrog_agent_deployment.py`
  - `ocp_disconnected_workflow.py`
  - `ocp_pre_deployment_validation.py`
  - `dag_helpers.py`

- qubinode_navigator integration for Tier 1 infrastructure
  - Provided base system setup
  - MCP integration (9 tools)

- kcli-based VM provisioning
  - Fast VM creation (kcli CLI)
  - Opinionated defaults

**⚠️ Important Notes**:
- This tag is **frozen** - no backports will be provided
- Users needing Airflow support should remain on this tag
- Migration to v4.21.0 requires following migration guides
- Use `git checkout v4.20.0-airflow` to access legacy code

---

## Version History Summary

| Version | Release Date | Type | Summary |
|---------|--------------|------|---------|
| **4.21.0** | TBD (Q4 2026) | 🔴 **MAJOR (Breaking)** | Revolutionary architecture change: AAP adoption, standalone architecture, pure Ansible |
| **4.20.0-airflow** | 2026-06-02 | 🏷️ **LEGACY TAG** | Frozen state preserving Airflow + qubinode + kcli architecture |

---

## Migration Checklist for v4.21.0

Use this checklist to validate your migration:

### For Airflow Users
- [ ] Read [MIGRATION-AIRFLOW-TO-AAP.md](docs/MIGRATION-AIRFLOW-TO-AAP.md)
- [ ] Backup current Airflow workflows and logs
- [ ] Obtain AAP subscription from Red Hat
- [ ] Provision AAP VM (`ansible-playbook playbooks/provision-aap-vm.yml`)
- [ ] Install AAP 2.5 (`ansible-playbook playbooks/setup-aap-containerized.yml`)
- [ ] Import job templates (`ansible-playbook playbooks/aap-preload-job-templates.yml`)
- [ ] Test workflows in AAP UI
- [ ] Decommission Airflow services

### For qubinode Users
- [ ] Read [MIGRATION-QUBINODE-TO-STANDALONE.md](docs/MIGRATION-QUBINODE-TO-STANDALONE.md)
- [ ] Backup current qubinode configuration
- [ ] Provision fresh RHEL 9.4 host (or reuse existing)
- [ ] Clone v4.21.0 repository
- [ ] Run `ansible-playbook playbooks/setup-dependencies.yml`
- [ ] Migrate inventory and variables
- [ ] Test VM provisioning (`ansible-playbook playbooks/provision-registry-vm.yml`)

### For kcli Users
- [ ] Read [docs/libvirt-vm-provisioning.md](docs/libvirt-vm-provisioning.md)
- [ ] Update playbooks to use `community.libvirt` (pattern auto-detected)
- [ ] Test idempotency (run playbook twice, verify second run skips)
- [ ] Remove kcli package (optional)

### For Fresh Installs
- [ ] Read [PREREQUISITES.md](docs/PREREQUISITES.md)
- [ ] Install supported OS (RHEL 9.4+ or CentOS Stream 9.4+)
- [ ] Clone v4.21.0 repository
- [ ] Run `ansible-playbook playbooks/setup-dependencies.yml`
- [ ] Verify setup (`ansible-playbook playbooks/validate-environment.yml`)

---

## Links

- **Repository**: https://github.com/tosin2013/ocp4-disconnected-helper
- **Issues**: https://github.com/tosin2013/ocp4-disconnected-helper/issues
- **Discussions**: https://github.com/tosin2013/ocp4-disconnected-helper/discussions
- **Red Hat AAP Documentation**: https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5
- **community.libvirt Collection**: https://docs.ansible.com/ansible/latest/collections/community/libvirt/

---

[Unreleased]: https://github.com/tosin2013/ocp4-disconnected-helper/compare/v4.20.0-airflow...HEAD
[4.21.0]: https://github.com/tosin2013/ocp4-disconnected-helper/compare/v4.20.0-airflow...v4.21.0
[4.20.0-airflow]: https://github.com/tosin2013/ocp4-disconnected-helper/releases/tag/v4.20.0-airflow

---

**Document Version**: 1.0  
**Last Updated**: 2026-06-02  
**Format**: [Keep a Changelog v1.1.0](https://keepachangelog.com/en/1.1.0/)  
**Versioning**: [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html)
