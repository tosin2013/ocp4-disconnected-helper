# AAP Workflow Implementation Guide

**Date**: 2026-06-10  
**ADR**: 0032 - AAP Workflow Orchestration for Infrastructure Lifecycle Management  
**Status**: Implementation in Progress

---

## Overview

This guide documents the implementation of AAP workflow orchestration for infrastructure lifecycle management, following ADR 0032. The workflow system provides automated deployment and teardown capabilities for all infrastructure components (except VyOS, DNS, and AAP itself).

---

## Workflow Architecture

### Included Components (Workflow-Managed)

✅ **Registry Infrastructure**
- Quay Mirror Registry
- Harbor Registry
- JFrog Artifactory

✅ **oc-mirror Operations** (Completed)
- Download to Disk (Phase 1)
- Push to Registry (Phase 2)
- Workspace Cleanup

✅ **Future Components** (Planned)
- OpenShift Cluster Nodes
- Storage VMs (NFS)
- Monitoring Stack (Prometheus, Grafana, Loki)
- Certificate Management Workflows
- Backup/Restore Operations

### Excluded Components (Manual Playbook Only)

❌ **VyOS Router** - Network foundation prerequisite (ADR 0025)  
❌ **DNS Services** - Foundational dependency  
❌ **AAP Deployment** - Bootstrap paradox  
❌ **Hypervisor Setup** - One-time IBM Cloud provisioning

---

## Implementation Status

### Phase 1: oc-mirror Workflows (✅ Completed - June 2026)

**Workflow ID 18**: Deploy Disconnected OpenShift Infrastructure
- Node 1: Download OpenShift Images to Disk (Phase 1)
- Node 2: Mirror OpenShift Images to Registry (Phase 2)

**Workflow ID 21**: Teardown oc-mirror Workspace
- Node 1: Teardown oc-mirror Workspace (dry-run, force, clean-all modes)

**Configuration Files**:
- `playbooks/aap-configuration/configure-complete-aap-setup.yml`
- `playbooks/aap-configuration/configure-teardown-workflow.yml`

---

### Phase 2: Registry VM Workflows (🔄 In Progress - June 2026)

**Configuration File**: `playbooks/aap-configuration/configure-registry-vm-workflows.yml`

**Job Templates Created**:
1. Check Registry VM Prerequisites
2. Provision Registry VM
3. Configure Registry Service
4. Verify Registry Health
5. Backup Registry Configuration
6. Remove Registry Service
7. Destroy Registry VM

**Deployment Workflow**: Deploy Registry Infrastructure
```
Node 1: Check Prerequisites
  ↓ (success)
Node 2: Provision VM
  ↓ (success)
Node 3: Configure Service
  ↓ (success)
Node 4: Verify Health
```

**Teardown Workflow**: Teardown Registry Infrastructure
```
Node 1: Backup Configuration
  ↓ (success)
Node 2: Remove Service
  ↓ (success)
Node 3: Destroy VM
```

**Supported Registry Types**:
- `registry_type: quay` - Quay mirror-registry v2
- `registry_type: harbor` - Harbor containerized
- `registry_type: jfrog` - JFrog Artifactory

---

## Workflow Design Principles

### 1. Atomic Job Templates
Each job template performs **one well-defined task**:
- ✅ **Good**: "Provision Registry VM" (single VM creation)
- ❌ **Bad**: "Deploy Complete Infrastructure" (too broad)

### 2. Two-Workflow Pattern
Every component has **two workflows**:
- **Deploy Workflow**: Provision → Configure → Verify
- **Teardown Workflow**: Backup → Remove → Destroy

### 3. Idempotent Operations
All workflows are **safe to re-run**:
- VM provisioning checks if VM exists before creating
- Configuration tasks use `state: present` (Ansible idempotency)
- Teardown checks if resources exist before removing

### 4. Safety Gates
Teardown workflows include **safety features**:
- **Dry-run mode**: `dry_run=true` (preview deletions)
- **Confirmation gates**: User approval before destructive operations
- **Force mode**: `force=true` (skip confirmations for automation)

### 5. Dependency Awareness
Workflows **check prerequisites** before execution:
- VyOS router accessible (`ping 192.168.122.2`)
- DNS resolution working (`nslookup registry.ocp4.sandbox3377.opentlc.com`)
- Storage paths exist (`test -d /data/libvirt-images`)

### 6. Shared Templates
**Reusable job templates** for common tasks:
- VM provisioning (used by all infrastructure components)
- Certificate setup (used by registry, AAP, monitoring)
- Health verification (standard pattern across services)

---

## Workflow Configuration Management

### Git Repository Structure
```
ocp4-disconnected-helper/
├── playbooks/
│   ├── aap-configuration/
│   │   ├── configure-complete-aap-setup.yml        # ✅ Completed
│   │   ├── configure-teardown-workflow.yml         # ✅ Completed
│   │   ├── configure-registry-vm-workflows.yml     # 🔄 New
│   │   ├── configure-storage-workflows.yml         # 📋 Planned
│   │   └── configure-cluster-workflows.yml         # 📋 Planned
│   │
│   ├── check-registry-prerequisites.yml            # 📋 To Create
│   ├── provision-registry-vm.yml                   # 📋 To Create
│   ├── configure-registry-service.yml              # 📋 To Create
│   ├── verify-registry-health.yml                  # 📋 To Create
│   ├── backup-registry-config.yml                  # 📋 To Create
│   ├── remove-registry-service.yml                 # 📋 To Create
│   └── destroy-registry-vm.yml                     # 📋 To Create
│
└── docs/
    ├── adrs/
    │   └── adr-0032-aap-workflow-orchestration-strategy.md  # ✅ Completed
    └── AAP_WORKFLOW_IMPLEMENTATION_GUIDE.md                 # ✅ This document
```

### Version Control Rules
1. **Playbooks are authoritative**: Workflows call playbooks (never inline tasks)
2. **Workflow configs in Git**: All `playbooks/aap-configuration/*.yml` committed
3. **No secrets in workflows**: Use Ansible Vault credentials or AAP credential objects
4. **Atomic commits**: One workflow configuration per commit

---

## Implementation Workflow

### Step 1: Create Underlying Playbooks
Before configuring AAP workflows, create the playbooks they will call:

```bash
# Example: Create prerequisite check playbook
ansible-playbook playbooks/check-registry-prerequisites.yml --syntax-check

# Example: Create VM provisioning playbook
ansible-playbook playbooks/provision-registry-vm.yml --syntax-check
```

### Step 2: Configure AAP Workflows
Run the workflow configuration playbook to create AAP resources:

```bash
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/aap-configuration/configure-registry-vm-workflows.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

**Output**:
- 7 Job Templates created
- 2 Workflow Templates created (Deploy + Teardown)
- Workflow nodes linked (sequential execution)

### Step 3: Test Workflows
Launch workflows via AAP Web UI or CLI:

**Deploy Registry VM (Dry-Run Test)**:
```bash
# Launch workflow with variables
curl -u admin:$AAP_PASSWORD \
  -X POST https://aap.sandbox3377.opentlc.com/api/v2/workflow_job_templates/[ID]/launch/ \
  -H "Content-Type: application/json" \
  -d '{"extra_vars": {"registry_type": "quay", "dry_run": true}}'
```

**Production Deployment**:
1. Navigate to AAP Web UI: https://aap.sandbox3377.opentlc.com
2. Templates → Workflow Templates → Deploy Registry Infrastructure
3. Click "Launch"
4. Set variables:
   - `registry_type`: quay
   - `vm_memory`: 16384
   - `vm_cpus`: 4
5. Monitor execution in real-time

### Step 4: Verify Workflow Success
Check each workflow node completed successfully:
- ✅ Green checkmarks on all nodes
- ✅ No failed tasks in job logs
- ✅ Final verification step passed

### Step 5: Document Workflow
Update this guide with:
- Workflow ID
- Execution time (baseline for future runs)
- Any lessons learned or gotchas

---

## Troubleshooting

### Workflow Node Failures

**Symptom**: Workflow node shows red X (failed)

**Diagnosis**:
1. Click failed node in AAP Web UI
2. View job output log
3. Identify failed task (red "fatal:" line)

**Common Failures**:

**Prerequisite check failed**:
- **Cause**: VyOS router not accessible
- **Fix**: Verify VyOS running: `virsh list | grep vyos`
- **Fix**: Check routes: `ip route | grep 192.168`

**VM provisioning failed**:
- **Cause**: Insufficient hypervisor resources
- **Fix**: Check available RAM: `free -g`
- **Fix**: Check disk space: `df -h /data`

**Service configuration failed**:
- **Cause**: Package installation timeout
- **Fix**: Check internet connectivity from VM
- **Fix**: Verify VM can reach package repositories

**Health verification failed**:
- **Cause**: Service not fully started yet
- **Fix**: Add longer wait time in playbook
- **Fix**: Check service status: `systemctl status quay-pod`

### Workflow Execution Stuck

**Symptom**: Workflow running for >60 minutes with no progress

**Diagnosis**:
1. Check AAP Controller resources: `top` (CPU/memory usage)
2. Check for hung async jobs: `ps aux | grep ansible`

**Fix**:
- Cancel workflow execution in AAP Web UI
- Check Controller logs: `journalctl -u automation-controller -f`
- Restart Controller if needed: `systemctl restart automation-controller`

---

## Best Practices

### Workflow Design
1. ✅ **Keep workflows shallow**: Maximum 3 levels deep (avoid complex nesting)
2. ✅ **Use success/failure nodes**: Don't rely on `always` nodes (explicit flow)
3. ✅ **Add approval gates**: For production deployments, require manual approval
4. ✅ **Enable notifications**: Slack/email on workflow completion

### Job Template Configuration
1. ✅ **Limit concurrent jobs**: Set `forks: 5` in playbooks (prevent Controller overload)
2. ✅ **Set timeouts**: Add `timeout: 3600` for long-running operations
3. ✅ **Ask variables on launch**: Make workflows flexible (don't hardcode values)
4. ✅ **Use execution environments**: Ensure consistent tooling (oc-mirror, kubectl)

### Workflow Maintenance
1. ✅ **Regular audits**: Monthly review of workflow definitions vs playbooks
2. ✅ **Version playbooks**: Tag playbook releases matching workflow updates
3. ✅ **Monitor Controller**: Track CPU/memory usage trends (prevent resource exhaustion)
4. ✅ **Retention policy**: Keep workflow job logs for 90 days (compliance requirement)

---

## Next Steps

### Phase 2 Completion (June 2026)
- [ ] Create underlying playbooks for Registry VM workflows
- [ ] Test Quay registry deployment via workflow
- [ ] Test Harbor registry deployment via workflow
- [ ] Test JFrog registry deployment via workflow
- [ ] Document workflow execution times (baseline metrics)

### Phase 3: Storage Workflows (Q3 2026)
- [ ] Create `configure-storage-workflows.yml` playbook
- [ ] Implement NFS VM provisioning workflow
- [ ] Implement backup/restore workflow
- [ ] Test storage workflow end-to-end

### Phase 4: OpenShift Cluster Workflows (Q4 2026)
- [ ] Create `configure-cluster-workflows.yml` playbook (cluster provisioning)
- [ ] Implement cluster node provisioning workflow
- [ ] Implement cluster installation workflow
- [x] **Implement cluster upgrade workflow** ✅ (2026-06-10)
  - Created `configure-cluster-upgrade-workflow.yml`
  - 7 job templates: prerequisites, mirror, backup, ICSP, upgrade, verify, rollback
  - Full workflow with approval gates and failure handling
  - See **ADR 0006** for detailed upgrade strategy

---

## References

- **ADR 0032**: AAP Workflow Orchestration for Infrastructure Lifecycle Management
- **ADR 0021**: Deprecate Airflow and Adopt AAP 2.5
- **ADR 0024**: Roles and Collections Architecture
- **ADR 0025**: VyOS Router as Network Infrastructure Prerequisite
- **ADR 0029**: Custom Execution Environment with oc-mirror

**AAP Documentation**:
- [Workflow Best Practices](https://docs.ansible.com/automation-controller/latest/html/userguide/workflows.html)
- [Job Templates](https://docs.ansible.com/automation-controller/latest/html/userguide/job_templates.html)
- [Execution Environments](https://docs.ansible.com/automation-controller/latest/html/userguide/execution_environments.html)

**Workflow URLs**:
- Deploy oc-mirror: https://aap.sandbox3377.opentlc.com/#/templates/workflow_job_template/18
- Teardown oc-mirror: https://aap.sandbox3377.opentlc.com/#/templates/workflow_job_template/21
- Deploy Registry: (To be created)
- Teardown Registry: (To be created)

---

**Last Updated**: 2026-06-10  
**Maintainer**: Tosin Akinosho  
**Status**: Living Document (update as implementation progresses)
