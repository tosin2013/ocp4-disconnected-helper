# ADR 0033: AAP Workflow Validation and Health Check Framework

## Date
2026-06-10

## Status
Accepted → **Validated in Production (v1.2)**

**Production Validation**: 2026-06-11 (Release v1.2)  
**Validation Framework Components Deployed**:
- Shell health check scripts: `validate-aap-health.sh`, `validate-aap-workflow-templates.sh`
- E2E test playbooks: `test-registry-vm-workflow.yml`, `test-oc-mirror-workflow.yml`
- GitHub Actions workflow: `validate-aap-workflows.yml`
- Testing documentation: `docs/TESTING.md`

## Context

ADR 0032 established AAP workflow orchestration as the standard pattern for infrastructure lifecycle management. We have successfully implemented:
- Registry VM deployment workflows (7 job templates, 2 workflows)
- oc-mirror operation workflows (download-to-disk, push-to-registry, teardown)
- Cluster upgrade workflows (8-node workflow with approval gates)

However, **we have no automated way to validate that these workflows function correctly** before production use.

### Current Validation Limitations

**Manual Validation Only:**
- Workflows tested by launching them in AAP UI and watching execution
- Success determined by visual inspection of job output
- No programmatic health checks for AAP Controller or multi-node cluster
- No automated verification of ADR compliance (especially ADR 0031 - Control Plane EE registry auth)

**Existing Validation Infrastructure (Insufficient for AAP Workflows):**
- ✅ Preflight scripts: `preflight-cert-check.sh`, `preflight-aap-registry-check.sh`
  - Purpose: Pre-deployment validation (before AAP or registry setup)
  - Limitation: Do not validate AAP Controller health or workflow execution
  
- ✅ Validation playbooks: `validate-aap-passwords.yml`, `validate-passthrough-mode.yml`
  - Purpose: Configuration validation (password structure, registry modes)
  - Limitation: Do not test end-to-end workflow orchestration

- ✅ Health check playbooks: `verify-registry-health.yml`, `verify-cluster-upgrade.yml`
  - Purpose: Component-level health verification
  - Limitation: Run as workflow nodes, not independent validators

**ADR Compliance Gaps:**
- **ADR 0031** (AAP Installer Registry Credentials): No automated verification that Control Plane EE can pull images from `registry.redhat.io` after deployment
- **ADR 0028** (Multi-Node Password Architecture): No validation that Gateway password works for Web UI and Controller password works for API
- **ADR 0032** (Workflow Orchestration): No automated testing of two-workflow pattern (deploy + teardown)

### AAP 2.6 Multi-Node Architecture Complexity

AAP 2.6 introduces architectural complexity requiring programmatic validation:

**Multi-Component System:**
- Automation Gateway (Web UI authentication)
- Automation Controller (API authentication, job execution)
- PostgreSQL Database (metadata persistence)
- Control Plane Execution Environment (project sync, SCM operations)

**Failure Modes Requiring Validation:**
1. **Control Plane EE Registry Authentication Failure** (ADR 0031):
   - Symptom: Project sync fails with "unable to retrieve auth token: unauthorized"
   - Root Cause: Registry credentials not in AAP installer inventory before `setup.sh`
   - Current Detection: Manual project sync attempt in UI
   - **Gap**: No automated post-deployment verification

2. **Web UI Login Failure Despite Correct Password** (ADR 0028):
   - Symptom: "Invalid username or password" when using `admin_password` for Web UI
   - Root Cause: Web UI requires `automationgateway_admin_password`, not `admin_password`
   - Current Detection: Manual login attempt
   - **Gap**: No automated dual-password validation

3. **Workflow Node Execution Order Failure**:
   - Symptom: Teardown workflow blocks on interactive prompt (fixed in commit 68990bc)
   - Root Cause: Workflow extra_vars had `force: false` instead of `force: true`
   - Current Detection: Manual workflow launch and monitoring
   - **Gap**: No automated workflow execution test

### Research: AWX INSTALL.md Not Suitable

**Investigation Result**: AWX upstream `INSTALL.md` does NOT contain validation procedures applicable to AAP workflows.
- ❌ No post-installation health checks documented
- ❌ No workflow testing procedures
- ❌ No API validation endpoints
- ✅ Only covers installation methods (Operator, Docker, CLI)

**AWX API Documentation** (`/api/v2/`) provides relevant health endpoints:
- `/api/v2/ping/` - Controller availability check
- `/api/v2/instances/` - Instance health, capacity, errors
- `/api/v2/job_templates/` - Job template availability
- `/api/v2/workflow_job_templates/` - Workflow template configuration
- `/api/v2/project_updates/` - Project sync status (critical for ADR 0031 validation)

**Red Hat AAP Health Check Documentation** (Article #7113839):
- ⚠️ Subscriber-exclusive content (requires Red Hat subscription)
- Would provide official AAP 2.x health validation procedures
- Not accessible for design reference without subscription

### Industry Patterns for Workflow Validation

**Ansible Molecule Pattern**: Test roles in isolated environments
- Pros: Structured testing with verify stage
- Cons: Designed for role testing, not workflow orchestration

**AWX/Tower Job Launch Pattern**: Programmatic job execution via API
- Pros: Matches production usage (API-driven)
- Cons: Requires Python `awxkit` SDK or `curl` scripting

**Shell Script Health Check Pattern**: Lightweight validation scripts
- Pros: Fast, portable, no additional dependencies
- Cons: Limited error handling, no structured output

**Hybrid Pattern** (Recommended): Layered validation approach
- Layer 1: Shell scripts for quick health checks (AAP availability, API ping)
- Layer 2: Ansible playbooks for comprehensive workflow validation (E2E execution)

## Decision

**Adopt a hybrid validation framework** combining shell scripts for health checks and Ansible playbooks for end-to-end workflow validation.

### Framework Architecture

```
Validation Framework (Hybrid)
│
├─ Layer 1: Health Checks (Shell Scripts)
│  ├─ scripts/validate-aap-health.sh
│  │  ├─ Check AAP Controller API availability (/api/v2/ping/)
│  │  ├─ Verify instance health and capacity (/api/v2/instances/)
│  │  ├─ Validate dual password authentication (Gateway + Controller)
│  │  └─ Check Control Plane EE registry auth (project sync success)
│  │
│  └─ scripts/validate-aap-workflow-templates.sh
│     ├─ Verify all workflow templates exist
│     ├─ Check workflow node connectivity
│     └─ Validate job template availability
│
└─ Layer 2: E2E Workflow Validation (Ansible Playbooks)
   ├─ playbooks/test-registry-vm-workflow.yml
   │  ├─ Launch "Deploy Registry Infrastructure" workflow
   │  ├─ Wait for completion with timeout
   │  ├─ Verify registry VM created and healthy
   │  ├─ Launch "Teardown Registry Infrastructure" workflow
   │  ├─ Verify VM destroyed and storage cleaned
   │  └─ Assert idempotent re-run (no errors on second deploy)
   │
   ├─ playbooks/test-oc-mirror-workflow.yml
   │  ├─ Launch "Deploy Disconnected OpenShift Infrastructure" workflow
   │  ├─ Verify Phase 1 (download-to-disk) artifacts created
   │  ├─ Verify Phase 2 (push-to-registry) images mirrored
   │  ├─ Launch "Teardown oc-mirror Workspace" workflow
   │  └─ Verify workspace cleaned (idempotent teardown)
   │
   └─ playbooks/test-cluster-upgrade-workflow.yml (Future)
      ├─ Launch "Upgrade OpenShift Cluster" workflow
      ├─ Verify prerequisite checks passed
      ├─ Test approval gate behavior (manual intervention)
      └─ Verify failure path triggers on prerequisite failure
```

### Validation Scope

**Shell Scripts (Layer 1):**
1. **AAP Controller Health**: API availability, instance capacity, database connectivity
2. **Authentication Validation**: Dual password architecture (Gateway vs Controller - ADR 0028)
3. **Project Sync Status**: Control Plane EE registry authentication (ADR 0031)
4. **Workflow Template Availability**: All configured workflows present and valid

**Ansible Playbooks (Layer 2):**
1. **Registry VM Workflow**: Full deploy → verify → teardown cycle
2. **oc-mirror Workflow**: Multi-phase execution with artifact validation
3. **Cluster Upgrade Workflow**: Approval gate behavior and failure paths (future)
4. **Idempotency Testing**: Re-run workflows without errors
5. **Force Mode Testing**: Validate `force: true` skips interactive prompts (commit 68990bc fix)

### Success Criteria

**Layer 1 (Shell Scripts) - Exit Code Based:**
- Exit 0: All health checks passed
- Exit 1: Health check failure (with specific error message)
- Exit 2: Configuration error (AAP not reachable, credentials missing)

**Layer 2 (Ansible Playbooks) - Assertion Based:**
- All tasks pass (no `failed=1` in PLAY RECAP)
- Workflow job status: `successful` (not `failed`, `canceled`, `error`)
- Artifacts created/destroyed as expected (VMs, TAR files, registry images)
- Idempotent re-run: no changes on second execution

### Integration with Existing Tooling

**Preflight Scripts** (Pre-Deployment Validation):
```bash
# Before AAP deployment
./scripts/preflight-aap-registry-check.sh  # Validate registry credentials exist
./scripts/preflight-cert-check.sh          # Validate certificates ready

# Deploy AAP
ansible-playbook playbooks/deploy-aap-multi-node.yml

# After AAP deployment (NEW)
./scripts/validate-aap-health.sh           # Validate AAP Controller healthy
./scripts/validate-aap-workflow-templates.sh  # Validate workflows configured
```

**Workflow Configuration Playbooks** (AAP Setup):
```bash
# Configure workflows
ansible-playbook playbooks/aap-configuration/configure-registry-vm-workflows.yml

# Test workflows (NEW)
ansible-playbook playbooks/test-registry-vm-workflow.yml
```

**CI/CD Integration** (GitHub Actions - ADR 0008):
```yaml
# .github/workflows/validate-aap-workflows.yml
- name: Deploy AAP (Test Environment)
  run: ansible-playbook playbooks/deploy-aap-multi-node.yml
  
- name: Validate AAP Health
  run: ./scripts/validate-aap-health.sh
  
- name: Test Registry VM Workflow
  run: ansible-playbook playbooks/test-registry-vm-workflow.yml
  
- name: Test oc-mirror Workflow
  run: ansible-playbook playbooks/test-oc-mirror-workflow.yml
```

## Consequences

### Positive

1. **ADR Compliance Verification**:
   - ✅ ADR 0031: Automated validation that Control Plane EE has registry authentication
   - ✅ ADR 0028: Automated dual password authentication testing
   - ✅ ADR 0032: End-to-end workflow orchestration validation

2. **Early Failure Detection**:
   - Catch workflow configuration errors before production use
   - Detect AAP multi-node cluster issues immediately after deployment
   - Verify `force: true` fix (commit 68990bc) prevents interactive prompt blocking

3. **Regression Prevention**:
   - Automated tests prevent re-introduction of fixed issues
   - CI/CD integration catches breaking changes before merge
   - Idempotency tests ensure workflows safe to re-run

4. **Documentation as Code**:
   - Test scripts serve as executable documentation
   - Success criteria encoded in assertions
   - Examples for troubleshooting production issues

5. **Faster Onboarding**:
   - New team members can validate environment with `./scripts/validate-aap-health.sh`
   - Clear pass/fail signals reduce debugging time
   - E2E tests demonstrate correct workflow usage

### Negative

1. **Dual Maintenance Burden**:
   - Shell scripts AND Ansible playbooks require updates when workflows change
   - Two different testing patterns to document and maintain
   - Mitigation: Keep shell scripts minimal (health only), comprehensive logic in Ansible

2. **Test Environment Requirement**:
   - E2E workflow tests require functional AAP instance
   - Cannot run in CI/CD without AAP deployment step
   - Mitigation: Use ephemeral AAP deployments in CI/CD, teardown after tests

3. **Execution Time**:
   - Full E2E workflow tests may take 10-30 minutes (VM provisioning, registry setup)
   - Slower feedback loop compared to unit tests
   - Mitigation: Layer 1 health checks run in <1 minute, use as smoke tests

4. **API Versioning Risk**:
   - AWX/AAP API may change between versions
   - Shell scripts using `/api/v2/` may break on AAP upgrades
   - Mitigation: Version-pin API endpoints, test against multiple AAP versions

5. **Credential Management**:
   - Test scripts need AAP admin credentials
   - Security risk if credentials hardcoded or leaked
   - Mitigation: Use Ansible Vault, environment variables, or CI/CD secrets

### ADR Relationship Matrix

| ADR | Relationship | Impact |
|-----|--------------|--------|
| ADR 0031 | **Validates** | Test scripts verify Control Plane EE registry authentication |
| ADR 0028 | **Validates** | Health checks test dual password architecture (Gateway vs Controller) |
| ADR 0032 | **Validates** | E2E playbooks test two-workflow pattern (deploy + teardown) |
| ADR 0008 | **Integrates** | CI/CD pipeline runs validation scripts on every deployment |
| ADR 0021 | **Supports** | Validates AAP adoption is operationally successful |
| ADR 0024 | **Uses** | Test playbooks follow atomic roles architecture |

## Implementation Plan

### Phase 1: Layer 1 Health Checks (Week of June 10, 2026)

**Deliverables:**
1. `scripts/validate-aap-health.sh` - AAP Controller health validation
   - API ping check (`/api/v2/ping/`)
   - Instance health check (`/api/v2/instances/`)
   - Dual password authentication (Gateway + Controller)
   - Control Plane EE registry auth (project sync status)

2. `scripts/validate-aap-workflow-templates.sh` - Workflow template validation
   - Check workflow templates exist
   - Verify node connectivity
   - Validate job template references

**Success Criteria:**
- Scripts exit 0 on healthy AAP instance
- Scripts exit non-zero with clear error messages on failure
- Can run independently (no Ansible runtime required)

### Phase 2: Layer 2 E2E Workflow Tests (Week of June 17, 2026)

**Deliverables:**
1. `playbooks/test-registry-vm-workflow.yml` - Registry VM lifecycle test
   - Launch deploy workflow via `ansible.controller.workflow_launch`
   - Wait for completion with 30-minute timeout
   - Verify VM created (`virsh list`)
   - Verify registry healthy (`curl /health/instance`)
   - Launch teardown workflow
   - Verify VM destroyed and storage cleaned

2. `playbooks/test-oc-mirror-workflow.yml` - oc-mirror operation test
   - Launch deploy workflow (download + push phases)
   - Verify TAR archives created (`/data/ocp-mirror/*.tar`)
   - Verify images pushed to registry (`oc-mirror list`)
   - Launch teardown workflow
   - Verify workspace cleaned (`/data/ocp-mirror/oc-mirror-workspace` removed)

**Success Criteria:**
- All tasks pass (PLAY RECAP shows `failed=0`)
- Workflows complete with `successful` status
- Artifacts created/destroyed as expected
- Idempotent re-run possible (second deploy succeeds)

### Phase 3: CI/CD Integration (Week of June 24, 2026)

**Deliverables:**
1. GitHub Actions workflow: `.github/workflows/validate-aap-workflows.yml`
   - Deploy ephemeral AAP instance
   - Run Layer 1 health checks
   - Run Layer 2 E2E workflow tests
   - Teardown AAP instance

2. Documentation: `docs/TESTING.md`
   - How to run validation scripts locally
   - CI/CD integration guide
   - Troubleshooting failed tests

**Success Criteria:**
- CI/CD pipeline passes on every commit to `main`
- Failed tests block PR merge
- Clear failure messages guide debugging

### Phase 4: Cluster Upgrade Workflow Testing (Q3 2026)

**Deliverables:**
1. `playbooks/test-cluster-upgrade-workflow.yml`
   - Test prerequisite checks (node health, etcd quorum)
   - Verify approval gate behavior
   - Test failure path triggers (degraded operators)

**Success Criteria:**
- Approval gate blocks execution until manual approval
- Failure paths trigger correctly on prerequisite failures
- Rollback alerts generated on upgrade failure

## Alternatives Considered

### Alternative 1: Shell Scripts Only
**Approach**: All validation via shell scripts (curl + jq for API calls)

**Pros**:
- Fast execution (<1 minute for all checks)
- No Ansible runtime dependency
- Portable to any environment with bash/curl/jq

**Cons**:
- Complex workflow orchestration difficult to script in bash
- No structured error handling or assertions
- Difficult to maintain for multi-step E2E tests

**Rejection Reason**: Cannot adequately validate complex workflow orchestration patterns.

### Alternative 2: Ansible Playbooks Only
**Approach**: All validation via Ansible playbooks (no shell scripts)

**Pros**:
- Single testing framework (Ansible expertise already present)
- Structured YAML with clear assertions
- Reusable roles and modules

**Cons**:
- Slower execution (Ansible overhead for simple health checks)
- Requires Ansible runtime (not portable to minimal environments)
- Overkill for simple API ping checks

**Rejection Reason**: Too heavy for quick health checks, defeats purpose of fast smoke tests.

### Alternative 3: Python Testing Framework (pytest + awxkit)
**Approach**: Write pytest test suite using AWX SDK (`awxkit`)

**Pros**:
- Robust error handling and structured assertions
- AWX SDK provides native Python API client
- Extensible framework for future test scenarios

**Cons**:
- Additional dependency (`pip install awxkit pytest`)
- Python expertise required (team is Ansible-focused)
- SDK may lag behind AAP API changes

**Rejection Reason**: Introduces new tooling when existing tools (bash + Ansible) sufficient.

### Alternative 4: Manual Testing Only (No Automation)
**Approach**: Continue manual workflow launch and visual inspection

**Pros**:
- No development effort required
- Flexibility to adapt to changing requirements

**Cons**:
- Human error prone (miss failures, inconsistent testing)
- Time-consuming (10+ minutes per workflow)
- No regression prevention (fixed issues may reappear)
- Cannot integrate into CI/CD pipeline

**Rejection Reason**: Does not scale, no repeatability, blocks ADR compliance verification.

## References

- ADR 0032: AAP Workflow Orchestration for Infrastructure Lifecycle Management
- ADR 0031: AAP Installer Registry Credential Configuration
- ADR 0028: AAP 2.6 Multi-Node Password Architecture
- ADR 0021: Deprecate Airflow and Adopt AAP
- ADR 0008: GitHub Actions Automation
- [AWX API Reference](https://docs.ansible.com/projects/awx/en/latest/rest_api/api_ref.html)
- [Red Hat AAP Health Check (Subscriber Content)](https://access.redhat.com/solutions/7113839)
- [AWX Health Check Issue #12954](https://github.com/ansible/awx/issues/12954)
- Commit 68990bc: Fix force=true by default in AAP workflows to avoid interactive prompts

## Appendix: Example Validation Script Structure

### Shell Script Health Check Example

```bash
#!/bin/bash
# scripts/validate-aap-health.sh
set -euo pipefail

AAP_HOST="${AAP_HOST:-https://aap.sandbox3377.opentlc.com}"
AAP_USERNAME="${AAP_USERNAME:-admin}"
AAP_PASSWORD="${AAP_PASSWORD}"  # From environment or Ansible Vault

echo "=== AAP Health Validation ==="

# Check 1: Controller API Availability
echo "Checking AAP Controller API..."
if curl -sk -u "$AAP_USERNAME:$AAP_PASSWORD" "$AAP_HOST/api/v2/ping/" | jq -e '.ha == true' > /dev/null; then
  echo "✓ Controller API healthy"
else
  echo "✗ Controller API unavailable"
  exit 1
fi

# Check 2: Instance Health
echo "Checking AAP instance health..."
CAPACITY=$(curl -sk -u "$AAP_USERNAME:$AAP_PASSWORD" "$AAP_HOST/api/v2/instances/" | jq '.results[0].capacity')
if [[ "$CAPACITY" -gt 0 ]]; then
  echo "✓ Instance capacity available: $CAPACITY"
else
  echo "✗ Instance capacity zero (errors present)"
  exit 1
fi

# Check 3: Control Plane EE Registry Auth (ADR 0031)
echo "Checking Control Plane EE registry authentication..."
SYNC_STATUS=$(curl -sk -u "$AAP_USERNAME:$AAP_PASSWORD" "$AAP_HOST/api/controller/v2/project_updates/?order_by=-id" | jq -r '.results[0].status')
if [[ "$SYNC_STATUS" == "successful" ]]; then
  echo "✓ Project sync successful (Control Plane EE authenticated)"
else
  echo "✗ Project sync failed: $SYNC_STATUS (check ADR 0031 compliance)"
  exit 1
fi

echo "=== All health checks passed ==="
exit 0
```

### Ansible E2E Workflow Test Example

```yaml
---
# playbooks/test-registry-vm-workflow.yml
- name: Test Registry VM Workflow (E2E)
  hosts: localhost
  gather_facts: false
  vars:
    aap_host: "https://aap.sandbox3377.opentlc.com"
    aap_username: "admin"
    workflow_timeout: 1800  # 30 minutes

  tasks:
    # Launch Deploy Workflow
    - name: Launch "Deploy Registry Infrastructure" workflow
      ansible.controller.workflow_launch:
        controller_host: "{{ aap_host }}"
        controller_username: "{{ aap_username }}"
        controller_password: "{{ admin_password }}"
        validate_certs: false
        workflow: "Deploy Registry Infrastructure"
        extra_vars:
          registry_type: quay
      register: deploy_job

    # Wait for Completion
    - name: Wait for deploy workflow to complete
      ansible.controller.workflow_job_wait:
        controller_host: "{{ aap_host }}"
        controller_username: "{{ aap_username }}"
        controller_password: "{{ admin_password }}"
        validate_certs: false
        job_id: "{{ deploy_job.id }}"
        timeout: "{{ workflow_timeout }}"
      register: deploy_result

    # Verify Success
    - name: Verify deploy workflow succeeded
      ansible.builtin.assert:
        that:
          - deploy_result.status == "successful"
        fail_msg: "Deploy workflow failed: {{ deploy_result.status }}"
        success_msg: "✓ Deploy workflow completed successfully"

    # Verify Registry VM Created
    - name: Check registry VM exists
      ansible.builtin.command:
        cmd: virsh list --all
      register: vm_list
      delegate_to: kvm-host

    - name: Verify registry-quay VM running
      ansible.builtin.assert:
        that:
          - "'registry-quay' in vm_list.stdout"
          - "'running' in vm_list.stdout"
        fail_msg: "Registry VM not running"
        success_msg: "✓ Registry VM created and running"

    # Launch Teardown Workflow
    - name: Launch "Teardown Registry Infrastructure" workflow
      ansible.controller.workflow_launch:
        controller_host: "{{ aap_host }}"
        controller_username: "{{ aap_username }}"
        controller_password: "{{ admin_password }}"
        validate_certs: false
        workflow: "Teardown Registry Infrastructure"
        extra_vars:
          registry_type: quay
          force: true  # Skip confirmation prompts (commit 68990bc)
      register: teardown_job

    # Wait for Teardown
    - name: Wait for teardown workflow to complete
      ansible.controller.workflow_job_wait:
        controller_host: "{{ aap_host }}"
        controller_username: "{{ aap_username }}"
        controller_password: "{{ admin_password }}"
        validate_certs: false
        job_id: "{{ teardown_job.id }}"
        timeout: "{{ workflow_timeout }}"
      register: teardown_result

    # Verify Teardown Success
    - name: Verify teardown workflow succeeded
      ansible.builtin.assert:
        that:
          - teardown_result.status == "successful"
        fail_msg: "Teardown workflow failed"
        success_msg: "✓ Teardown workflow completed successfully"

    # Verify VM Destroyed
    - name: Check registry VM destroyed
      ansible.builtin.command:
        cmd: virsh list --all
      register: vm_list_after
      delegate_to: kvm-host

    - name: Verify registry-quay VM not present
      ansible.builtin.assert:
        that:
          - "'registry-quay' not in vm_list_after.stdout"
        fail_msg: "Registry VM still exists after teardown"
        success_msg: "✓ Registry VM destroyed successfully"

    # Final Summary
    - name: E2E test summary
      ansible.builtin.debug:
        msg:
          - "==================================="
          - "  Registry VM Workflow E2E Test"
          - "==================================="
          - "✓ Deploy workflow: {{ deploy_result.status }}"
          - "✓ VM created and running"
          - "✓ Teardown workflow: {{ teardown_result.status }}"
          - "✓ VM destroyed successfully"
          - ""
          - "E2E Test: PASSED"
          - "==================================="
```
