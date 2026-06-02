# ocp4-disconnected-helper v4.21.0 Release Plan

**Status**: 🔴 PLANNING  
**Target Release**: Q4 2026  
**Timeline**: 15-20 weeks  
**Last Updated**: 2026-06-02

---

## Executive Summary

### Strategic Context

Version 4.21.0 represents a **revolutionary architectural change** for ocp4-disconnected-helper, transitioning from a two-tier architecture with external dependencies (qubinode_navigator + Apache Airflow + kcli) to a **self-contained, enterprise-supported platform** based on Red Hat Ansible Automation Platform (AAP) and pure Ansible.

This migration addresses three critical strategic requirements:

1. **Enterprise Support**: Replace community Airflow with Red Hat-supported AAP 2.5
2. **Operational Simplicity**: Eliminate qubinode_navigator dependency (2-repo → 1-repo architecture)
3. **Development Parity**: Pure Ansible approach ensures identical playbooks between development and production

### Timeline & Budget

- **Duration**: 15-20 weeks (Q3-Q4 2026)
- **Critical Path**: AAP adoption (15 weeks)
- **Budget Impact**: **$5,000-15,000/year** (AAP subscription - NEW RECURRING COST)
- **Development Effort**: Platform Team, ~3.5-5 months full-time equivalent

### Breaking Changes Overview

This release introduces **BREAKING CHANGES** for all users:

| Component Removed | Replacement | User Action Required |
|------------------|-------------|---------------------|
| Apache Airflow orchestration | AAP 2.5 | Follow [MIGRATION-AIRFLOW-TO-AAP.md](docs/MIGRATION-AIRFLOW-TO-AAP.md) |
| qubinode_navigator | setup-dependencies.yml | Follow [MIGRATION-QUBINODE-TO-STANDALONE.md](docs/MIGRATION-QUBINODE-TO-STANDALONE.md) |
| kcli VM provisioning | community.libvirt | Update playbooks per [docs/libvirt-vm-provisioning.md](docs/libvirt-vm-provisioning.md) |
| MCP integration | N/A (removed) | No replacement (accept functionality loss) |

**⚠️ Users wishing to remain on the legacy architecture should stay on tag `v4.20.0-airflow`.**

---

## Migration Phases

### Phase 0: Preservation (Week 1) ✅ CRITICAL

**Objective**: Preserve current working state before any changes.

**Tasks**:
- Tag `v4.20.0-airflow` to preserve legacy Airflow architecture
- Create `archive/` directory structure for deprecated code
- **Obtain AAP subscription approval** (GO/NO-GO decision point)

**Deliverables**:
- Git tag: `v4.20.0-airflow`
- Directory: `archive/airflow-legacy/` (empty, ready for Phase 3 cleanup)
- Budget approval for $5k-15k/year AAP subscription

**Success Criteria**:
- [ ] Tag `v4.20.0-airflow` created and pushed to origin
- [ ] Archive directory structure exists
- [ ] AAP budget approved (BLOCKER - if denied, ABORT migration)

**Timeline**: Week 1 (1 week)

---

### Phase 1: Foundation - Pure Ansible Migration (Weeks 1-4) [ADR 0023]

**Objective**: Replace kcli VM provisioning with pure Ansible using `community.libvirt`.

**Key Work**:

#### Week 1: Template Creation
- Create `templates/libvirt/*.xml.j2` (Libvirt domain XML for registry, AAP, HAProxy, OCP nodes)
- Create `templates/cloud-init/*.yml.j2` (Cloud-init configs for all VM types)

#### Week 2: Core Playbook Rewrite
- Rewrite `playbooks/provision-registry-vm.yml` using `community.libvirt`
- Implement idempotency pattern (check VM exists → skip if present)
- Test cloud-init injection (SSH keys, network config, packages)

#### Week 3: Reusable Task Development
- Create `tasks/provision-vm-libvirt.yml` (reusable VM provisioning task)
- Extract common logic from registry VM playbook
- Parameterize VM specs (name, memory, CPUs, disk size)

#### Week 4: Additional VM Playbooks
- Create `playbooks/provision-haproxy-vm.yml` (using reusable task)
- Create `playbooks/provision-ocp-nodes-vms.yml` (loop over node list)
- Document approach in `docs/libvirt-vm-provisioning.md`

**Deliverables**:
- 4 libvirt domain templates (registry, AAP, HAProxy, OCP node)
- 12+ cloud-init templates (user-data, meta-data, network-config × 4 VM types)
- 1 reusable task file (`tasks/provision-vm-libvirt.yml`)
- 3 new playbooks (provision-haproxy-vm, provision-ocp-nodes-vms, rewritten provision-registry-vm)
- Documentation: `docs/libvirt-vm-provisioning.md`

**Success Criteria**:
- [ ] All VM provisioning playbooks use `community.libvirt` (no kcli CLI calls)
- [ ] Idempotency verified (run twice, second run skips VM creation)
- [ ] Cloud-init applies successfully (SSH access works with injected key)
- [ ] VMs boot and respond to SSH within 2 minutes

**Risks**:
- **Medium**: Cloud-init complexity (mitigation: use proven patterns from RHEL documentation)
- **Low**: Libvirt XML syntax errors (mitigation: validate with `xmllint`)

**Timeline**: Weeks 1-4 (4 weeks)

---

### Phase 2: Independence - Qubinode Removal (Weeks 3-8) [ADR 0022]

**Objective**: Eliminate qubinode_navigator dependency, make repository self-contained.

**Key Work**:

#### Weeks 3-4: Setup Infrastructure
- Create `playbooks/setup-dependencies.yml` (replaces qubinode setup)
- Install: ansible-core, libvirt, qemu-kvm, python3-libvirt, genisoimage
- Enable and start libvirtd service
- Install Ansible collections: community.libvirt, ansible.posix

#### Weeks 5-6: Documentation
- Create `docs/PREREQUISITES.md` (OS installation guide)
- Update `README.md` (remove all qubinode references)
- Create `docs/MIGRATION-QUBINODE-TO-STANDALONE.md`

#### Weeks 7-8: ADR Updates & Validation
- Mark ADRs 0001, 0011 as SUPERSEDED
- Test fresh RHEL 9.4 setup (30-minute target vs. old 2-3 hour setup)

**Deliverables**:
- `playbooks/setup-dependencies.yml` (replaces qubinode installer)
- `docs/PREREQUISITES.md` (comprehensive setup guide)
- Updated `README.md` (no qubinode references)
- `docs/MIGRATION-QUBINODE-TO-STANDALONE.md` (user migration guide)
- ADRs 0001, 0011 marked SUPERSEDED

**Success Criteria**:
- [ ] Fresh RHEL 9.4 VM setup completes in ≤30 minutes
- [ ] Zero qubinode references in active documentation (`grep -ri qubinode`)
- [ ] All dependencies installable via single playbook
- [ ] Libvirt operational and VM provisioning works

**Risks**:
- **Low**: Missed qubinode dependencies (mitigation: comprehensive grep audit)
- **Low**: RHEL subscription issues (mitigation: clear subscription instructions)

**Timeline**: Weeks 3-8 (6 weeks, parallel with Phases 1 & 3)

---

### Phase 3: Orchestration - AAP Adoption (Weeks 2-15) [ADR 0021] ⚠️ CRITICAL PATH

**Objective**: Replace Apache Airflow with Red Hat Ansible Automation Platform (AAP) 2.5.

**Key Work**:

#### Weeks 2-3: AAP VM Provisioning
- Create `playbooks/provision-aap-vm.yml` (4 vCPU, 16GB RAM, 60GB disk)
- Provision AAP VM on KVM using `community.libvirt` (depends on Phase 1)
- Configure RHEL 9.4 with subscription and base packages

#### Weeks 3-4: AAP Installation
- Create `playbooks/setup-aap-containerized.yml`
- Download AAP 2.5 installer from Red Hat portal
- Run containerized installer (Growth Topology)
- Verify AAP UI accessible at https://aap-controller

#### Week 5: Migration Tooling
- Create `scripts/migrate-dags-to-aap.py` (automated DAG parser)
- Parse all 8 Airflow DAG files
- Extract BashOperator tasks and dependencies
- Generate AAP Job Template YAML definitions

#### Weeks 6-7: Primary Workflow Conversion
- Manually refine `aap/workflows/ocp_initial_deployment.yml`
- Add AAP survey (ocp_version, registry_type, clean_mirror)
- Map all 8 task dependencies
- Configure error handling and retry logic
- Test in AAP UI

#### Weeks 8-11: Remaining DAG Conversions (7 DAGs)
- Convert `ocp_incremental_update.py` → AAP workflow
- Convert `ocp_registry_sync.py` → AAP job template
- Convert `ocp_harbor_registry.py` → AAP job template
- Convert `ocp_jfrog_agent_deployment.py` → AAP workflow
- Convert `ocp_disconnected_workflow.py` → AAP workflow
- Convert `ocp_pre_deployment_validation.py` → AAP job template
- Convert `dag_helpers.py` utility functions → AAP custom execution environment

#### Week 12: AAP Pre-load Automation
- Create `playbooks/aap-preload-job-templates.yml`
- Auto-import all job templates from YAML
- Auto-import all workflow templates
- Verify AAP UI shows all templates

#### Weeks 13-15: Parallel Testing & Validation ⚠️ GO/NO-GO
- Run Airflow DAG (v4.20.0-airflow) vs. AAP Workflow (v4.21.0) side-by-side
- Compare execution time (must be within 10%)
- Compare success/failure outcomes (must match)
- Benchmark resource usage (CPU, memory, disk I/O)
- **GO/NO-GO Decision**: If >10% regression OR failures → investigate and extend timeline

**Deliverables**:
- `playbooks/provision-aap-vm.yml` (AAP VM provisioning)
- `playbooks/setup-aap-containerized.yml` (AAP 2.5 installation)
- `scripts/migrate-dags-to-aap.py` (automated DAG converter)
- `aap/job-templates/*.yml` (8 job template definitions)
- `aap/workflows/*.yml` (5 workflow definitions)
- `playbooks/aap-preload-job-templates.yml` (auto-import)
- `docs/MIGRATION-AIRFLOW-TO-AAP.md` (user migration guide)
- `docs/aap-setup.md` (AAP installation & config guide)
- `archive/airflow-legacy/` (Airflow code moved for reference)

**Success Criteria**:
- [ ] AAP VM deployed on KVM (16GB RAM, 4 vCPU, 60GB disk)
- [ ] AAP 2.5 containerized installation successful
- [ ] All 8 Airflow DAGs converted to AAP Job Templates
- [ ] `ocp_initial_deployment` workflow executes successfully in AAP
- [ ] **Performance within 10% of Airflow baseline** (GO/NO-GO criterion)
- [ ] All workflows tested (no regressions)
- [ ] Airflow code archived in `archive/airflow-legacy/`

**Risks**:
- **HIGH**: DAG conversion introduces bugs (mitigation: parallel testing, phased rollout)
- **HIGH**: AAP subscription procurement delay (mitigation: start Week 1, maintain fallback)
- **MEDIUM**: Performance regression >10% (mitigation: optimize AAP configs, increase VM resources)

**Timeline**: Weeks 2-15 (15 weeks, **CRITICAL PATH**)

---

### Phase 4: Documentation & Finalization (Weeks 16-17)

**Objective**: Finalize all release documentation and create v4.21.0 release tag.

**Key Work**:

#### Week 16: Documentation Review
- Final review of `README.md` (no legacy references)
- Final review of `CHANGELOG.md` (all changes documented)
- Final review of all migration guides
- Update ADRs 0021, 0022, 0023 with actual release date

#### Week 17: Release Preparation
- Create `RELEASE_PLAN.md` (this document)
- Create `CHANGELOG.md` (Keep a Changelog format)
- Create `TODO.md` (development task tracker)
- Tag `v4.21.0` release
- Publish GitHub release with release notes

**Deliverables**:
- `RELEASE_PLAN.md` (executive summary, phases, risks, timeline)
- `CHANGELOG.md` (breaking changes, new features, migration guides)
- `TODO.md` (trackable task list for development)
- Git tag: `v4.21.0`
- GitHub release: v4.21.0

**Success Criteria**:
- [ ] All documentation reviewed and accurate
- [ ] No broken links in documentation
- [ ] Tag `v4.21.0` created and pushed
- [ ] GitHub release published with release notes

**Timeline**: Weeks 16-17 (2 weeks)

---

## Critical Path Analysis

### Longest Path (15 weeks)
**Phase 3: AAP Adoption** is the critical path.

```
Week 1: Preservation (Phase 0)
  ↓
Week 2-3: AAP VM Provisioning (Phase 3) ← depends on Phase 1 (libvirt migration)
  ↓
Week 3-4: AAP Installation (Phase 3)
  ↓
Week 5: Migration Tooling (Phase 3)
  ↓
Week 6-11: DAG Conversions (Phase 3) ← 6 weeks
  ↓
Week 12: AAP Pre-load (Phase 3)
  ↓
Week 13-15: Parallel Testing (Phase 3) ← GO/NO-GO decision
  ↓
Week 16-17: Documentation & Release (Phase 4)
```

**Total**: 17 weeks minimum (assuming no GO/NO-GO delays)

### Parallel Work Opportunities

**Weeks 1-4**: Phase 1 (libvirt) runs in parallel with early Phase 3 (AAP VM provisioning depends on libvirt completion by Week 3)

**Weeks 3-8**: Phase 2 (qubinode removal) runs fully in parallel with Phase 1 and Phase 3

**Optimization**: By parallelizing Phases 1, 2, and early Phase 3, total timeline stays at 15-17 weeks instead of 25+ weeks if sequential.

---

## Dependency Graph

```
Phase 0 (Week 1)
  │
  ├─> Phase 1 (Weeks 1-4: Libvirt migration)
  │     │
  │     └─> Phase 3.1 (Weeks 2-3: AAP VM provisioning) ← depends on libvirt templates
  │           │
  │           └─> Phase 3.2 (Weeks 3-4: AAP installation)
  │                 │
  │                 └─> Phase 3.3-3.7 (Weeks 5-15: DAG conversion & testing)
  │                       │
  │                       └─> Phase 4 (Weeks 16-17: Release)
  │
  └─> Phase 2 (Weeks 3-8: Qubinode removal) ← fully parallel, no blockers
        └─> Phase 4 (Weeks 16-17: Release)
```

**Key Dependencies**:
1. Phase 3.1 (AAP VM provisioning) **MUST WAIT** for Phase 1 to complete (needs libvirt templates)
2. All other work can run in parallel
3. Phase 4 (release) **MUST WAIT** for all phases to complete

---

## Risk Matrix

| Risk | Likelihood | Impact | Severity | Mitigation Strategy |
|------|-----------|--------|----------|---------------------|
| **AAP subscription approval delayed** | MEDIUM | HIGH | 🔴 **CRITICAL** | Start procurement Week 1. If denied by Week 2, ABORT migration and remain on v4.20.0-airflow. Maintain Tier 1 (shell/Ansible) as fallback. |
| **DAG conversion introduces bugs** | HIGH | HIGH | 🔴 **CRITICAL** | Run parallel testing (Airflow + AAP) for 3 weeks (Weeks 13-15). Phased rollout: test one workflow at a time. GO/NO-GO decision point at Week 15. |
| **Performance regression >10%** | MEDIUM | MEDIUM | 🟡 **HIGH** | Benchmark before/after. Optimize AAP configs (concurrency, forks). Increase AAP VM resources (6 vCPU, 24GB RAM). Accept up to 10% regression per ADR requirements. |
| **User adoption resistance** | MEDIUM | LOW | 🟢 **MEDIUM** | Clear migration guides with step-by-step instructions. Tag v4.20.0-airflow for legacy support. Communicate breaking changes prominently in CHANGELOG.md. |
| **Cloud-init complexity** | MEDIUM | MEDIUM | 🟡 **HIGH** | Use proven cloud-init patterns from RHEL documentation. Test on fresh RHEL 9.4 VM. Provide troubleshooting guide in docs/libvirt-vm-provisioning.md. |
| **Lost MCP integration** | LOW | LOW | 🟢 **LOW** | Acceptable trade-off per PRD requirements. Document in CHANGELOG.md. Future: explore AAP + MCP integration via custom execution environments. |
| **Timeline slip (critical path)** | MEDIUM | HIGH | 🟡 **HIGH** | Build 20% buffer (15-20 week range). Weekly progress reviews. Escalate blockers immediately. Consider extending Phase 3 DAG conversion to 8 weeks if needed. |

**Risk Severity Scale**:
- 🔴 **CRITICAL**: BLOCKER, could abort migration
- 🟡 **HIGH**: Major impact, requires immediate mitigation
- 🟢 **MEDIUM/LOW**: Manageable, monitor and mitigate

---

## Rollback Strategy

### Rollback Windows

#### Before Week 5 (Low Cost)
**Action**: Simple git revert to `v4.20.0-airflow` tag  
**Cost**: Wasted effort (Weeks 1-4), no production impact  
**Procedure**:
```bash
git checkout v4.20.0-airflow
git branch -D main  # if desired
```

#### Weeks 5-14 (Medium Cost)
**Action**: Maintain parallel Airflow/AAP execution  
**Cost**: Dual infrastructure overhead  
**Procedure**:
- Keep Airflow running for critical workflows
- Test AAP workflows on non-critical paths
- Gradual transition workflow-by-workflow

#### After Week 15 (High Cost)
**Action**: Airflow code archived but recoverable  
**Cost**: Significant rework, re-deployment of Airflow infrastructure  
**Procedure**:
```bash
# Restore Airflow code from archive
cp -r archive/airflow-legacy/airflow .

# Revert to v4.20.0-airflow
git checkout v4.20.0-airflow

# Re-deploy Airflow services
systemctl start airflow-webserver
systemctl start airflow-scheduler
```

**⚠️ After Public Release (v4.21.0 tag)**: Rollback only possible for individual users (not project-wide).

### Rollback Triggers

- **AAP subscription denied** (Week 1-2) → ABORT migration immediately
- **Critical DAG conversion bugs** (Week 6-11) → Extend timeline, add 2-4 weeks
- **Performance regression >20%** (Week 13-15) → Investigate root cause, optimize or extend timeline
- **GO/NO-GO failure** (Week 15) → ROLLBACK to v4.20.0-airflow, postpone v4.21.0

---

## Success Criteria

At v4.21.0 release, the following **MUST** be achieved (GO/NO-GO checklist):

### Technical Criteria
- [ ] **AAP VM deployed on KVM** (16GB RAM, 4 vCPU, 60GB disk)
- [ ] **AAP 2.5 containerized installation** successful
- [ ] **All 8 Airflow DAGs converted** to AAP Job Templates
- [ ] **Primary workflow (`ocp_initial_deployment`) executes successfully** in AAP
- [ ] **Performance within 10% of Airflow baseline** (critical GO/NO-GO)
- [ ] **Zero qubinode_navigator dependencies** (`grep -ri qubinode` returns nothing in active code)
- [ ] **Zero kcli dependencies** (all VM provisioning uses `community.libvirt`)
- [ ] **Airflow code archived** in `archive/airflow-legacy/`

### Documentation Criteria
- [ ] **README.md updated** (no qubinode/Airflow/kcli references)
- [ ] **All migration guides published** (Airflow→AAP, Qubinode→Standalone, kcli→libvirt)
- [ ] **CHANGELOG.md complete** (breaking changes, new features, migration paths)
- [ ] **ADRs 0021, 0022, 0023 finalized** with release date
- [ ] **Legacy ADRs marked SUPERSEDED** (0001, 0011, 0012, 0014, 0018)

### Business Criteria
- [ ] **AAP subscription active** (valid for ≥1 year)
- [ ] **Budget approval documented** ($5k-15k/year recurring cost)
- [ ] **Stakeholder sign-off** (product owner, platform team)

### Validation Criteria
- [ ] **Fresh RHEL 9.4 VM setup** completes in ≤30 minutes
- [ ] **All playbooks idempotent** (run twice, second run no changes)
- [ ] **Development → Production parity** maintained (identical playbooks, different inventory)

**If ANY criterion fails → NO-GO (extend timeline or rollback).**

---

## Go/No-Go Decision Points

### Decision Point 1: Week 1 (AAP Budget Approval) 🔴 BLOCKER

**Question**: Is AAP subscription approved ($5k-15k/year)?

**GO**: Proceed with full migration  
**NO-GO**: ABORT migration, remain on v4.20.0-airflow indefinitely

**Rationale**: Without AAP subscription, Phase 3 (critical path) cannot proceed. No point investing 4-15 weeks if core platform unavailable.

---

### Decision Point 2: Week 4 (Libvirt Migration Stability)

**Question**: Is libvirt-based VM provisioning stable and idempotent?

**GO**: Proceed to AAP VM provisioning (depends on libvirt templates)  
**NO-GO**: Extend Phase 1 by 1-2 weeks to fix issues

**Rationale**: AAP VM provisioning (Phase 3.1) depends on working libvirt templates. Flaky VM provisioning will cascade failures.

---

### Decision Point 3: Week 11 (DAG Conversion Progress)

**Question**: Are ≥50% of DAGs (4/8) converted successfully and tested?

**GO**: Proceed to final 4 DAGs and parallel testing  
**NO-GO**: Extend Phase 3 by 2-4 weeks, investigate conversion blockers

**Rationale**: If <50% conversion rate by Week 11, timeline is at risk. Early extension better than rushing and introducing bugs.

---

### Decision Point 4: Week 15 (Parallel Testing Results) 🔴 CRITICAL GO/NO-GO

**Question**: Are ALL workflows (8/8) performing within 10% of Airflow baseline with no regressions?

**GO**: Proceed to Phase 4 (documentation & release)  
**NO-GO**: ROLLBACK to v4.20.0-airflow, postpone v4.21.0 indefinitely

**Criteria**:
- ✅ All workflows execute successfully
- ✅ Performance within 10% (per-workflow comparison)
- ✅ No data loss or corruption
- ✅ Error handling works (retries, notifications)

**Rationale**: This is the final validation before committing to v4.21.0. Failures here indicate fundamental conversion issues. Better to rollback than ship broken release.

---

## Timeline Visualization (Gantt Chart)

```
Week  | Phase 0 | Phase 1 | Phase 2 | Phase 3         | Phase 4
------|---------|---------|---------|-----------------|--------
  1   | ████    | ████    |         |                 |        
      | Tag     | Tmplt   |         |                 |        
  2   |         | ████    |         | ████            |        
      |         | Plybk   |         | AAP VM          |        
  3   |         | ████    | ████    | ████            |        
      |         | Task    | Setup   | AAP Install     |        
  4   |         | ████    | ████    | ████            |        
      |         | AddVM   | Docs    | AAP Install     |        
  5   |         |         | ████    | ████            |        
      |         |         | README  | Migration Tool  |        
  6   |         |         | ████    | ████            |        
      |         |         | ADR     | Primary DAG     |        
  7   |         |         | ████    | ████            |        
      |         |         | Docs    | Primary DAG     |        
  8   |         |         | ████    | ████            |        
      |         |         | Test    | Remaining DAGs  |        
  9   |         |         |         | ████            |        
      |         |         |         | Remaining DAGs  |        
 10   |         |         |         | ████            |        
      |         |         |         | Remaining DAGs  |        
 11   |         |         |         | ████            |        
      |         |         |         | Remaining DAGs  |        
      |         |         |         | **GO/NO-GO #3** |        
 12   |         |         |         | ████            |        
      |         |         |         | AAP Pre-load    |        
 13   |         |         |         | ████            |        
      |         |         |         | Parallel Test   |        
 14   |         |         |         | ████            |        
      |         |         |         | Parallel Test   |        
 15   |         |         |         | ████            |        
      |         |         |         | **GO/NO-GO #4** |        
 16   |         |         |         |                 | ████   
      |         |         |         |                 | Docs   
 17   |         |         |         |                 | ████   
      |         |         |         |                 | Release
```

**Legend**:
- █ = Active work
- Tmplt = Template creation
- Plybk = Playbook rewrite
- Task = Reusable task
- AddVM = Additional VM playbooks
- Setup = setup-dependencies.yml
- AAP VM = AAP VM provisioning
- Primary DAG = ocp_initial_deployment conversion
- Remaining DAGs = 7 other DAG conversions
- **GO/NO-GO** = Decision point

**Note**: Weeks 1-8 show significant parallel work (Phases 1, 2, 3 overlap).

---

## Cost Considerations

### One-Time Costs (Development)

| Item | Effort | Cost (Estimated) | Notes |
|------|--------|-----------------|-------|
| Phase 1: Libvirt Migration | 4 weeks | Internal team | Platform team effort |
| Phase 2: Qubinode Removal | 6 weeks | Internal team | Parallel with Phase 1/3 |
| Phase 3: AAP Adoption | 15 weeks | Internal team | Critical path |
| Phase 4: Documentation | 2 weeks | Internal team | Finalization |
| **Total Development** | **15-20 weeks** | **~$50k-100k** (3 FTEs × 4 months @ $150k/year avg) | Opportunity cost |

### Recurring Costs (Operational)

| Item | Old (v4.20.0) | New (v4.21.0) | Δ |
|------|---------------|---------------|---|
| **Airflow** | $0 (Apache 2.0) | N/A (removed) | -$0 |
| **AAP Subscription** | N/A | **$5,000-15,000/year** | **+$5k-15k/year** 🔴 |
| **qubinode_navigator** | $0 (OSS) | N/A (removed) | -$0 |
| **kcli** | $0 (OSS) | N/A (removed) | -$0 |
| **community.libvirt** | N/A | $0 (OSS) | +$0 |
| **Infrastructure** | Self-managed VMs | Self-managed VMs | $0 |
| **Support** | Community forums | Red Hat Enterprise Support | +$0 (included in AAP sub) |

**Net Recurring Cost**: **+$5,000-15,000/year** (AAP subscription)

### Cost-Benefit Analysis

**Benefits** (Qualitative):
- ✅ Enterprise support (Red Hat SLA)
- ✅ Unified vendor (Ansible + AAP)
- ✅ Simpler setup (2-3 hours → 30 minutes)
- ✅ Single repository (reduced maintenance)
- ✅ Development → Production parity

**Costs**:
- ❌ $5k-15k/year (AAP subscription)
- ❌ 15-20 weeks development effort
- ❌ Lost MCP integration
- ❌ User migration burden

**ROI**: Break-even if enterprise support prevents **≥1 critical production incident/year** (typical incident cost: $10k-50k in downtime + remediation).

**⚠️ Budget Approval Required Before Proceeding.**

---

## Stakeholder Communication Plan

### Week 1: Kickoff Announcement

**Audience**: Product Owner, Platform Team, End Users  
**Message**:
- v4.21.0 migration starting (revolutionary architecture change)
- 15-20 week timeline (Q3-Q4 2026)
- AAP subscription cost: $5k-15k/year
- Breaking changes for all users
- Tag v4.20.0-airflow preserved for legacy support

**Channels**: Email, Slack, GitHub Discussions

---

### Weeks 2, 4, 6, 8, 11, 15: Progress Updates

**Audience**: Product Owner, Platform Team  
**Message**:
- Phase completion status (% complete)
- Risks and blockers
- GO/NO-GO decision outcomes
- Timeline adjustments (if any)

**Channels**: Weekly standup, Slack

---

### Week 15: Final GO/NO-GO Decision

**Audience**: Product Owner (decision maker)  
**Message**:
- Parallel testing results (Airflow vs. AAP performance)
- GO recommendation (if criteria met) or NO-GO recommendation (if not)
- Rollback plan if NO-GO
- Request explicit approval to proceed to Phase 4

**Channels**: Email, formal meeting

---

### Week 17: Release Announcement

**Audience**: All Users  
**Message**:
- v4.21.0 released
- Breaking changes summary
- Migration guides available
- Tag v4.20.0-airflow for legacy support
- AAP benefits (enterprise support, unified platform)

**Channels**: Email, Slack, GitHub Release Notes, README.md

---

## Appendices

### Appendix A: Related ADRs

- **ADR 0021**: Deprecate Airflow and Adopt AAP ([docs/adrs/0021-deprecate-airflow-adopt-aap.md](docs/adrs/0021-deprecate-airflow-adopt-aap.md))
- **ADR 0022**: Deprecate qubinode_navigator Dependency ([docs/adrs/0022-deprecate-qubinode-navigator.md](docs/adrs/0022-deprecate-qubinode-navigator.md))
- **ADR 0023**: Pure Ansible with community.libvirt Migration ([docs/adrs/0023-pure-ansible-community-libvirt.md](docs/adrs/0023-pure-ansible-community-libvirt.md))

### Appendix B: Migration Guides

- [MIGRATION-AIRFLOW-TO-AAP.md](docs/MIGRATION-AIRFLOW-TO-AAP.md) (for Airflow users)
- [MIGRATION-QUBINODE-TO-STANDALONE.md](docs/MIGRATION-QUBINODE-TO-STANDALONE.md) (for qubinode users)
- [libvirt-vm-provisioning.md](docs/libvirt-vm-provisioning.md) (libvirt approach)

### Appendix C: References

1. PRD v4.21.0 (2026-05-28) - Strategic requirements
2. Red Hat AAP 2.5 Documentation - Container topologies: https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.5/html/tested_deployment_models/container-topologies
3. Ansible community.libvirt Collection - https://docs.ansible.com/ansible/latest/collections/community/libvirt/

---

**Document Version**: 1.0  
**Last Updated**: 2026-06-02  
**Next Review**: Weekly during migration (Weeks 1-17)
