# ADR 0022: Deprecate qubinode_navigator Dependency

**Status:** Accepted  
**Date:** 2026-06-02  
**Deciders:** Platform Team, Product Owner (Tosin)  
**Supersedes:** ADR 0001 (Two-Tier Architecture), ADR 0011 (qubinode_navigator Integration)  
**PRD Reference:** PRD v4.21.0 Section 3 - The "Develop to Production" Philosophy

## Context

The ocp4-disconnected-helper project currently operates within a **two-tier architecture** defined in ADR 0001:

1. **qubinode_navigator (Tier 1)** - Infrastructure + Orchestration
   - Prepares CentOS Stream 10 servers
   - Installs dependencies
   - Provides Airflow orchestration
   - Includes MCP server integration (9 tools)

2. **ocp4-disconnected-helper (Tier 2)** - Automation
   - Ansible playbooks for heavy lifting
   - Airflow DAG definitions
   - Can run standalone (with limitations)

This architecture was formalized in ADR 0001 (accepted 2025-11-25, revised 2025-11-25) and ADR 0011 (qubinode_navigator Integration).

However, the **PRD v4.21.0** (dated 2026-05-28) introduces a new strategic direction:

### PRD Requirements (Section 3)

> "The core tenet of this project is that the local development experience must perfectly mirror the production deployment, differing only in the target IP addresses and MAC addresses defined in the Ansible inventory."

**Development (KVM) → Fork & Adapt → Production (Bare Metal)**

1. **Development (KVM)**: User clones repo, runs playbooks, pure Ansible (`community.libvirt`) spins up VMs
2. **Fork & Adapt**: Organization forks repo, updates inventory/extra_vars with bare-metal MAC addresses
3. **Production (Bare Metal)**: Run **exact same playbooks**, Agent-based Installer boots on physical hardware

### Problem with Current Architecture

The qubinode_navigator dependency **violates the Development → Production parity principle**:

| Aspect | Current (with qubinode_navigator) | PRD Requirement |
|--------|----------------------------------|------------------|
| **Dependency** | External project (qubinode_navigator) | Self-contained repository |
| **Installation** | Multi-step: Install qubinode → Install ocp4-helper | Single clone + run playbooks |
| **VM Provisioning** | Relies on qubinode's kcli wrapper | Pure Ansible `community.libvirt` |
| **Orchestration** | Airflow from qubinode | AAP or shell/Ansible (see ADR 0021) |
| **Portability** | Requires qubinode setup | Standalone, forkable repository |
| **Development → Production** | Different paths (qubinode dev, bare metal prod) | Identical playbooks, different inventory |

### Additional Motivations

1. **MCP Integration Loss is Acceptable**: With Airflow deprecation (ADR 0021), the primary value of qubinode_navigator (Airflow + MCP) is eliminated
2. **Complexity Reduction**: Removing external dependency simplifies onboarding and troubleshooting
3. **Forking Strategy**: Organizations want to fork ocp4-disconnected-helper, not both repos
4. **Self-Containment**: All VM provisioning, orchestration, and automation in one repository

## Decision

**Deprecate the qubinode_navigator dependency** and make ocp4-disconnected-helper a **fully self-contained, standalone repository**.

### Revised Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│              ocp4-disconnected-helper (Standalone)              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Tier 1: Shell + Ansible CLI                             │  │
│  │  - Pure Ansible playbooks                                │  │
│  │  - community.libvirt for KVM provisioning                │  │
│  │  - ansible-playbook CLI execution                        │  │
│  │  - cicd.sh wrapper script                                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                  │
│                              ▼                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Tier 2: AAP (Optional)                                   │  │
│  │  - AAP 2.5 Containerized (on KVM or bare metal)          │  │
│  │  - Job Templates for workflows                            │  │
│  │  - provision-aap-vm.yml (using community.libvirt)         │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Core Automation (Ansible Playbooks)                      │  │
│  │  - download-to-tar.yml                                    │  │
│  │  - push-tar-to-registry.yml                               │  │
│  │  - build-appliance.yml                                    │  │
│  │  - setup-*-registry.yml                                   │  │
│  │  - provision-*-vm.yml (using community.libvirt)           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

NO EXTERNAL DEPENDENCIES (qubinode_navigator removed)
```

### From Two-Tier to Self-Contained

**Before (ADR 0001 - Two-Tier with qubinode_navigator):**
```
qubinode_navigator        → Tier 1 (Infrastructure + Orchestration)
ocp4-disconnected-helper  → Tier 2 (Automation)
```

**After (This ADR - Self-Contained):**
```
ocp4-disconnected-helper  → Single repository with two execution models:
                             - Tier 1: Shell + ansible-playbook (required)
                             - Tier 2: AAP Job Templates (optional)
```

## Rationale

### Why Remove qubinode_navigator?

| Concern | With qubinode_navigator | Without qubinode_navigator |
|---------|------------------------|---------------------------|
| **Setup complexity** | Install qubinode → Install ocp4-helper | Clone repo → Run playbooks |
| **Dependency management** | Two repos to maintain | Single repo |
| **Forking** | Fork both repos | Fork one repo |
| **Development → Production** | Different workflows | Identical playbooks |
| **VM provisioning** | kcli via qubinode | `community.libvirt` (pure Ansible) |
| **Orchestration** | Airflow from qubinode | AAP or shell/Ansible |
| **MCP integration** | Yes (9 tools) | ❌ Lost (acceptable trade-off) |
| **Learning curve** | Learn qubinode + ocp4-helper | Learn ocp4-helper only |

### What qubinode_navigator Provided (and How We Replace It)

| qubinode Feature | Replacement in ocp4-disconnected-helper |
|------------------|----------------------------------------|
| **CentOS Stream 10 setup** | Document prerequisites in README, user installs RHEL/CentOS manually |
| **Dependency installation** | Add `setup-dependencies.yml` playbook (install ansible-core, community.libvirt, oc-mirror) |
| **Airflow deployment** | ❌ Removed (see ADR 0021), replaced with AAP or shell/Ansible |
| **MCP server integration** | ❌ Removed (acceptable loss with Airflow deprecation) |
| **kcli VM provisioning** | Migrate to `community.libvirt` (see ADR 0023) |

### Development → Production Parity (PRD Section 3)

**Before (with qubinode_navigator):**
```
Development:
  1. Install qubinode_navigator on CentOS Stream 10
  2. qubinode deploys Airflow + MCP
  3. Clone ocp4-disconnected-helper
  4. Run DAGs via Airflow UI
  5. qubinode uses kcli to provision VMs

Production:
  1. No qubinode on production jump host
  2. Run ocp4-disconnected-helper playbooks directly
  3. Provision bare metal (not VMs)
  
⚠️ MISMATCH: Different tools (qubinode+kcli vs bare metal)
```

**After (standalone ocp4-disconnected-helper):**
```
Development (KVM):
  1. Clone ocp4-disconnected-helper
  2. ansible-playbook provision-registry-vm.yml  # Uses community.libvirt
  3. ansible-playbook download-to-tar.yml
  4. ansible-playbook push-tar-to-registry.yml
  5. ansible-playbook build-appliance.yml

Production (Bare Metal):
  1. Fork ocp4-disconnected-helper
  2. Update inventory: KVM MAC addresses → Bare metal MAC addresses
  3. ansible-playbook provision-registry-vm.yml  # Skipped (bare metal exists)
  4. ansible-playbook download-to-tar.yml        # IDENTICAL
  5. ansible-playbook push-tar-to-registry.yml   # IDENTICAL
  6. ansible-playbook build-appliance.yml        # IDENTICAL
  
✅ PARITY: Same playbooks, different inventory
```

## Consequences

### Positive

- ✅ **Self-contained repository**: No external dependencies, easier forking
- ✅ **Development → Production parity**: Identical playbooks, different inventory
- ✅ **Simplified setup**: Clone repo → Run playbooks (no qubinode installation)
- ✅ **Pure Ansible**: Single automation framework (`ansible-core` + `community.libvirt`)
- ✅ **Reduced learning curve**: Users learn one repository, not two
- ✅ **Better portability**: Works on any Linux with Ansible + libvirt
- ✅ **Clearer scope**: ocp4-disconnected-helper owns entire workflow

### Negative

- ⚠️ **MCP integration loss**: No AI-assisted workflow management (from qubinode_navigator)
- ⚠️ **CentOS Stream 10 setup**: Users must manually install base OS and dependencies
- ⚠️ **Migration effort**: Users on qubinode + ocp4-helper must migrate
- ⚠️ **Existing integrations**: Any qubinode-specific workflows will break
- ⚠️ **Loss of proven infrastructure layer**: qubinode_navigator was battle-tested for OS setup

### Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **User confusion** | MEDIUM | Clear migration guide, document prerequisites |
| **Lost functionality** | LOW | Document what users must do manually (OS setup) |
| **MCP integration demand** | LOW | Future: Standalone MCP server playbook (optional) |
| **Incomplete migration** | MEDIUM | Comprehensive testing of standalone workflows |

## Implementation Plan

### Phase 1: Document Prerequisites (Week 1)

Create `docs/PREREQUISITES.md`:

```markdown
# Prerequisites for ocp4-disconnected-helper

## Base System Requirements

### For Development (KVM)
- RHEL 9.4+ or CentOS Stream 10
- KVM/libvirt installed and enabled
- Ansible Core 2.16+
- Python 3.11+
- 16GB+ RAM (32GB recommended)
- 500GB+ available disk space

### For Production (Bare Metal)
- RHEL 9.4+ jump host with network access to bare-metal servers
- Ansible Core 2.16+
- Bare-metal servers pre-provisioned and accessible via SSH

## Installation Steps

### 1. Install Base OS
```bash
# Install RHEL 9.4 or CentOS Stream 10
# Subscribe system (RHEL only)
sudo subscription-manager register --username YOUR_USERNAME
sudo subscription-manager attach --auto
```

### 2. Install KVM/libvirt (Development only)
```bash
sudo dnf install -y qemu-kvm libvirt virt-install
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $(whoami)
```

### 3. Install Ansible
```bash
sudo dnf install -y ansible-core python3-pip
pip3 install --user ansible
ansible-galaxy collection install community.libvirt
```

### 4. Install OpenShift CLI tools
```bash
# Download oc and oc-mirror
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
tar -xzf openshift-client-linux.tar.gz
sudo mv oc /usr/local/bin/
sudo chmod +x /usr/local/bin/oc

# Download oc-mirror
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/oc-mirror.tar.gz
tar -xzf oc-mirror.tar.gz
sudo mv oc-mirror /usr/local/bin/
sudo chmod +x /usr/local/bin/oc-mirror
```

### 5. Clone ocp4-disconnected-helper
```bash
git clone https://github.com/yourorg/ocp4-disconnected-helper.git
cd ocp4-disconnected-helper
```

**No qubinode_navigator installation needed!**
```

### Phase 2: Create Dependency Installation Playbook (Week 2)

Create `playbooks/setup-dependencies.yml`:

```yaml
---
- name: Install ocp4-disconnected-helper Dependencies
  hosts: localhost
  become: yes
  vars:
    ansible_python_interpreter: /usr/bin/python3
  
  tasks:
    - name: Install base packages
      ansible.builtin.dnf:
        name:
          - ansible-core
          - python3-pip
          - python3-libvirt
          - qemu-kvm
          - libvirt
          - virt-install
          - git
          - wget
          - curl
        state: present
    
    - name: Enable libvirtd service
      ansible.builtin.systemd:
        name: libvirtd
        enabled: yes
        state: started
    
    - name: Add user to libvirt group
      ansible.builtin.user:
        name: "{{ ansible_user_id }}"
        groups: libvirt
        append: yes
    
    - name: Install Ansible collections
      ansible.builtin.command:
        cmd: ansible-galaxy collection install community.libvirt
      become: no
    
    - name: Download oc CLI
      ansible.builtin.get_url:
        url: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
        dest: /tmp/oc-client.tar.gz
    
    - name: Extract oc CLI
      ansible.builtin.unarchive:
        src: /tmp/oc-client.tar.gz
        dest: /usr/local/bin
        remote_src: yes
        creates: /usr/local/bin/oc
    
    - name: Download oc-mirror
      ansible.builtin.get_url:
        url: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/oc-mirror.tar.gz
        dest: /tmp/oc-mirror.tar.gz
    
    - name: Extract oc-mirror
      ansible.builtin.unarchive:
        src: /tmp/oc-mirror.tar.gz
        dest: /usr/local/bin
        remote_src: yes
        creates: /usr/local/bin/oc-mirror
    
    - name: Verify installations
      ansible.builtin.shell: |
        echo "Ansible: $(ansible --version | head -1)"
        echo "oc: $(oc version --client)"
        echo "oc-mirror: $(oc-mirror version)"
        echo "libvirt: $(virsh version)"
      register: version_check
    
    - name: Display installation summary
      ansible.builtin.debug:
        msg: "{{ version_check.stdout_lines }}"
```

### Phase 3: Update README (Week 2)

**Remove all qubinode_navigator references:**

```bash
# Before (v4.20.0 with qubinode)
git clone https://github.com/yourorg/qubinode_navigator.git
cd qubinode_navigator
./setup.sh  # Installs Airflow, MCP, dependencies
cd /root/ocp4-disconnected-helper
# Run DAGs via Airflow UI

# After (v4.21.0 standalone)
git clone https://github.com/yourorg/ocp4-disconnected-helper.git
cd ocp4-disconnected-helper
ansible-playbook playbooks/setup-dependencies.yml  # One-time setup
ansible-playbook playbooks/download-to-tar.yml     # Start working!
```

Update `README.md` introduction:

```markdown
# OpenShift 4 Disconnected Helper

**Self-contained automation** for deploying OpenShift in disconnected and air-gapped environments.

## Quick Start (Development on KVM)

```bash
# 1. Clone repository
git clone https://github.com/yourorg/ocp4-disconnected-helper.git
cd ocp4-disconnected-helper

# 2. Install dependencies (one-time setup)
ansible-playbook playbooks/setup-dependencies.yml

# 3. Provision registry VM on KVM
ansible-playbook playbooks/provision-registry-vm.yml

# 4. Download OpenShift images
ansible-playbook playbooks/download-to-tar.yml

# 5. Push to local registry
ansible-playbook playbooks/push-tar-to-registry.yml

# 6. Build appliance
ansible-playbook playbooks/build-appliance.yml
```

## Fork & Adapt for Production (Bare Metal)

```bash
# 1. Fork this repository
# 2. Update inventory file with bare-metal MAC addresses
# 3. Update extra_vars/ with production registry DNS
# 4. Run the SAME playbooks (skip provision-registry-vm.yml)
ansible-playbook playbooks/download-to-tar.yml        # IDENTICAL
ansible-playbook playbooks/push-tar-to-registry.yml   # IDENTICAL
ansible-playbook playbooks/build-appliance.yml        # IDENTICAL
```

**Development → Production Parity**: Same playbooks, different inventory.

---

**⚠️ DEPRECATED**: qubinode_navigator dependency removed in v4.21.0.  
For legacy Airflow workflows, see `v4.20.0-airflow` tag.
```

### Phase 4: Migration Guide (Week 3)

Create `docs/MIGRATION-QUBINODE-TO-STANDALONE.md`:

```markdown
# Migration Guide: qubinode_navigator + ocp4-disconnected-helper → Standalone

For users currently running ocp4-disconnected-helper with qubinode_navigator.

## What Changed?

- ❌ **qubinode_navigator** - No longer required
- ❌ **Airflow orchestration** - Replaced with AAP or shell/Ansible
- ❌ **MCP integration** - No longer available
- ❌ **kcli VM provisioning** - Replaced with `community.libvirt`
- ✅ **Standalone repository** - Self-contained, no external deps
- ✅ **Pure Ansible** - Uses `ansible-core` + `community.libvirt`

## Migration Steps

### Option 1: Start Fresh (Recommended)

```bash
# 1. Tag your current setup for reference
cd /root/ocp4-disconnected-helper
git remote add upstream https://github.com/yourorg/ocp4-disconnected-helper.git
git fetch upstream
git tag my-qubinode-setup

# 2. Backup your extra_vars and inventory
cp -r extra_vars/ ~/backup/extra_vars
cp inventory ~/backup/inventory

# 3. Pull latest standalone version
git checkout main
git pull upstream main

# 4. Install dependencies (replaces qubinode setup)
ansible-playbook playbooks/setup-dependencies.yml

# 5. Restore your configuration
cp ~/backup/extra_vars/* extra_vars/
cp ~/backup/inventory inventory

# 6. Run workflows via ansible-playbook CLI (no Airflow)
ansible-playbook playbooks/download-to-tar.yml
```

### Option 2: Parallel Installation (Keep qubinode for now)

```bash
# Clone standalone version to new directory
cd /root
git clone https://github.com/yourorg/ocp4-disconnected-helper.git ocp4-helper-standalone
cd ocp4-helper-standalone

# Install dependencies
ansible-playbook playbooks/setup-dependencies.yml

# Copy your existing configuration
cp /root/ocp4-disconnected-helper/extra_vars/* extra_vars/
cp /root/ocp4-disconnected-helper/inventory inventory

# Test standalone workflows
ansible-playbook playbooks/download-to-tar.yml

# Once validated, decommission qubinode
sudo systemctl stop airflow-*
rm -rf /root/qubinode_navigator
```

## What You Need to Do Manually (Previously Done by qubinode)

1. **CentOS Stream 10 / RHEL 9.4 Installation**: Install manually
2. **System Subscription**: `sudo subscription-manager register` (RHEL only)
3. **KVM/libvirt Setup**: Run `setup-dependencies.yml` playbook
4. **Ansible Installation**: Run `setup-dependencies.yml` playbook
5. **oc + oc-mirror**: Run `setup-dependencies.yml` playbook

**TL;DR**: Run `setup-dependencies.yml` once, replaces qubinode setup.

## Airflow Workflows → Shell/Ansible

| Old (Airflow via qubinode) | New (Shell/Ansible) |
|----------------------------|---------------------|
| Trigger DAG in Airflow UI | `ansible-playbook playbooks/ocp-initial-deployment.yml` |
| Monitor in Airflow dashboard | `tail -f /var/log/ansible.log` |
| Retry failed task in UI | Re-run playbook (idempotent) |
| Schedule via Airflow | Use `cron` or AAP schedules |

## AAP Migration (Optional)

If you need advanced orchestration (equivalent to Airflow):

```bash
# Provision AAP VM on KVM
ansible-playbook playbooks/provision-aap-vm.yml

# Install AAP 2.5 Containerized
ansible-playbook playbooks/setup-aap-containerized.yml

# Pre-load Job Templates
ansible-playbook playbooks/aap-preload-job-templates.yml

# Access AAP UI
https://aap-controller.example.com
```

See `docs/aap-setup.md` for full AAP migration guide.

## Troubleshooting

### "Where is Airflow?"
Airflow is deprecated in v4.21.0. Use `ansible-playbook` CLI or AAP instead.

### "Where is qubinode_navigator?"
No longer a dependency. `setup-dependencies.yml` replaces qubinode setup.

### "How do I provision VMs without kcli?"
Use `community.libvirt` (see ADR 0023): `ansible-playbook playbooks/provision-registry-vm.yml`

### "I need MCP integration"
MCP integration was removed with Airflow deprecation. Future: Standalone MCP playbook may be added.
```

### Phase 5: Update ADRs (Week 3)

**Mark superseded ADRs:**

```bash
# Update ADR 0001
sed -i '3s/.*/Status: Superseded by ADR 0022/' docs/adrs/0001-two-tier-architecture.md

# Update ADR 0011
sed -i '3s/.*/Status: Superseded by ADR 0022/' docs/adrs/0011-qubinode-navigator-integration.md
```

**Add supersession notices:**

```markdown
<!-- Add to top of ADR 0001 and ADR 0011 -->

---
**⚠️ SUPERSEDED**: This ADR is superseded by ADR 0022: Deprecate qubinode_navigator Dependency (2026-06-02).

The two-tier architecture with qubinode_navigator has been replaced with a self-contained standalone repository model.

See ADR 0022 for the new architecture.
---
```

### Phase 6: Remove qubinode References from Code (Week 4)

```bash
# Find all references to qubinode
grep -r "qubinode" --include="*.yml" --include="*.py" --include="*.md" .

# Update or remove files with qubinode references
# Examples:
# - playbooks/inventory → Remove qubinode hosts
# - docs/*.md → Update setup instructions
# - scripts/cicd.sh → Remove qubinode checks
```

### Phase 7: Testing (Weeks 5-6)

**Standalone workflow validation:**

```bash
# Test on fresh CentOS Stream 10 VM (no qubinode)
# 1. Clone repo
git clone https://github.com/yourorg/ocp4-disconnected-helper.git
cd ocp4-disconnected-helper

# 2. Install dependencies
ansible-playbook playbooks/setup-dependencies.yml

# 3. Run full workflow
ansible-playbook playbooks/provision-registry-vm.yml
ansible-playbook playbooks/download-to-tar.yml
ansible-playbook playbooks/push-tar-to-registry.yml
ansible-playbook playbooks/build-appliance.yml

# 4. Verify appliance boots on KVM
# 5. Verify identical workflow works with bare-metal inventory
```

## Directory Structure Changes

### Before (v4.20.0 with qubinode_navigator)

```
External Dependency:
/root/qubinode_navigator/         ← EXTERNAL DEPENDENCY
├── airflow/                      ← Airflow provided here
│   └── dags/
├── mcp-servers/                  ← MCP integration
└── setup.sh                      ← Installs dependencies

Repository:
/root/ocp4-disconnected-helper/
├── airflow/
│   └── dags/                     ← DAG definitions, calls playbooks
├── playbooks/                    ← Ansible automation
├── extra_vars/
├── inventory                     ← Includes qubinode hosts
└── README.md                     ← References qubinode setup
```

### After (v4.21.0 standalone)

```
Repository (Self-Contained):
/root/ocp4-disconnected-helper/
├── playbooks/
│   ├── setup-dependencies.yml    ✅ NEW (replaces qubinode setup)
│   ├── provision-registry-vm.yml ✅ UPDATED (uses community.libvirt)
│   ├── provision-aap-vm.yml      ✅ NEW (optional AAP deployment)
│   ├── download-to-tar.yml       (unchanged)
│   ├── push-tar-to-registry.yml  (unchanged)
│   └── build-appliance.yml       (unchanged)
├── aap/                          ✅ NEW (Job Templates, replaces Airflow)
│   ├── job-templates/
│   └── workflows/
├── extra_vars/                   (unchanged)
├── inventory                     ✅ UPDATED (remove qubinode hosts)
├── docs/
│   ├── PREREQUISITES.md          ✅ NEW
│   ├── MIGRATION-QUBINODE-TO-STANDALONE.md  ✅ NEW
│   └── adrs/
│       ├── 0001-two-tier-architecture.md     (marked SUPERSEDED)
│       ├── 0011-qubinode-navigator-integration.md (marked SUPERSEDED)
│       └── 0022-deprecate-qubinode-navigator.md  ✅ THIS ADR
└── README.md                     ✅ UPDATED (remove qubinode references)

NO EXTERNAL DEPENDENCIES
```

## Verification Criteria

✅ Repository is self-contained (no qubinode_navigator dependency)  
✅ `setup-dependencies.yml` successfully installs all prerequisites  
✅ Fresh CentOS Stream 10 system can run workflows without qubinode  
✅ `provision-registry-vm.yml` uses `community.libvirt` (not kcli)  
✅ README updated with standalone instructions  
✅ Migration guide (`MIGRATION-QUBINODE-TO-STANDALONE.md`) created  
✅ Prerequisites documented (`PREREQUISITES.md`)  
✅ ADRs 0001 and 0011 marked as SUPERSEDED  
✅ All qubinode references removed from code  
✅ Development (KVM) workflow tested without qubinode  
✅ Production (bare metal) workflow validated with forked inventory  
✅ Identical playbooks run on both KVM and bare metal  

## Timeline

- **Week 1**: Document prerequisites (`PREREQUISITES.md`)
- **Week 2**: Create `setup-dependencies.yml` playbook
- **Week 2**: Update README (remove qubinode references)
- **Week 3**: Create migration guide (`MIGRATION-QUBINODE-TO-STANDALONE.md`)
- **Week 3**: Mark ADRs 0001 and 0011 as SUPERSEDED
- **Week 4**: Remove qubinode references from all code
- **Weeks 5-6**: Testing (fresh installs, KVM, bare metal)

**Total Estimated Timeline: 6 weeks (~1.5 months)**

**⚠️ Note**: This timeline runs in parallel with ADR 0021 (Airflow → AAP) and ADR 0023 (kcli → community.libvirt).

## Cost Considerations

| Item | With qubinode_navigator | Without qubinode_navigator |
|------|-------------------------|---------------------------|
| **Setup time** | 2-3 hours (install qubinode + ocp4-helper) | 30 min (run setup-dependencies.yml) |
| **Maintenance** | Two repos to update | One repo |
| **Learning curve** | Learn qubinode + ocp4-helper | Learn ocp4-helper only |
| **Disk space** | ~10GB (qubinode + Airflow containers) | ~2GB (playbooks + AAP optional) |
| **Complexity** | High (two repos, Airflow, MCP) | Low (pure Ansible) |

**Benefit**: Significant reduction in complexity and onboarding time.

## Related ADRs

- **Supersedes:**
  - ADR 0001: Two-Tier Architecture
  - ADR 0011: qubinode_navigator Integration

- **Superseded By:** (none yet)

- **Related:**
  - ADR 0021: Deprecate Airflow and Adopt AAP
  - ADR 0023: Pure Ansible with community.libvirt Migration
  - ADR 0012: Airflow DAG Orchestration (superseded by ADR 0021)
  - ADR 0014: Airflow Replaces kcli-pipelines (superseded by ADR 0021)

## References

1. PRD v4.21.0 (2026-05-28), Section 3 - The "Develop to Production" Philosophy
2. PRD v4.21.0, Section 2 - Goals: "Migrate to Pure Ansible (Deprecate kcli and Qubinode)"
3. ADR 0001: Two-Tier Architecture (2025-11-25)
4. ADR 0011: qubinode_navigator Integration
