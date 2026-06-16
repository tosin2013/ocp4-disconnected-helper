# AAP Workflow Validation Framework Testing Guide

**ADR 0033**: AAP Workflow Validation and Health Check Framework  
**Status**: Implemented (Phases 1-3 complete)  
**Last Updated**: 2026-06-10

---

## Overview

The AAP Workflow Validation Framework provides automated testing for Ansible Automation Platform (AAP) workflow orchestration. It validates AAP deployment health and end-to-end workflow execution to ensure compliance with architectural decisions (ADRs 0031, 0028, 0032).

### Validation Layers

| Layer | Type | Tools | Speed | Scope |
|-------|------|-------|-------|-------|
| **Layer 1** | Health Checks | Shell scripts (bash + curl + jq) | Fast (<1 min) | AAP Controller API, instance health, authentication, Control Plane EE |
| **Layer 2** | E2E Workflow Tests | Ansible playbooks | Slow (10-60 min) | Full workflow lifecycle (deploy → verify → teardown) |
| **Layer 3** | CI/CD Integration | GitHub Actions | Automated | Continuous validation on every commit |

---

## Prerequisites

### For Layer 1 (Shell Scripts)

- **Tools**: `curl`, `jq` (install: `sudo dnf install -y curl jq`)
- **AAP Instance**: Deployed and accessible
- **Credentials**: 
  - `AAP_GATEWAY_PASSWORD` (automationgateway_admin_password from secrets file)
  - `AAP_CONTROLLER_PASSWORD` (admin_password from secrets file)
- **Network Access**: HTTPS connectivity to AAP Controller API

### For Layer 2 (Ansible Playbooks)

- **Ansible Runtime**: Ansible 2.16+ with `ansible.controller` collection
- **Credentials**: Ansible Vault password file (`~/.vault_pass`)
- **Secrets File**: `extra_vars/rhel-subscription-secrets.yml` (encrypted)
- **KVM Access**: SSH access to hypervisor host (for VM validation)
- **AAP Workflows**: Configured via `playbooks/aap-configuration/` playbooks

---

## Layer 1: Health Checks (Shell Scripts)

### Purpose

Fast smoke tests to validate AAP deployment health before running comprehensive E2E tests.

### Scripts

#### 1. AAP Health Validation (`scripts/validate-aap-health.sh`)

**Validates**:
- AAP Controller API availability (`/api/v2/ping/`)
- Instance health and capacity (`/api/v2/instances/`)
- Dual password authentication (Gateway + Controller - ADR 0028)
- Control Plane EE registry authentication (project sync status - ADR 0031)
- Database connectivity

**Usage**:
```bash
# Set environment variables
export AAP_HOST="https://aap.sandbox3377.opentlc.com"
export AAP_GATEWAY_PASSWORD="<automationgateway_admin_password>"
export AAP_CONTROLLER_PASSWORD="<admin_password>"

# Run health checks
./scripts/validate-aap-health.sh
```

**Exit Codes**:
- `0`: All health checks passed
- `1`: Health check failure (specific error message provided)
- `2`: Configuration error (credentials missing, AAP unreachable)

**Example Output**:
```
========================================
AAP Health Validation (ADR 0033)
========================================
Target: https://aap.sandbox3377.opentlc.com
Username: admin

[CHECK] Checking AAP Controller API availability...
✓ Controller API healthy (version: 4.6.0, HA: true)

[CHECK] Checking AAP instance health and capacity...
  Instance aap-controller-1: capacity 100
✓ All instances healthy (total capacity: 100)

[CHECK] Validating dual password architecture (ADR 0028)...
  Testing Gateway password authentication...
  Testing Controller password authentication...
✓ Dual password authentication valid (Gateway + Controller)

[CHECK] Validating Control Plane EE registry authentication (ADR 0031)...
✓ Control Plane EE authenticated (project: ocp4-disconnected-helper, last sync: 2026-06-10T18:30:00Z)

========================================
Health Check Summary
========================================
Total Checks: 5
Passed: 5
Failed: 0

✓ All health checks passed - AAP deployment healthy

ADR Compliance Validated:
  ✓ ADR 0031: Control Plane EE registry authentication
  ✓ ADR 0028: Dual password architecture (Gateway + Controller)
```

#### 2. Workflow Template Validation (`scripts/validate-aap-workflow-templates.sh`)

**Validates**:
- Expected workflow templates exist (Deploy/Teardown patterns)
- Workflow nodes configured correctly
- Job template references valid
- `force=true` configured for teardown workflows (commit 68990bc fix)

**Usage**:
```bash
export AAP_HOST="https://aap.sandbox3377.opentlc.com"
export AAP_CONTROLLER_PASSWORD="<admin_password>"

./scripts/validate-aap-workflow-templates.sh
```

**Example Output**:
```
[CHECK] Checking workflow templates existence...
  Found 4 workflow templates
  ✓ Deploy Disconnected OpenShift Infrastructure
  ✓ Teardown Disconnected OpenShift Infrastructure
  ✓ Deploy Registry Infrastructure
  ✓ Teardown Registry Infrastructure
✓ All expected workflow templates exist (4 workflows)

[CHECK] Validating workflow node connectivity...
  Deploy Disconnected OpenShift Infrastructure: 2 node(s)
  Teardown Disconnected OpenShift Infrastructure: 1 node(s)
  Deploy Registry Infrastructure: 7 node(s)
  Teardown Registry Infrastructure: 3 node(s)
✓ Workflow nodes configured (total: 13 nodes)

[CHECK] Checking workflow extra_vars configuration...
  Teardown Disconnected OpenShift Infrastructure: force=true configured ✓
  Teardown Registry Infrastructure: force=true configured ✓
✓ Teardown workflows configured with force=true (2 workflows)
```

---

## Layer 2: E2E Workflow Tests (Ansible Playbooks)

### Purpose

Comprehensive end-to-end testing of AAP workflow orchestration, validating full lifecycle (deploy → verify → teardown).

### Playbooks

#### 1. Registry VM Workflow Test (`playbooks/test-registry-vm-workflow.yml`)

**Tests**:
- Deploy Registry Infrastructure workflow (7-node workflow)
- Registry VM provisioning and health
- Teardown Registry Infrastructure workflow (3-node workflow)
- Storage cleanup (VM disk, cloud-init ISO)
- Idempotency (second deploy succeeds)

**Usage**:
```bash
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/test-registry-vm-workflow.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass

# Dry run mode (no actual VM provisioning)
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/test-registry-vm-workflow.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass \
  -e test_dry_run=true
```

**Success Criteria**:
- ✅ Deploy workflow completes with `successful` status
- ✅ Registry VM created and running (`virsh list` shows VM)
- ✅ Teardown workflow completes with `successful` status
- ✅ VM destroyed (not in `virsh list`)
- ✅ VM disk removed (`/data/libvirt-images/registry-quay.qcow2` does not exist)
- ✅ Cloud-init ISO removed
- ✅ Idempotency test passes (second deploy succeeds)

**Execution Time**: ~20-30 minutes (with actual VM provisioning)

#### 2. oc-mirror Workflow Test (`playbooks/test-oc-mirror-workflow.yml`)

**Tests**:
- Deploy Disconnected OpenShift Infrastructure workflow (2-phase: download + push)
- TAR archive creation (`/data/ocp-mirror/*.tar`)
- ImageSetConfiguration file creation
- Teardown workflow with `force=true` (no interactive prompts - commit 68990bc)
- Workspace cleanup
- Async cache detection

**Usage**:
```bash
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/test-oc-mirror-workflow.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass \
  -e skip_phase2=true  # Skip push-to-registry (requires registry)

# Full test (requires registry)
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/test-oc-mirror-workflow.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass \
  -e skip_phase2=false
```

**Success Criteria**:
- ✅ Deploy workflow completes with `successful` status
- ✅ TAR archives created in `/data/ocp-mirror/`
- ✅ `imageset-config-v2.yml` created
- ✅ Workspace directory created (`/data/ocp-mirror/oc-mirror-workspace/`)
- ✅ Teardown workflow completes without blocking (validates `force=true` fix)
- ✅ Workspace removed
- ✅ imageset-config removed
- ✅ TAR archives removed (when `clean_all=true`)

**Execution Time**: ~30-60 minutes (depends on image count)

---

## Layer 3: CI/CD Integration (GitHub Actions)

### Workflow File

`.github/workflows/validate-aap-workflows.yml`

### Triggers

- **Pull Requests**: Automatically runs on PRs modifying workflow-related files
- **Push to Main**: Validates after merge to `main` branch
- **Manual Dispatch**: On-demand execution with custom parameters

### Jobs

| Job | Purpose | Duration |
|-----|---------|----------|
| `health-checks` | Layer 1 validation (fast smoke test) | ~2-5 minutes |
| `e2e-workflow-tests` | Layer 2 validation (comprehensive E2E) | ~30-90 minutes |
| `validation-summary` | Generate final report and compliance summary | ~1 minute |

### Required Secrets

Configure these in GitHub repository settings (Settings → Secrets → Actions):

| Secret Name | Description | Source |
|-------------|-------------|--------|
| `AAP_TEST_HOST` | AAP Controller URL | https://aap.sandbox3377.opentlc.com |
| `AAP_GATEWAY_PASSWORD` | Gateway admin password | `automationgateway_admin_password` from secrets file |
| `AAP_CONTROLLER_PASSWORD` | Controller API password | `admin_password` from secrets file |
| `ANSIBLE_VAULT_PASSWORD` | Vault decryption key | Contents of `~/.vault_pass` |

### Manual Workflow Dispatch

```yaml
# Go to: Actions → AAP Workflow Validation → Run workflow

Parameters:
  test_environment: ephemeral | staging | existing
  skip_deployment: false (run full E2E) | true (use existing AAP)
  dry_run: false (actual resources) | true (simulate only)
```

---

## Troubleshooting

### Common Failures

#### 1. "AAP Controller API unreachable"

**Symptoms**:
```
✗ Controller API unreachable: curl: (7) Failed to connect to aap.sandbox3377.opentlc.com port 443
```

**Causes**:
- AAP not deployed or not running
- Firewall blocking HTTPS (port 443)
- Incorrect `AAP_HOST` environment variable

**Solutions**:
```bash
# Check AAP services running
ssh aap.sandbox3377.opentlc.com "systemctl status automation-controller"

# Verify firewall allows HTTPS
ssh aap.sandbox3377.opentlc.com "firewall-cmd --list-all | grep 443"

# Test connectivity
curl -k https://aap.sandbox3377.opentlc.com/api/v2/ping/
```

#### 2. "Project sync failed (Control Plane EE cannot pull images)"

**Symptoms**:
```
✗ Project sync failed (Control Plane EE cannot pull images)
  Check ADR 0031 compliance: registry credentials in AAP installer inventory?
```

**Causes**:
- Registry credentials NOT in AAP installer inventory before `setup.sh` (violates ADR 0031)
- Incorrect `registry_username` or `registry_password` format
- Network issue accessing `registry.redhat.io`

**Solutions**:
```bash
# Verify registry credentials in installer inventory
ssh aap.sandbox3377.opentlc.com "grep -A5 registry /opt/ansible-automation-platform/installer/inventory"

# Expected output:
# registry_url='registry.redhat.io'
# registry_username='<org-id>|<service-account-name>'
# registry_password='<token>'

# If missing, re-run AAP deployment with credentials:
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-aap-multi-node.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

#### 3. "Teardown workflow failed: Type 'yes' to continue"

**Symptoms**:
```
Workflow blocked on interactive prompt (force=false)
```

**Causes**:
- `force: false` in workflow extra_vars (should be `force: true` per commit 68990bc)
- Workflow template not updated after configuration playbook run

**Solutions**:
```bash
# Re-run workflow configuration with force=true fix
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/aap-configuration/configure-teardown-workflow.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass

# Verify force=true in workflow extra_vars
./scripts/validate-aap-workflow-templates.sh
```

#### 4. "Dual password authentication failed"

**Symptoms**:
```
✗ Gateway authentication failed (check AAP_GATEWAY_PASSWORD)
  Expected: automationgateway_admin_password from secrets file
```

**Causes**:
- Wrong password used (confused `admin_password` vs `automationgateway_admin_password`)
- Password contains special characters not properly escaped

**Solutions**:
```bash
# Verify passwords in secrets file
ansible-vault view extra_vars/rhel-subscription-secrets.yml | grep admin_password

# Expected two separate passwords:
# admin_password: "<controller-api-password>"
# automationgateway_admin_password: "<gateway-web-ui-password>"

# Test Gateway password manually
curl -sk -u admin:"<automationgateway_admin_password>" \
  https://aap.sandbox3377.opentlc.com/api/gateway/v1/config/

# Test Controller password manually
curl -sk -u admin:"<admin_password>" \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/ping/
```

---

## ADR Compliance Matrix

| ADR | Validation Method | Layer | Success Criteria |
|-----|-------------------|-------|------------------|
| **ADR 0031** (Control Plane EE Registry Auth) | Project sync status check (`/api/controller/v2/project_updates/`) | Layer 1 | Latest project sync status = `successful` |
| **ADR 0028** (Dual Password Architecture) | Gateway + Controller auth test | Layer 1 | Both passwords authenticate correctly (no 401 errors) |
| **ADR 0032** (Workflow Orchestration) | E2E deploy/teardown lifecycle | Layer 2 | Both workflows complete with `successful` status |
| **ADR 0008** (GitHub Actions) | CI/CD integration | Layer 3 | Automated tests run on every PR/push |
| **Commit 68990bc** (force=true fix) | Teardown workflow completion without prompts | Layer 2 | Teardown completes without blocking on confirmation |

---

## Running Tests Locally

### Quick Smoke Test (Layer 1 Only)

```bash
# 1-minute validation
export AAP_HOST="https://aap.sandbox3377.opentlc.com"
export AAP_GATEWAY_PASSWORD="<password>"
export AAP_CONTROLLER_PASSWORD="<password>"

./scripts/validate-aap-health.sh && ./scripts/validate-aap-workflow-templates.sh
```

### Comprehensive E2E Test (All Layers)

```bash
# Layer 1: Health checks (fast)
./scripts/validate-aap-health.sh
./scripts/validate-aap-workflow-templates.sh

# Layer 2: E2E workflow tests (slow)
ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/test-registry-vm-workflow.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass

ansible-playbook -i inventory/ibm-cloud.yml \
  playbooks/test-oc-mirror-workflow.yml \
  -e@extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass \
  -e skip_phase2=true

# Total time: ~45-60 minutes
```

---

## Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Layer 1 Execution Time** | < 2 minutes | Shell script runtime |
| **Layer 2 Execution Time** | < 90 minutes | Ansible playbook runtime (full E2E) |
| **False Positive Rate** | < 5% | Tests passing when AAP actually broken |
| **False Negative Rate** | < 1% | Tests failing when AAP actually healthy |
| **CI/CD Reliability** | > 95% | Successful CI runs / total runs |

---

## References

- **ADR 0033**: AAP Workflow Validation and Health Check Framework (`docs/adrs/0033-aap-workflow-validation-framework.md`)
- **ADR 0032**: AAP Workflow Orchestration for Infrastructure Lifecycle Management
- **ADR 0031**: AAP Installer Registry Credential Configuration
- **ADR 0028**: AAP 2.6 Multi-Node Password Architecture
- **ADR 0008**: GitHub Actions Automation
- **Commit 68990bc**: Fix force=true by default in AAP workflows to avoid interactive prompts
- **AWX API Documentation**: https://docs.ansible.com/projects/awx/en/latest/rest_api/api_ref.html

---

**Last Updated**: 2026-06-10  
**Implementation Status**: Phases 1-3 complete, Phase 4 (cluster upgrade workflow tests) planned for Q3 2026
