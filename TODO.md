# ocp4-disconnected-helper v4.21.0 - Development Tasks

**Status**: 🟢 **APPROVED - READY TO START**  
**Target Release**: v4.21.0 (Q4 2026)  
**Timeline**: 15-20 weeks  
**AAP Subscription**: ✅ **APPROVED** (2026-06-02)  
**Last Updated**: 2026-06-02

> **📖 Documentation**: See [RELEASE_PLAN.md](RELEASE_PLAN.md) for executive overview and [CHANGELOG.md](CHANGELOG.md) for user-facing changes.

---

## Quick Status

| Phase | Status | Progress | Timeline |
|-------|--------|----------|----------|
| Phase 0: Preservation | 🟢 READY | 1/3 tasks (33%) | Week 1 |
| Phase 1: Libvirt Migration | 🔴 NOT STARTED | 0/7 tasks | Weeks 1-4 |
| Phase 2: Qubinode Removal | 🔴 NOT STARTED | 0/5 tasks | Weeks 3-8 |
| Phase 3: AAP Adoption | 🔴 NOT STARTED | 0/10 tasks | Weeks 2-15 ⚠️ CRITICAL PATH |
| Phase 4: Documentation | 🔴 NOT STARTED | 0/6 tasks | Weeks 16-17 |

**Total**: 4/31 tasks complete (13%) - ✅ **AAP APPROVED, READY TO BEGIN**

**Critical Path**: Phase 3 (AAP Adoption) - 15 weeks

---

## Legend

- ✅ **DONE** - Task completed and verified
- 🚧 **IN PROGRESS** - Currently being worked on
- ⏳ **BLOCKED** - Waiting on dependency or external factor
- 🔴 **NOT STARTED** - Not yet begun
- ⚠️ **HIGH RISK** - Potential for significant issues
- 🔒 **DEPENDENCY** - Depends on another task completing first
- 🎯 **GO/NO-GO** - Critical decision point

---

## Phase 0: Preservation (Week 1)

### ✅ Task 0.1: Tag Legacy Architecture

**Status**: 🔴 NOT STARTED  
**Priority**: P0 (BLOCKER)  
**Owner**: Platform Team  
**Effort**: 15 minutes  
**Dependencies**: None

**Description**:  
Create git tag `v4.20.0-airflow` to preserve current working state before any migration work begins. This serves as the rollback point and legacy support tag.

**Commands**:
```bash
git tag v4.20.0-airflow -m "Legacy Airflow architecture before v4.21.0 migration"
git push origin v4.20.0-airflow
```

**Verification**:
- [ ] Tag visible in `git tag -l`
- [ ] Tag pushed to origin (`git ls-remote --tags origin`)
- [ ] Tag documented in CHANGELOG.md

**Rollback**: Delete tag before any code changes: `git tag -d v4.20.0-airflow && git push origin :refs/tags/v4.20.0-airflow`

---

### ✅ Task 0.2: Create Archive Directory Structure

**Status**: 🔴 NOT STARTED  
**Priority**: P0 (BLOCKER)  
**Owner**: Platform Team  
**Effort**: 10 minutes  
**Dependencies**: 🔒 Task 0.1 (tag created first)

**Description**:  
Create `archive/` directory to preserve legacy code for reference during migration. Airflow and kcli code will be moved here in later phases.

**Commands**:
```bash
mkdir -p archive/{airflow-legacy,kcli-legacy}
cat > archive/README.md <<EOF
# Legacy Code Archive

Preserved code from v4.20.0 for reference during v4.21.0 migration.

- **airflow-legacy/**: Apache Airflow DAG code (Phase 3 cleanup)
- **kcli-legacy/**: kcli-based playbooks (Phase 1 backup)

**⚠️ Do not modify**: This code is frozen for reference only.

**Tag**: v4.20.0-airflow
EOF
git add archive/
git commit -m "chore: Create archive directory for legacy code"
```

**Verification**:
- [ ] `archive/airflow-legacy/` directory exists (empty)
- [ ] `archive/kcli-legacy/` directory exists (empty)
- [ ] `archive/README.md` describes purpose

**Rollback**: `git rm -r archive/ && git commit --amend`

---

### 🎯 Task 0.3: AAP Subscription Approval (BUSINESS CRITICAL)

**Status**: ✅ **DONE** (2026-06-02)  
**Priority**: P0 (GO/NO-GO DECISION #1)  
**Owner**: Product Owner (Tosin)  
**Effort**: 1-2 weeks (procurement process)  
**Dependencies**: None

**Description**:  
Obtain budget approval and procure Red Hat AAP subscription ($5k-15k/year). **If denied, ABORT migration** and remain on v4.20.0-airflow.

**Steps**:
1. ✅ Present [RELEASE_PLAN.md](RELEASE_PLAN.md) to stakeholders
2. ✅ Get budget approval for $5k-15k/year recurring cost
3. 🚧 Initiate Red Hat procurement process (IN PROGRESS)
4. ⏳ Obtain subscription entitlement (PENDING)

**Verification**:
- [x] Budget approved (signed document) ✅
- [ ] Subscription purchased (Red Hat order number) - IN PROCUREMENT
- [ ] Entitlement accessible in Red Hat Customer Portal
- [ ] AAP installer downloadable from portal

**🎯 GO/NO-GO Decision**:
- ✅ **GO**: Proceed with full migration (Phase 1-4) - **APPROVED**
- ~~NO-GO~~: ~~ABORT migration~~ - N/A

**Critical**: ✅ AAP approval received - **GREEN LIGHT for v4.21.0 migration**

---

## Phase 1: Foundation - Pure Ansible Migration (Weeks 1-4)

### ✅ Task 1.1: Create Libvirt VM Templates

**Status**: 🔴 NOT STARTED  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 1 week  
**Dependencies**: None  
**ADR**: 0023

**Description**:  
Create Jinja2 templates for libvirt domain XML definitions for all VM types (registry, AAP, HAProxy, OCP nodes).

**Files to Create**:
- `templates/libvirt/registry-vm.xml.j2` (mirror-registry/harbor/jfrog)
- `templates/libvirt/aap-vm.xml.j2` (4 vCPU, 16GB RAM)
- `templates/libvirt/haproxy-vm.xml.j2` (load balancer)
- `templates/libvirt/ocp-node-vm.xml.j2` (master/worker nodes)

**Reference**: ADR 0023 contains example XML structure.

**Verification**:
- [ ] All 4 template files created
- [ ] XML syntax valid (`xmllint --noout templates/libvirt/*.xml.j2`)
- [ ] Variables documented in template comments (vm_name, vm_memory, vm_cpus, vm_disk, etc.)
- [ ] Templates include cloud-init CDROM device

**Rollback**: `git rm -r templates/libvirt/`

---

### ✅ Task 1.2: Create Cloud-Init Templates

**Status**: 🔴 NOT STARTED  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 1 week  
**Dependencies**: None  
**ADR**: 0023

**Description**:  
Create cloud-init configuration templates for automated VM initialization (user accounts, SSH keys, network, packages).

**Files to Create** (per VM type):
- `templates/cloud-init/<vm-type>-user-data.yml.j2` (user account, SSH keys, packages)
- `templates/cloud-init/<vm-type>-meta-data.yml.j2` (instance ID, hostname)
- `templates/cloud-init/<vm-type>-network-config.yml.j2` (static IP configuration)

**VM Types**: registry, aap, haproxy, ocp-node (total: 12 templates)

**Reference**: ADR 0023 contains example cloud-init configs.

**Verification**:
- [ ] All 12 cloud-init templates created (4 VM types × 3 files)
- [ ] YAML syntax valid (`yamllint templates/cloud-init/*.yml.j2`)
- [ ] SSH key injection tested (variable: `ssh_public_key`)
- [ ] Network config supports static IP (variables: `vm_ip`, `vm_gateway`, `vm_dns`)

**Rollback**: `git rm -r templates/cloud-init/`

---

### ✅ Task 1.3: Rewrite provision-registry-vm.yml (community.libvirt)

**Status**: 🔴 NOT STARTED  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 1 week  
**Dependencies**: 🔒 Task 1.1 (libvirt templates), 🔒 Task 1.2 (cloud-init templates)  
**ADR**: 0023

**Description**:  
Rewrite `playbooks/provision-registry-vm.yml` to use `community.libvirt` instead of kcli. This is the **proof-of-concept** for the libvirt approach.

**Implementation Pattern**:
```yaml
- name: Check if VM already exists (idempotency)
  community.libvirt.virt:
    command: list_vms
  register: existing_vms

- name: End play if VM exists
  ansible.builtin.meta: end_play
  when: vm_name in existing_vms.list_vms

- name: Create cloud-init ISO
  ansible.builtin.command:
    cmd: genisoimage -output {{ cloud_init_iso }} -volid cidata -joliet -rock user-data meta-data network-config

- name: Define VM in libvirt
  community.libvirt.virt:
    command: define
    xml: "{{ lookup('template', 'templates/libvirt/registry-vm.xml.j2') }}"

- name: Start VM
  community.libvirt.virt:
    name: "{{ vm_name }}"
    state: running
```

**Before Starting**:
- [ ] Backup current playbook: `cp playbooks/provision-registry-vm.yml archive/kcli-legacy/provision-registry-vm.yml.bak`

**Verification**:
- [ ] Playbook syntax valid (`ansible-playbook --syntax-check playbooks/provision-registry-vm.yml`)
- [ ] Idempotency test: Run twice, second run skips VM creation
- [ ] VM boots and cloud-init applies successfully (check `/var/log/cloud-init.log` in VM)
- [ ] SSH access works with injected key (`ssh -i ~/.ssh/id_rsa <vm_user>@<vm_ip>`)

**Rollback**: Restore from backup: `cp archive/kcli-legacy/provision-registry-vm.yml.bak playbooks/provision-registry-vm.yml`

---

### ✅ Task 1.4: Create tasks/provision-vm-libvirt.yml (Reusable Task)

**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Owner**: Platform Team  
**Effort**: 3 days  
**Dependencies**: 🔒 Task 1.3 (pattern proven in registry VM)  
**ADR**: 0023

**Description**:  
Extract common VM provisioning logic from `provision-registry-vm.yml` into a reusable task file. This will be used by all future VM provisioning playbooks.

**File to Create**: `tasks/provision-vm-libvirt.yml`

**Parameters** (passed via variables):
- `vm_name` (e.g., "registry-vm")
- `vm_memory` (MB, e.g., 8192)
- `vm_cpus` (e.g., 2)
- `vm_disk_size` (GB, e.g., 60)
- `base_image` (e.g., "/var/lib/libvirt/images/rhel-9.4.qcow2")
- `vm_template` (e.g., "templates/libvirt/registry-vm.xml.j2")
- `cloud_init_user_data_template` (e.g., "templates/cloud-init/registry-user-data.yml.j2")
- `cloud_init_meta_data_template`
- `cloud_init_network_config_template`

**Verification**:
- [ ] Task file syntax valid
- [ ] Can be included in multiple playbooks (`ansible.builtin.include_tasks`)
- [ ] Variables properly parameterized (no hardcoded values)
- [ ] Idempotency preserved (checks for existing VM)

**Rollback**: `git rm tasks/provision-vm-libvirt.yml`

---

### ✅ Task 1.5: Create provision-haproxy-vm.yml

**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Owner**: Platform Team  
**Effort**: 2 days  
**Dependencies**: 🔒 Task 1.4 (reusable task)  
**ADR**: 0023

**Description**:  
Create new playbook for HAProxy VM using reusable task. HAProxy will be used for load balancing OCP API/Ingress traffic.

**File to Create**: `playbooks/provision-haproxy-vm.yml`

**VM Specs**:
- 2 vCPU
- 4GB RAM
- 20GB disk

**Verification**:
- [ ] HAProxy VM provisions successfully
- [ ] Cloud-init configures network correctly
- [ ] SSH access works
- [ ] HAProxy service can be installed post-boot (manual test)

**Rollback**: `git rm playbooks/provision-haproxy-vm.yml`

---

### ✅ Task 1.6: Create provision-ocp-nodes-vms.yml

**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Owner**: Platform Team  
**Effort**: 3 days  
**Dependencies**: 🔒 Task 1.4 (reusable task)  
**ADR**: 0023

**Description**:  
Create playbook for provisioning OCP master/worker nodes. Loop over node list to provision multiple VMs with different specs.

**File to Create**: `playbooks/provision-ocp-nodes-vms.yml`

**Node List** (example):
- 3 master nodes (16GB RAM, 4 vCPU, 120GB disk each)
- 2 worker nodes (32GB RAM, 8 vCPU, 200GB disk each)

**Verification**:
- [ ] All 5 VMs provision successfully
- [ ] VMs boot and respond to SSH
- [ ] Adequate resources for OCP installation
- [ ] VMs accessible via static IPs (or DHCP)

**Rollback**: `git rm playbooks/provision-ocp-nodes-vms.yml`

---

### ✅ Task 1.7: Update docs/libvirt-vm-provisioning.md

**Status**: 🔴 NOT STARTED  
**Priority**: P3  
**Owner**: Platform Team  
**Effort**: 1 day  
**Dependencies**: 🔒 Task 1.3, 1.4, 1.5, 1.6 (all playbooks complete)  
**ADR**: 0023

**Description**:  
Document pure Ansible VM provisioning approach for users and contributors.

**File to Create**: `docs/libvirt-vm-provisioning.md`

**Sections**:
- community.libvirt collection installation
- Libvirt XML template structure
- Cloud-init configuration patterns
- Idempotency best practices
- Troubleshooting common issues (e.g., "VM not booting", "cloud-init not applying")
- Example playbooks with usage

**Verification**:
- [ ] Documentation complete
- [ ] Code examples tested (copy-paste works)
- [ ] Troubleshooting section covers common errors from testing
- [ ] Links to upstream documentation (libvirt, cloud-init)

**Rollback**: `git rm docs/libvirt-vm-provisioning.md`

---

## Phase 2: Independence - Qubinode Removal (Weeks 3-8)

### ✅ Task 2.1: Create playbooks/setup-dependencies.yml

**Status**: 🔴 NOT STARTED  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 1 week  
**Dependencies**: None  
**ADR**: 0022

**Description**:  
Create playbook to replace qubinode_navigator setup functionality. This is the **core playbook** that makes the repository self-contained.

**File to Create**: `playbooks/setup-dependencies.yml`

**What It Installs**:
- ansible-core (2.15+)
- libvirt, libvirt-client, qemu-kvm
- python3-libvirt, python3-pip
- virt-install, genisoimage
- wget, curl, git

**What It Configures**:
- Enables and starts libvirtd service
- Installs Ansible collections: `community.libvirt`, `ansible.posix`
- Creates directories: `/var/lib/libvirt/images`, `/opt/ocp4-disconnected-helper`
- Verifies libvirt connection works

**Reference**: ADR 0022 contains full playbook example.

**Verification**:
- [ ] Runs successfully on fresh RHEL 9.4 VM
- [ ] All packages installed (`rpm -q ansible-core libvirt qemu-kvm`)
- [ ] Libvirt operational (`systemctl status libvirtd`)
- [ ] Ansible collections available (`ansible-galaxy collection list | grep community.libvirt`)
- [ ] Directory structure created (`ls -ld /var/lib/libvirt/images`)

**Rollback**: `git rm playbooks/setup-dependencies.yml` (manual package cleanup required)

---

### ✅ Task 2.2: Create docs/PREREQUISITES.md

**Status**: 🔴 NOT STARTED  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 2 days  
**Dependencies**: 🔒 Task 2.1 (setup-dependencies.yml complete)  
**ADR**: 0022

**Description**:  
Document OS installation and setup requirements. This is the **entry point** for all new users.

**File to Create**: `docs/PREREQUISITES.md`

**Sections**:
- Supported Operating Systems (RHEL 9.4+, CentOS Stream 9.4+)
- Hardware Requirements (CPU, RAM, disk for development vs. production)
- Network Requirements (static IP, DNS, proxy config)
- Installation Steps (OS install → clone repo → run setup-dependencies.yml)
- Troubleshooting (libvirt connection failed, permission denied, disk space)

**Verification**:
- [ ] Documentation complete
- [ ] Tested on fresh RHEL 9.4 VM (follow doc from scratch)
- [ ] Troubleshooting section covers errors encountered during testing
- [ ] Links to Red Hat documentation (subscription management, RHEL installation)

**Rollback**: `git rm docs/PREREQUISITES.md`

---

### ✅ Task 2.3: Update README.md (Remove Qubinode References)

**Status**: 🔴 NOT STARTED  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 1 day  
**Dependencies**: 🔒 Task 2.1 (setup-dependencies.yml), 🔒 Task 2.2 (PREREQUISITES.md)  
**ADR**: 0022

**Description**:  
Rewrite README to reflect standalone architecture. Remove **all** qubinode references.

**Changes**:
- Remove "Prerequisites: qubinode_navigator installation"
- Add "Quick Start" section pointing to [PREREQUISITES.md](docs/PREREQUISITES.md)
- Update "Setup" section to use `setup-dependencies.yml`
- Add note about `v4.20.0-airflow` tag for legacy users
- Update "Execution Tiers" section (Tier 1: shell/Ansible, Tier 2: AAP optional)

**Before Starting**:
- [ ] Backup current README: `cp README.md README.md.v4.20.0.bak`

**Verification**:
- [ ] No "qubinode" references remain (`grep -i qubinode README.md` returns nothing)
- [ ] Quick Start tested by new user (fresh VM, follow README from scratch)
- [ ] Links to all new documentation valid (PREREQUISITES.md, setup-dependencies.yml)
- [ ] Badge links updated (if applicable)

**Rollback**: `git checkout HEAD -- README.md`

---

### ✅ Task 2.4: Mark ADRs 0001, 0011 as SUPERSEDED

**Status**: 🔴 NOT STARTED  
**Priority**: P3  
**Owner**: Platform Team  
**Effort**: 30 minutes  
**Dependencies**: 🔒 Task 2.3 (README updated)  
**ADR**: 0022

**Description**:  
Update legacy ADRs to indicate superseded status. Add deprecation notice at top.

**Files to Update**:
- `docs/adrs/0001-two-tier-architecture.md`
- `docs/adrs/0011-qubinode-navigator-integration.md`

**Header to Add**:
```markdown
**Status:** SUPERSEDED by ADR 0022  
**Date Superseded:** 2026-06-02  
**Migration Guide:** See [MIGRATION-QUBINODE-TO-STANDALONE.md](../MIGRATION-QUBINODE-TO-STANDALONE.md)

---

**⚠️ IMPORTANT**: This ADR is deprecated as of v4.21.0. The two-tier architecture with qubinode_navigator has been replaced by a self-contained, standalone architecture. Users on v4.20.0-airflow should follow the migration guide.

---

# [Original ADR Content Below]
```

**Verification**:
- [ ] Both ADRs updated with superseded notice
- [ ] Links to migration guide valid
- [ ] Original ADR content preserved below notice

**Rollback**: Remove superseded notices via `git checkout HEAD -- docs/adrs/0001-*.md docs/adrs/0011-*.md`

---

### ✅ Task 2.5: Create docs/MIGRATION-QUBINODE-TO-STANDALONE.md

**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Owner**: Platform Team  
**Effort**: 1 day  
**Dependencies**: 🔒 Task 2.1, 🔒 Task 2.2, 🔒 Task 2.3  
**ADR**: 0022

**Description**:  
Migration guide for users currently using qubinode_navigator.

**File to Create**: `docs/MIGRATION-QUBINODE-TO-STANDALONE.md`

**Sections**:
- Who Should Use This Guide (qubinode users on v4.20.0)
- Overview (what's changing, why)
- Migration Steps (backup → provision new host → clone v4.21.0 → setup-dependencies.yml → migrate inventory)
- What Changed table (before/after comparison)
- Troubleshooting ("qubinode command not found" → expected, "MCP tools missing" → removed)
- Rollback (git checkout v4.20.0-airflow)

**Reference**: ADR 0022 contains example migration guide structure.

**Verification**:
- [ ] Migration guide complete
- [ ] Tested with actual qubinode user (if available)
- [ ] Troubleshooting covers common issues
- [ ] Rollback procedure tested

**Rollback**: `git rm docs/MIGRATION-QUBINODE-TO-STANDALONE.md`

---

## Phase 3: Orchestration - AAP Adoption (Weeks 2-15) ⚠️ CRITICAL PATH

### ✅ Task 3.1: Create playbooks/provision-aap-vm.yml

**Status**: 🔴 NOT STARTED  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 3 days  
**Dependencies**: 🔒 Task 1.4 (reusable task), 🔒 Task 0.3 (AAP subscription) ⚠️  
**ADR**: 0021

**Description**:  
Provision AAP VM on KVM using `community.libvirt` and reusable task from Task 1.4.

**File to Create**: `playbooks/provision-aap-vm.yml`

**VM Specs** (AAP 2.5 minimum requirements):
- 4 vCPU
- 16GB RAM
- 60GB disk

**Reference**: ADR 0021 contains example playbook.

**Verification**:
- [ ] AAP VM provisions with correct specs (4 vCPU, 16GB RAM, 60GB disk)
- [ ] VM boots successfully
- [ ] SSH access works
- [ ] RHEL subscription can be applied (`subscription-manager register`)

**Rollback**: `git rm playbooks/provision-aap-vm.yml`, delete VM: `virsh undefine aap-controller`

---

### ✅ Task 3.2: Create playbooks/setup-aap-containerized.yml

**Status**: 🔴 NOT STARTED  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 1 week  
**Dependencies**: 🔒 Task 3.1 (AAP VM exists)  
**ADR**: 0021

**Description**:  
Install AAP 2.5 containerized (Growth Topology) on provisioned VM.

**File to Create**: `playbooks/setup-aap-containerized.yml`

**Steps**:
1. Subscribe RHEL system (`community.general.redhat_subscription`)
2. Enable AAP repos (`subscription-manager repos --enable=ansible-automation-platform-2.5-for-rhel-9-x86_64-rpms`)
3. Download AAP installer from Red Hat portal
4. Run containerized installer (`./setup.sh`)
5. Verify AAP is running (UI accessible)

**Reference**: ADR 0021 contains example playbook.

**Verification**:
- [ ] AAP installation completes without errors
- [ ] AAP UI accessible at https://aap-controller
- [ ] Can login with admin credentials (from inventory vars)
- [ ] All AAP services running (`podman ps` shows controller, database, redis)

**Rollback**: Uninstall AAP containers: `podman stop --all && podman rm --all && rm -rf /var/lib/awx`

---

### ✅ Task 3.3: Create scripts/migrate-dags-to-aap.py

**Status**: 🔴 NOT STARTED  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 1 week  
**Dependencies**: None (can run in parallel with 3.1, 3.2)  
**ADR**: 0021

**Description**:  
Automated script to convert Airflow DAGs to AAP Job Template YAML. This provides the **base conversion** that will be manually refined.

**File to Create**: `scripts/migrate-dags-to-aap.py`

**What It Does**:
1. Parses all `.py` files in `airflow/dags/`
2. Extracts `BashOperator` tasks (look for `ansible-playbook` commands)
3. Extracts task dependencies (`>>` operator, `set_downstream()`)
4. Generates AAP Job Template YAML in `aap/job-templates/`
5. Generates AAP Workflow Template YAML in `aap/workflows/`

**Reference**: ADR 0021 contains full script code.

**Verification**:
- [ ] Script runs without errors (`python3 scripts/migrate-dags-to-aap.py`)
- [ ] All 8 DAGs converted to YAML (8 files in `aap/job-templates/`)
- [ ] Workflow YAML generated for complex DAGs (5 files in `aap/workflows/`)
- [ ] YAML syntax valid (`yamllint aap/**/*.yml`)

**Rollback**: `git rm scripts/migrate-dags-to-aap.py aap/`

---

### ✅ Task 3.4: Manual Workflow Conversion (ocp_initial_deployment)

**Status**: 🔴 NOT STARTED  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 2 weeks  
**Dependencies**: 🔒 Task 3.3 (automated script provides base)  
**ADR**: 0021

**Description**:  
Manually refine automated conversion for primary workflow. This is the **proof-of-concept** for AAP workflow conversion.

**File to Refine**: `aap/workflows/ocp_initial_deployment.yml` (generated by script)

**Enhancements to Add**:
- AAP survey for runtime parameters (ocp_version, registry_type, clean_mirror)
- Map all 8 task dependencies correctly (validate against DAG file)
- Add error handling and retry logic (AAP-specific)
- Configure notifications (email/Slack on failure)
- Add workflow visualization metadata

**Verification**:
- [ ] Workflow imports successfully to AAP (`ansible-controller.workflow_job_template`)
- [ ] Survey prompts for correct parameters (test in AAP UI)
- [ ] All 8 tasks execute in correct order (run workflow end-to-end)
- [ ] Error handling triggers on task failure (introduce intentional failure, verify retry)

**Rollback**: Restore from automated script output: `git checkout HEAD -- aap/workflows/ocp_initial_deployment.yml`

---

### ✅ Task 3.5: Convert Remaining DAGs (7 DAGs)

**Status**: 🔴 NOT STARTED  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 4 weeks  
**Dependencies**: 🔒 Task 3.4 (pattern proven for primary workflow)  
**ADR**: 0021

**Description**:  
Manually convert remaining 7 Airflow DAGs to AAP workflows. Apply lessons learned from Task 3.4.

**DAGs to Convert** (checklist):
- [ ] `ocp_incremental_update.py` → `aap/workflows/ocp_incremental_update.yml`
- [ ] `ocp_registry_sync.py` → `aap/job-templates/ocp_registry_sync.yml` (simple job)
- [ ] `ocp_harbor_registry.py` → `aap/job-templates/ocp_harbor_registry.yml` (simple job)
- [ ] `ocp_jfrog_agent_deployment.py` → `aap/workflows/ocp_jfrog_agent_deployment.yml`
- [ ] `ocp_disconnected_workflow.py` → `aap/workflows/ocp_disconnected_workflow.yml`
- [ ] `ocp_pre_deployment_validation.py` → `aap/job-templates/ocp_pre_deployment_validation.yml` (simple job)
- [ ] `dag_helpers.py` → AAP custom execution environment (utility functions)

**Per-DAG Verification**:
- [ ] Workflow/job template imports to AAP
- [ ] Executes successfully (end-to-end test)
- [ ] Performance within 10% of Airflow (benchmark)
- [ ] Error handling works (retry, notifications)

**Rollback**: Use Airflow DAG for specific workflow (keep Airflow running during migration)

---

### ✅ Task 3.6: Create playbooks/aap-preload-job-templates.yml

**Status**: 🔴 NOT STARTED  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 1 week  
**Dependencies**: 🔒 Task 3.5 (all YAML created)  
**ADR**: 0021

**Description**:  
Automate AAP Job Template import from YAML definitions. This makes AAP setup **repeatable and version-controlled**.

**File to Create**: `playbooks/aap-preload-job-templates.yml`

**What It Does**:
1. Adds `ocp4-disconnected-helper` project to AAP (git-based)
2. Imports all job templates from `aap/job-templates/*.yml`
3. Imports all workflow templates from `aap/workflows/*.yml`
4. Configures surveys, schedules, notifications

**Collections Required**: `ansible.controller`

**Reference**: ADR 0021 contains full playbook example.

**Verification**:
- [ ] Playbook runs without errors
- [ ] All 8 job templates imported to AAP (check AAP UI → Templates)
- [ ] All 5 workflow templates imported (check AAP UI → Templates)
- [ ] AAP project synced from git (check AAP UI → Projects)

**Rollback**: Delete templates in AAP UI manually (or via `ansible.controller` playbook)

---

### 🎯 Task 3.7: Parallel Testing (Airflow vs AAP) ⚠️ GO/NO-GO #4

**Status**: 🔴 NOT STARTED  
**Priority**: P0 (GO/NO-GO DECISION #4)  
**Owner**: Platform Team  
**Effort**: 3 weeks  
**Dependencies**: 🔒 Task 3.6 (all templates imported)  
**ADR**: 0021

**Description**:  
Run Airflow DAG and AAP Workflow side-by-side to validate conversion. This is the **final validation** before committing to AAP.

**Test Matrix**:
For each workflow:
1. Execute Airflow DAG (v4.20.0-airflow tag)
2. Execute AAP Workflow (v4.21.0)
3. Compare:
   - **Execution time** (must be within 10%)
   - **Success/failure outcomes** (must match)
   - **Logs and output** (verify consistency)
   - **Resource usage** (CPU, memory, disk I/O)

**Workflows to Test**:
- [ ] `ocp_initial_deployment` - Airflow: ___min, AAP: ___min, Δ: ___%
- [ ] `ocp_incremental_update` - Airflow: ___min, AAP: ___min, Δ: ___%
- [ ] `ocp_registry_sync` - Airflow: ___min, AAP: ___min, Δ: ___%
- [ ] `ocp_harbor_registry` - Airflow: ___min, AAP: ___min, Δ: ___%
- [ ] `ocp_jfrog_agent_deployment` - Airflow: ___min, AAP: ___min, Δ: ___%
- [ ] `ocp_disconnected_workflow` - Airflow: ___min, AAP: ___min, Δ: ___%
- [ ] `ocp_pre_deployment_validation` - Airflow: ___min, AAP: ___min, Δ: ___%

**🎯 GO/NO-GO Criteria**:
- ✅ **GO**: All workflows within 10% performance, same outcomes → Proceed to Task 3.8
- ❌ **NO-GO**: >10% regression OR any workflow failures → Investigate, optimize, or **ROLLBACK** to v4.20.0-airflow

**Verification**:
- [ ] All workflows tested (7/7 complete)
- [ ] Performance acceptable (all within 10%)
- [ ] No regressions introduced (outcomes match)
- [ ] Test results documented (fill in table above)

**Rollback**: If NO-GO, **ABORT v4.21.0 release**, remain on v4.20.0-airflow, investigate issues.

---

### ✅ Task 3.8: Archive Airflow Code

**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Owner**: Platform Team  
**Effort**: 1 day  
**Dependencies**: 🔒 Task 3.7 (testing passed - GO decision)  
**ADR**: 0021

**Description**:  
Move Airflow code to `archive/airflow-legacy/` for reference. This is the **point of no return** for Airflow removal.

**Commands**:
```bash
# Move Airflow directory
mv airflow/ archive/airflow-legacy/

# Create deprecation notice
cat > archive/airflow-legacy/DEPRECATED.md <<EOF
# Airflow Orchestration (DEPRECATED)

⚠️ **DEPRECATED as of v4.21.0**

This directory contains the legacy Airflow-based orchestration code from v4.20.0.

## Why Deprecated?
Apache Airflow was replaced with Red Hat Ansible Automation Platform (AAP) 2.5 for:
- Enterprise support
- Unified Ansible ecosystem
- KVM deployability
- Better RBAC and audit logging

## Migration
See [MIGRATION-AIRFLOW-TO-AAP.md](../../docs/MIGRATION-AIRFLOW-TO-AAP.md)

## Legacy Support
Users requiring Airflow support should use tag \`v4.20.0-airflow\`.
No backports will be provided.
EOF

# Commit archive
git add archive/airflow-legacy/
git commit -m "chore: Archive legacy Airflow code (v4.20.0)"
```

**Verification**:
- [ ] `airflow/` directory moved to `archive/airflow-legacy/`
- [ ] `DEPRECATED.md` created with clear notice
- [ ] No `airflow/` references in active code (`grep -r "airflow/" --exclude-dir=archive`)

**Rollback**: `git revert HEAD && mv archive/airflow-legacy/airflow .`

---

### ✅ Task 3.9: Create docs/MIGRATION-AIRFLOW-TO-AAP.md

**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Owner**: Platform Team  
**Effort**: 2 days  
**Dependencies**: 🔒 Task 3.7 (testing complete, performance data available)  
**ADR**: 0021

**Description**:  
Migration guide for Airflow users.

**File to Create**: `docs/MIGRATION-AIRFLOW-TO-AAP.md`

**Sections**:
- Pre-Migration Checklist (AAP requirements, subscription, backups)
- Migration Steps (provision AAP VM → install AAP → import templates → test → decommission Airflow)
- Mapping: Airflow → AAP (DAG → Workflow, Task → Job Template, params → survey, etc.)
- Performance Comparison (use data from Task 3.7)
- Troubleshooting (AAP UI unreachable, playbook not found, performance issues)
- Rollback (git checkout v4.20.0-airflow, restart Airflow services)

**Reference**: ADR 0021 contains example migration guide structure.

**Verification**:
- [ ] Migration guide complete
- [ ] Tested with actual Airflow user (if available)
- [ ] Performance comparison table filled with real data from Task 3.7
- [ ] Troubleshooting covers common issues

**Rollback**: `git rm docs/MIGRATION-AIRFLOW-TO-AAP.md`

---

### ✅ Task 3.10: Create docs/aap-setup.md

**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Owner**: Platform Team  
**Effort**: 2 days  
**Dependencies**: 🔒 Task 3.2 (AAP installation complete, lessons learned)  
**ADR**: 0021

**Description**:  
Comprehensive AAP setup and configuration guide for users and contributors.

**File to Create**: `docs/aap-setup.md`

**Sections**:
- AAP System Requirements (CPU, RAM, disk for different topologies)
- Containerized vs. RPM Installation (when to use each)
- Growth Topology Deployment (recommended for this project)
- RBAC Configuration (users, teams, permissions)
- Inventory Setup (how to configure inventories in AAP)
- Credential Management (SSH keys, vault passwords, tokens)
- Custom Execution Environments (for dag_helpers.py utilities)
- Backup and Recovery (AAP database backup, disaster recovery)
- Troubleshooting (common AAP issues, logs to check)

**Verification**:
- [ ] Documentation complete
- [ ] Code examples tested (copy-paste works)
- [ ] Covers all AAP features used in this project
- [ ] Links to upstream Red Hat documentation

**Rollback**: `git rm docs/aap-setup.md`

---

## Phase 4: Documentation & Finalization (Weeks 16-17)

### ✅ Task 4.1: Create RELEASE_PLAN.md

**Status**: ✅ DONE  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 3 days  
**Dependencies**: None (created alongside TODO.md)

**Description**:  
Executive-level release plan document for stakeholder communication.

**File Created**: `RELEASE_PLAN.md`

**Verification**:
- [x] RELEASE_PLAN.md exists
- [x] All phases documented with timelines
- [x] Risk matrix complete
- [x] Go/No-Go criteria defined
- [x] Cost analysis included

**Rollback**: `git rm RELEASE_PLAN.md`

---

### ✅ Task 4.2: Create CHANGELOG.md

**Status**: ✅ DONE  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 2 days  
**Dependencies**: Task 4.1 (RELEASE_PLAN provides structure)

**Description**:  
User-facing changelog in Keep a Changelog format.

**File Created**: `CHANGELOG.md`

**Verification**:
- [x] CHANGELOG.md exists
- [x] All breaking changes documented
- [x] Migration guides linked
- [x] Keep a Changelog v1.1.0 format followed

**Rollback**: `git rm CHANGELOG.md`

---

### ✅ Task 4.3: Create TODO.md

**Status**: ✅ DONE  
**Priority**: P1  
**Owner**: Platform Team  
**Effort**: 1 day  
**Dependencies**: Task 4.2 (CHANGELOG provides context)

**Description**:  
Trackable task list for development (this document).

**File Created**: `TODO.md`

**Verification**:
- [x] TODO.md created
- [x] All 31 tasks listed
- [x] Dependencies mapped with 🔒 indicators
- [x] Checkboxes for tracking progress

**Rollback**: `git rm TODO.md`

---

### ✅ Task 4.4: Update All ADRs with v4.21.0 Release Date

**Status**: 🔴 NOT STARTED  
**Priority**: P3  
**Owner**: Platform Team  
**Effort**: 30 minutes  
**Dependencies**: 🔒 All implementation complete (Tasks 0.1-3.10)

**Description**:  
Set final release date in ADRs 0021, 0022, 0023 once v4.21.0 ships.

**Files to Update**:
- `docs/adrs/0021-deprecate-airflow-adopt-aap.md` (replace "TBD" with actual date)
- `docs/adrs/0022-deprecate-qubinode-navigator.md`
- `docs/adrs/0023-pure-ansible-community-libvirt.md`

**Commands**:
```bash
# Example: Release on 2026-10-15
sed -i 's/TBD (Target: Q4 2026)/2026-10-15/g' docs/adrs/002{1,2,3}-*.md
git add docs/adrs/002{1,2,3}-*.md
git commit -m "docs: Set v4.21.0 release date in ADRs"
```

**Verification**:
- [ ] All 3 ADRs updated with release date
- [ ] Dates consistent across CHANGELOG.md and RELEASE_PLAN.md

**Rollback**: Restore TBD: `sed -i 's/2026-10-15/TBD (Target: Q4 2026)/g' docs/adrs/002{1,2,3}-*.md`

---

### ✅ Task 4.5: Final Documentation Review

**Status**: 🔴 NOT STARTED  
**Priority**: P2  
**Owner**: Platform Team  
**Effort**: 1 week  
**Dependencies**: 🔒 All docs created (Tasks 1.7, 2.2, 2.5, 3.9, 3.10)

**Description**:  
Comprehensive review of all documentation for accuracy, consistency, and completeness.

**Review Checklist**:
- [ ] `README.md` - No qubinode/Airflow/kcli references
- [ ] `PREREQUISITES.md` - Tested on fresh RHEL 9.4 VM
- [ ] `CHANGELOG.md` - All changes documented, links work
- [ ] `RELEASE_PLAN.md` - Timeline accurate, costs updated
- [ ] `TODO.md` - All tasks present, checkboxes work
- [ ] ADRs 0021, 0022, 0023 - Implementation matches documentation
- [ ] Migration guides (Airflow→AAP, Qubinode→Standalone) - Tested by external user
- [ ] `docs/aap-setup.md` - Complete and accurate, code examples work
- [ ] `docs/libvirt-vm-provisioning.md` - Examples tested, troubleshooting complete
- [ ] No broken links (`markdown-link-check docs/**/*.md`)
- [ ] Spelling/grammar checked (`aspell check docs/**/*.md`)

**Verification**:
- [ ] All docs reviewed (checklist complete)
- [ ] No broken links found
- [ ] All code examples tested (copy-paste works)
- [ ] External user tested migration guides (feedback incorporated)

**Rollback**: Fix identified issues via git commits.

---

### ✅ Task 4.6: Tag v4.21.0 Release

**Status**: 🔴 NOT STARTED  
**Priority**: P0 (RELEASE BLOCKER)  
**Owner**: Platform Team  
**Effort**: 15 minutes  
**Dependencies**: 🔒 ALL TASKS COMPLETE (0.1-4.5)

**Description**:  
Create official v4.21.0 release tag. This is the **final step** in the migration.

**Before Tagging**:
- [ ] Verify all tasks complete: `grep "🔴 NOT STARTED" TODO.md` (should return nothing)
- [ ] All tests passing (Phase 3.7 GO decision)
- [ ] Documentation complete (Phase 4.5)

**Commands**:
```bash
# Create annotated tag
git tag -a v4.21.0 -m "Release v4.21.0: AAP adoption, standalone architecture, pure Ansible

Breaking changes:
- Removed Apache Airflow (replaced with AAP 2.5)
- Removed qubinode_navigator dependency (self-contained)
- Removed kcli (replaced with community.libvirt)

See CHANGELOG.md for full details."

# Push tag
git push origin v4.21.0

# Create GitHub release
gh release create v4.21.0 \
  --title "v4.21.0: Revolutionary Architecture Change" \
  --notes-file CHANGELOG.md
```

**Verification**:
- [ ] Tag created (`git tag -l v4.21.0`)
- [ ] Tag pushed to origin (`git ls-remote --tags origin | grep v4.21.0`)
- [ ] GitHub release published (check https://github.com/tosin2013/ocp4-disconnected-helper/releases)
- [ ] Release notes link to CHANGELOG.md

**Rollback**: Delete tag (ONLY before public announcement): `git tag -d v4.21.0 && git push origin :refs/tags/v4.21.0`

---

## Progress Tracking

### Overall Progress by Phase

```
[Phase 0]  ████████░░░░░░░░░░░░ 0/3 (0%)
[Phase 1]  ██░░░░░░░░░░░░░░░░░░ 0/7 (0%)
[Phase 2]  █░░░░░░░░░░░░░░░░░░░ 0/5 (0%)
[Phase 3]  █░░░░░░░░░░░░░░░░░░░ 0/10 (0%)
[Phase 4]  ███████████░░░░░░░░░ 3/6 (50%)

Total:     ███░░░░░░░░░░░░░░░░░ 3/31 (10%)
```

**Note**: Phase 4 shows 50% because RELEASE_PLAN.md, CHANGELOG.md, and TODO.md (this file) are already created.

---

## Critical Dependencies Graph

```
Task 0.1 (Tag v4.20.0) ─┐
                        ├─> Task 0.2 (Archive dir)
                        └─> Task 0.3 (AAP subscription) ──┐
                                                           │
Task 1.1 (Libvirt tmpl) ─┬─> Task 1.3 (Registry VM) ─────┼─> Task 1.4 (Reusable task) ─┬─> Task 1.5 (HAProxy)
Task 1.2 (Cloud-init) ───┘                                │                              ├─> Task 1.6 (OCP nodes)
                                                           │                              └─> Task 3.1 (AAP VM) ──┐
                                                           │                                                      │
Task 2.1 (setup-deps) ───┬─> Task 2.2 (PREREQ) ─────────> Task 2.3 (README) ──> Task 2.4 (Mark ADRs) ──────────┤
                         └─> Task 2.5 (Migration guide)                                                          │
                                                                                                                  │
                                                         ┌────────────────────────────────────────────────────────┘
                                                         │
                                                         └─> Task 3.2 (AAP install) ──┐
                                                                                      │
Task 3.3 (Migration script) ──> Task 3.4 (Primary DAG) ──> Task 3.5 (Remaining DAGs) ┼──> Task 3.6 (Preload) ──┐
                                                                                      │                           │
                                                                                      └─> Task 3.10 (aap-setup) ──┤
                                                                                                                  │
                                                         ┌────────────────────────────────────────────────────────┘
                                                         │
Task 1.7 (libvirt docs) ─────────────────────────────────┼──> Task 3.7 (Testing GO/NO-GO) ──┬─> Task 3.8 (Archive Airflow)
Task 3.9 (Airflow migration guide) ──────────────────────┘                                   │
                                                                                              └─> Task 4.4 (ADR dates) ──┐
                                                                                                                          │
Task 4.1 (RELEASE_PLAN) ──> Task 4.2 (CHANGELOG) ──> Task 4.3 (TODO) ──────────────────────────────────────────────────┤
                                                                                                                          │
                                                         ┌────────────────────────────────────────────────────────────────┘
                                                         │
                                                         └──> Task 4.5 (Final review) ──> Task 4.6 (Tag v4.21.0) ✅
```

**Legend**:
- `─>` = Sequential dependency (must complete before next)
- `─┬─>` = Parallel fan-out (multiple tasks can run)
- `─┴─>` = Parallel fan-in (all must complete before next)

---

## Risk Heatmap

| Task | Risk Level | Impact | Likelihood | Mitigation |
|------|------------|--------|------------|------------|
| 0.3 AAP Subscription | 🔴 CRITICAL | HIGH | MEDIUM | Start Week 1, escalate if delayed |
| 3.7 Parallel Testing | 🔴 CRITICAL | HIGH | HIGH | 3-week buffer, GO/NO-GO decision |
| 3.4-3.5 DAG Conversion | 🟡 HIGH | HIGH | MEDIUM | Automated script base, manual refinement |
| 1.3 Registry VM Rewrite | 🟡 HIGH | MEDIUM | MEDIUM | Backup original, test idempotency |
| 2.1 setup-dependencies.yml | 🟢 MEDIUM | MEDIUM | LOW | Test on fresh RHEL 9.4 VM |

**Legend**:
- 🔴 CRITICAL: Could abort migration
- 🟡 HIGH: Significant timeline impact
- 🟢 MEDIUM/LOW: Manageable

---

## Weekly Checklist (Track Progress)

**Week 1**:
- [ ] Task 0.1: Tag v4.20.0-airflow
- [ ] Task 0.2: Archive directory
- [ ] Task 0.3: AAP subscription approval (start process)
- [ ] Task 1.1: Libvirt templates

**Week 2**:
- [ ] Task 1.2: Cloud-init templates
- [ ] Task 1.3: Registry VM rewrite

**Week 3**:
- [ ] Task 1.4: Reusable task
- [ ] Task 2.1: setup-dependencies.yml
- [ ] Task 3.1: AAP VM provisioning

**Week 4**:
- [ ] Task 1.5: HAProxy VM
- [ ] Task 1.6: OCP nodes VMs
- [ ] Task 2.2: PREREQUISITES.md
- [ ] Task 3.2: AAP installation

*(Continue weekly checklists through Week 17...)*

---

**Last Updated**: 2026-06-02  
**Total Tasks**: 31  
**Completed**: 3 (10%)  
**In Progress**: 0  
**Not Started**: 28  
**Blocked**: 0

**Next Actions**:
1. Get stakeholder approval for RELEASE_PLAN.md
2. Start Task 0.1 (tag v4.20.0-airflow)
3. Start Task 0.3 (AAP subscription approval) in parallel
