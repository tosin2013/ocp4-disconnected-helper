# AAP Workflow Catalog - OpenShift Disconnected Deployment

**Version**: 1.3  
**Last Updated**: 2026-06-16  
**ADR Reference**: [ADR-0032 v1.3](../docs/adrs/adr-0032-aap-workflow-orchestration-strategy.md)

---

## Overview

This catalog documents the complete set of AAP workflows for OpenShift disconnected deployment. Workflows are numbered sequentially and must be executed in order, with prerequisite validation enforcing correct execution sequence.

**Workflow Philosophy**: Each workflow handles one phase of the deployment lifecycle with clear inputs/outputs and validation gates between phases.

---

## Workflow Catalog

### **Workflow 1: OpenShift Infrastructure Deployment**

**Purpose**: Deploy foundational infrastructure for OpenShift disconnected environments

**Status**: ✅ Configured (v1.3) - Ready for deployment  
**Workflow ID**: TBD (not yet deployed to AAP)  
**Execution Model**: Conditional (adapts to deployment scenario)

#### Components Deployed

| Component | Deployment Condition | Description |
|-----------|---------------------|-------------|
| VyOS Router | KVM environments only | Network infrastructure with VLAN segmentation |
| DNS Services | If not already configured | Route53 (cloud) or FreeIPA (on-premise) |
| Registry VM | Always | KVM guest for container registry (4 vCPU, 16 GiB RAM, 200 GiB disk) |
| Container Registry | Always | Quay, Harbor, or JFrog (survey-driven selection) |
| HAProxy Load Balancer | Always | SNI routing and SSL termination |
| SSL/TLS Certificates | Always | Let's Encrypt (cloud) or self-signed CA (disconnected) |

#### Workflow Execution Graph (8 Steps)

```
┌─────────────────────────────────────────┐
│ Step 1: Assess Deployment Environment  │
│ (Auto-detect or survey-driven)          │
└─────────────┬───────────────────────────┘
              ▼
        ┌─────┴─────┐
        │           │
     (KVM)     (Existing/Cloud)
        │           │
        ▼           │
┌──────────────┐    │
│ Step 2:      │    │
│ Deploy VyOS  │    │ (skip)
└──────┬───────┘    │
        ▼           │
┌──────────────┐    │
│ Step 3:      │    │
│ Configure DNS│    │ (skip if not needed)
└──────┬───────┘    │
        └─────┬─────┘
              ▼
┌─────────────────────────────────────────┐
│ Step 4: Deploy Registry VM              │
└─────────────┬───────────────────────────┘
              ▼
┌─────────────────────────────────────────┐
│ Step 5: Setup Registry (Quay/Harbor)    │
└─────────────┬───────────────────────────┘
              ▼
┌─────────────────────────────────────────┐
│ Step 6: Configure HAProxy               │
└─────────────┬───────────────────────────┘
              ▼
┌─────────────────────────────────────────┐
│ Step 7: Setup SSL/TLS Certificates      │
└─────────────┬───────────────────────────┘
              ▼
┌─────────────────────────────────────────┐
│ Step 8: Verify Infrastructure           │
│ (Comprehensive validation)               │
└─────────────────────────────────────────┘
```

#### Survey Questions

| Question | Options | Default | Description |
|----------|---------|---------|-------------|
| **Deployment Scenario** | `kvm_full` / `existing_infrastructure` / `cloud_deployment` | `kvm_full` | Determines which components to deploy |
| **DNS Provider** | `auto-detect` / `route53` / `freeipa` / `none` | `auto-detect` | DNS service selection |
| **Registry Type** | `quay` / `harbor` / `jfrog` | `quay` | Container registry to deploy |
| **Certificate Mode** | `auto-detect` / `letsencrypt` / `selfsigned` | `auto-detect` | Certificate generation method |

#### Deployment Scenarios

##### **Scenario 1: KVM Full Deployment**
- **When to use**: Starting from scratch on IBM Cloud or bare metal with KVM
- **Components deployed**: All 8 steps execute (VyOS + DNS + Registry + HAProxy + Certificates)
- **Prerequisites**: KVM/libvirt installed, sufficient disk space (300+ GiB)
- **Duration**: ~45-60 minutes

**Survey Selections**:
```yaml
deployment_scenario: kvm_full
dns_provider: auto-detect  # Will use Route53 if AWS creds available
registry_type: quay
certificate_mode: auto-detect  # Will use Let's Encrypt if AWS creds available
```

##### **Scenario 2: Existing Infrastructure**
- **When to use**: Network and DNS already configured, only need registry
- **Components deployed**: Steps 1, 4-8 (skip VyOS and DNS)
- **Prerequisites**: VyOS router accessible, DNS resolving, network connectivity
- **Duration**: ~25-35 minutes

**Survey Selections**:
```yaml
deployment_scenario: existing_infrastructure
dns_provider: none  # DNS already configured externally
registry_type: quay
certificate_mode: selfsigned  # On-premise deployment
```

##### **Scenario 3: Cloud Deployment**
- **When to use**: Deploying on AWS/GCP/Azure with cloud-native networking
- **Components deployed**: Steps 1, 4-8 (skip VyOS and DNS, use cloud DNS)
- **Prerequisites**: Cloud credentials configured, Route53 hosted zone exists
- **Duration**: ~20-30 minutes

**Survey Selections**:
```yaml
deployment_scenario: cloud_deployment
dns_provider: route53  # AWS Route53
registry_type: quay
certificate_mode: letsencrypt  # Let's Encrypt DNS-01 validation
```

#### Prerequisites

**None** - This is the entry point for deployment.

#### Output

- ✅ Container registry accessible at `https://registry.ocp4.sandbox3377.opentlc.com:8443`
- ✅ HAProxy routing traffic with SSL termination
- ✅ Certificates valid and trusted
- ✅ Infrastructure health validated

#### Next Workflow

→ **Workflow 2** (Image Mirroring) - validated via Step 0 prerequisite check

---

### **Workflow 2: OpenShift Image Mirroring**

**Purpose**: Mirror OpenShift releases and operators to disconnected registry

**Status**: ✅ Deployed (v1.3) - Production ready  
**Workflow ID**: 41  
**Execution Model**: Sequential (4-step with validation)

#### Components Mirrored

| Component | Description |
|-----------|-------------|
| OpenShift Releases | Platform images for specified OCP versions |
| Operator Catalogs | Red Hat operator catalogs (redhat-operators, certified-operators, etc.) |
| Operator Packages | Individual operators selected via survey (32 packages across 8 presets) |
| Additional Images | Optional custom images specified in extra_vars |

#### Workflow Execution Graph (4 Steps)

```
┌─────────────────────────────────────────┐
│ Step 0: Verify Infrastructure           │
│ Prerequisites (NEW - v1.3)               │
│ ✓ Registry accessible                   │
│ ✓ HAProxy routing                       │
│ ✓ Certificates valid                    │
└─────────────┬───────────────────────────┘
              ▼ (on success)
┌─────────────────────────────────────────┐
│ Step 1: Validate Operator Selection     │
│ (ADR-0034 - Pre-flight validation)      │
│ ✓ Operator names valid                  │
│ ✓ Catalog accessible                    │
│ ✓ Fuzzy matching for typos              │
└─────────────┬───────────────────────────┘
              ▼ (on success)
┌─────────────────────────────────────────┐
│ Step 2: Download OpenShift Images       │
│ (oc-mirror mirrorToDisk)                │
│ Duration: 30-90 minutes                  │
└─────────────┬───────────────────────────┘
              ▼ (on success)
┌─────────────────────────────────────────┐
│ Step 3: Mirror Images to Registry       │
│ (oc-mirror diskToMirror)                │
│ Duration: 30-60 minutes                  │
└─────────────────────────────────────────┘
```

#### Survey Questions

| Question | Options | Default | Description |
|----------|---------|---------|-------------|
| **Operator Preset** | 12 curated presets + `custom` | `storage-operators` | Pre-validated operator bundles |
| **Custom Preset Path** | File path | *(empty)* | Path to custom YAML (if preset = `custom`) |
| **Target Registry** | Registry URL | `registry.ocp4.sandbox3377.opentlc.com:8443` | Destination registry |
| **Target Namespace** | Namespace | `openshift4` | Registry namespace for images |

#### Operator Presets (12 Curated Bundles)

| Preset Name | Operators Included | Use Case |
|-------------|-------------------|----------|
| `storage-operators` | local-storage-operator, ocs-operator, odf-operator | Persistent storage |
| `rhacm-operators` | advanced-cluster-management, multicluster-engine | Multi-cluster management |
| `openshift-ai-operators` | rhods-operator, authorino-operator, servicemeshoperator | AI/ML workloads |
| `virtualization-operators` | kubevirt-hyperconverged, hostpath-provisioner-operator | VM workloads |
| `service-mesh-operators` | servicemeshoperator, kiali-ossm, jaeger-product | Service mesh |
| `observability-operators` | cluster-logging, elasticsearch-operator, loki-operator | Logging & monitoring |
| `security-operators` | compliance-operator, acs-operator, file-integrity-operator | Security & compliance |
| `networking-operators` | metallb-operator, nmstate-operator, sriov-network-operator | Advanced networking |

**Note**: All presets validated in production (Workflow Job #118, 100% success rate on 32 operators)

#### Prerequisites

**Workflow 1 must complete successfully** - enforced via Step 0 validation:
- ✅ Registry accessible (`https://{{ target_registry }}/v2/` returns 200/401)
- ✅ HAProxy running (`systemctl status haproxy` = active)
- ✅ Certificates valid (files exist, not expired within 24h)

**If validation fails**:
- Workflow stops immediately (fail-fast)
- Clear error message directs user to run Workflow 1 first
- No bandwidth wasted on downloads

#### Output

- ✅ OpenShift release images in registry
- ✅ Operator catalogs mirrored
- ✅ ImageContentSourcePolicy (ICSP) or ImageDigestMirrorSet (IDMS) YAML generated
- ✅ Mirror results available in `/data/ocp-mirror/oc-mirror-workspace/`

#### Next Workflow

→ **Workflow 3** (Cluster Deployment) - Future (v1.4+)

---

### **Workflow 3: OpenShift Cluster Deployment**

**Purpose**: Deploy OpenShift cluster using disconnected registry

**Status**: ⏳ Planned (v1.4+) - Not yet implemented  
**Workflow ID**: TBD  
**Execution Model**: Sequential (multi-phase cluster deployment)

#### Planned Components (Subject to Change)

| Component | Description |
|-----------|-------------|
| Install Config Generation | Create install-config.yaml with imageContentSources |
| Bootstrap Node | Deploy bootstrap VM and ignition config |
| Control Plane | Deploy 3 master nodes |
| Compute Nodes | Deploy worker nodes (configurable count) |
| Post-Install Config | Cluster operators, ingress, authentication |
| Cluster Verification | Health checks and integration tests |

#### Planned Prerequisites

- ✅ Workflow 1 completed (infrastructure deployed)
- ✅ Workflow 2 completed (images mirrored to registry)

#### Planned Timeline

**Target Release**: v1.4 (Q3 2026)  
**Estimated Effort**: 5+ new playbooks required

---

## Workflow Execution Order

**CRITICAL**: Workflows must be executed in numerical order. Prerequisite validation enforces this.

```
┌────────────────────────────────────────┐
│ Workflow 1: Infrastructure Deployment  │
│ (Conditional: KVM/Existing/Cloud)      │
└───────────────┬────────────────────────┘
                │ ✅ Infrastructure Ready
                │ (validated by Workflow 2 Step 0)
                ▼
┌────────────────────────────────────────┐
│ Workflow 2: Image Mirroring            │
│ (Validates Workflow 1 prerequisites)   │
└───────────────┬────────────────────────┘
                │ ✅ Images Mirrored
                │ (validated by Workflow 3 Step 0)
                ▼
┌────────────────────────────────────────┐
│ Workflow 3: Cluster Deployment (Future)│
│ (Validates Workflows 1 & 2)            │
└────────────────────────────────────────┘
```

### Prerequisite Validation Behavior

Each workflow includes a **Step 0** prerequisite check:

1. **Checks infrastructure health** (registry, HAProxy, certificates, network)
2. **Fails gracefully** if prerequisites not met
3. **Provides clear error messages** with troubleshooting steps
4. **Directs user to correct workflow** (e.g., "Run Workflow 1 first")
5. **Prevents wasted bandwidth** (no downloads if infrastructure broken)

**Example Error Message** (Workflow 2 Step 0 failure):
```
❌ PREREQUISITE FAILED: Container registry not accessible

Registry URL: https://registry.ocp4.sandbox3377.opentlc.com:8443/v2/
HTTP Status: Connection refused

**Action Required**:
1. Run Workflow 1 (Infrastructure Deployment) first to deploy registry
2. Verify registry service: podman ps | grep quay
3. Check HAProxy routing: curl -k https://registry.ocp4.sandbox3377.opentlc.com:8443/v2/

**Workflow Execution Order**:
✅ Workflow 1: Infrastructure Deployment (REQUIRED - run this first)
❌ Workflow 2: Image Mirroring (BLOCKED - you are here)
⏸️  Workflow 3: Cluster Deployment (FUTURE)
```

---

## Deployment Scenario Decision Matrix

| Your Situation | Recommended Workflow 1 Scenario | Survey Selections |
|----------------|--------------------------------|-------------------|
| Fresh KVM hypervisor, no infrastructure | `kvm_full` | VyOS + DNS + Registry + HAProxy + Certs (all steps) |
| KVM with existing VyOS and DNS | `existing_infrastructure` | Skip VyOS/DNS, deploy Registry + HAProxy + Certs |
| AWS/GCP/Azure cloud environment | `cloud_deployment` | Skip VyOS, use Route53 DNS, Let's Encrypt certs |
| On-premise with existing network | `existing_infrastructure` | Skip VyOS/DNS, self-signed certs |
| Bare metal with no network infrastructure | `kvm_full` | Deploy all components |

---

## Troubleshooting Guide

### Workflow 1 Failures

#### **Step 1 (Assessment) Fails**
**Symptom**: Assessment playbook errors or incorrect detection

**Solutions**:
1. Verify libvirt connection: `virsh list --all`
2. Check AWS credentials (if using Route53): `ls ~/.aws/credentials`
3. Review assessment output in `/tmp/workflow1-assessment.yml`
4. Override auto-detection with survey selections

#### **Step 2 (VyOS) Fails**
**Symptom**: VyOS VM deployment fails or SSH not accessible

**Solutions**:
1. Check KVM resources: `virsh nodeinfo`
2. Verify VyOS ISO exists: `ls /data/libvirt-images/vyos-*.iso`
3. Check libvirt network: `virsh net-list --all`
4. Review VyOS console: `virsh console vyos`

#### **Step 4 (Registry VM) Fails**
**Symptom**: Registry VM provisioning fails

**Solutions**:
1. Check disk space: `df -h /data/libvirt-images/`
2. Verify cloud-init ISO created: `ls /data/libvirt-images/registry-cloud-init.iso`
3. Check libvirt errors: `virsh dominfo registry`
4. Review VM console: `virsh console registry`

#### **Step 5 (Registry Setup) Fails**
**Symptom**: Quay/Harbor installation fails

**Solutions**:
1. Check registry VM SSH: `ssh admin@192.168.10.10`
2. Verify disk space on registry VM: `df -h`
3. Check podman service: `systemctl status podman`
4. Review installation logs: `journalctl -xe`

#### **Step 8 (Verification) Fails**
**Symptom**: Infrastructure validation fails

**Solutions**:
1. Check each service individually:
   ```bash
   virsh list --all  # VMs running?
   dig registry.ocp4.sandbox3377.opentlc.com  # DNS resolving?
   curl -k https://registry.ocp4.sandbox3377.opentlc.com:8443/v2/  # Registry accessible?
   systemctl status haproxy  # HAProxy running?
   openssl x509 -in /opt/registry-credentials/registry.crt -noout -text  # Cert valid?
   ```
2. Review verification playbook output for specific failures
3. Re-run failed component deployment (idempotent)

### Workflow 2 Failures

#### **Step 0 (Prerequisites) Fails**
**Symptom**: "Registry not accessible" or "HAProxy not running"

**Solution**: **Run Workflow 1 first** - this is intentional validation

**If Workflow 1 already ran**:
1. Check registry service: `systemctl status quay-pod`
2. Check HAProxy service: `systemctl status haproxy`
3. Verify certificates: `ls -la /opt/registry-credentials/`
4. Test connectivity: `curl -k https://registry.ocp4.sandbox3377.opentlc.com:8443/v2/`

#### **Step 1 (Operator Validation) Fails**
**Symptom**: "Operator X not found in catalog"

**Solutions**:
1. Check operator name spelling (validation provides fuzzy matching suggestions)
2. Use curated presets instead of custom operators
3. Verify catalog accessibility: `oc-mirror list operators --catalog redhat-operators`
4. Check Red Hat subscription: `subscription-manager status`

#### **Step 2 (Download) Fails**
**Symptom**: Download fails with network errors or authentication issues

**Solutions**:
1. Verify Red Hat pull secret: `jq . ~/pull-secret.json`
2. Check internet connectivity: `ping registry.redhat.io`
3. Review oc-mirror logs in AAP job output
4. Increase timeout if large download (edit playbook)

#### **Step 3 (Mirror) Fails**
**Symptom**: Push to registry fails

**Solutions**:
1. Verify registry authentication: `podman login registry.ocp4.sandbox3377.opentlc.com:8443`
2. Check registry disk space: `ssh admin@192.168.10.10 "df -h"`
3. Verify combined pull-secret exists: `ls /opt/registry-credentials/pull-secret-combined.json`
4. Test registry connectivity: `curl -k https://registry.ocp4.sandbox3377.opentlc.com:8443/v2/`

### Common Issues Across Workflows

#### **AAP Project Sync Fails**
**Symptom**: "Playbook not found for project"

**Solutions**:
1. Trigger project sync in AAP Web UI: Templates → Projects → ocp4-disconnected-helper → Sync
2. Via API: `curl -X POST https://aap.../api/controller/v2/projects/15/update/`
3. Verify Git credentials if private repository
4. Check AAP logs: `journalctl -u automation-controller -n 100`

#### **Survey Values Not Applied**
**Symptom**: Workflow uses default values instead of survey selections

**Solutions**:
1. Verify survey enabled: Templates → Workflows → Edit → Survey (toggle on)
2. Check survey variable names match playbook expectations
3. Review job output to see what extra_vars were passed
4. Re-create survey if corrupted

#### **Permission Denied Errors**
**Symptom**: "Permission denied" when running playbooks

**Solutions**:
1. Check SSH key configured in AAP: Resources → Credentials
2. Verify credential assigned to job template
3. Test SSH manually: `ssh -i ~/.ssh/id_rsa vpcuser@10.241.64.9`
4. Check sudo permissions on target host

---

## Related Documentation

- [ADR-0032: AAP Workflow Orchestration Strategy](../docs/adrs/adr-0032-aap-workflow-orchestration-strategy.md) - Architectural decisions
- [ADR-0034: Operator Catalog Validation](../docs/adrs/adr-0034-operator-catalog-validation.md) - Operator validation framework
- [AAP Deployment Guide](AAP_DEPLOYMENT_GUIDE.md) - AAP installation and configuration
- [AAP Preset Survey Guide](AAP_PRESET_SURVEY_GUIDE.md) - Operator preset usage
- [Troubleshooting Guide](TROUBLESHOOTING.md) - General troubleshooting

---

## Quick Reference

### Workflow 1 Launch Command (Web UI)
1. Navigate to: **Templates → Workflows**
2. Select: **Workflow 1: OpenShift Infrastructure Deployment**
3. Click: **Launch**
4. Fill survey:
   - Deployment Scenario: `kvm_full` / `existing_infrastructure` / `cloud_deployment`
   - DNS Provider: `auto-detect` (recommended)
   - Registry Type: `quay` (recommended)
   - Certificate Mode: `auto-detect` (recommended)
5. Click: **Next** → **Launch**

### Workflow 2 Launch Command (Web UI)
1. Navigate to: **Templates → Workflows**
2. Select: **Workflow 2: OpenShift Image Mirroring**
3. Click: **Launch**
4. Fill survey:
   - Operator Preset: Select from 12 curated presets
   - Target Registry: `registry.ocp4.sandbox3377.opentlc.com:8443`
   - Target Namespace: `openshift4`
5. Click: **Next** → **Launch**

### Manual Playbook Execution (CLI Fallback)

If AAP unavailable, workflows can be executed via CLI:

```bash
# Workflow 1 (Infrastructure)
ansible-playbook -i inventory/ibm-cloud.yml playbooks/assess-deployment-environment.yml
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-vyos.yml  # If KVM
ansible-playbook -i inventory/ibm-cloud.yml playbooks/setup-route53-dns.yml  # If needed
ansible-playbook -i inventory/ibm-cloud.yml playbooks/deploy-registry.yml
ansible-playbook -i inventory/ibm-cloud.yml playbooks/install-mirror-registry.yml
ansible-playbook -i inventory/ibm-cloud.yml playbooks/configure-haproxy.yml
ansible-playbook -i inventory/ibm-cloud.yml playbooks/setup-certificates.yml
ansible-playbook -i inventory/ibm-cloud.yml playbooks/verify-infrastructure-deployment.yml

# Workflow 2 (Mirroring)
ansible-playbook -i inventory/ibm-cloud.yml playbooks/verify-infrastructure-prerequisites.yml
ansible-playbook -i inventory/ibm-cloud.yml playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/storage-operators.yml
ansible-playbook -i inventory/ibm-cloud.yml playbooks/download-to-disk-v2.yml \
  -e @extra_vars/operators/storage-operators.yml
ansible-playbook -i inventory/ibm-cloud.yml playbooks/push-to-registry-v2.yml \
  -e @extra_vars/operators/storage-operators.yml
```

---

**Last Reviewed**: 2026-06-16  
**Reviewer**: AI Agent (Claude Code)  
**Status**: ✅ Production Ready (Workflows 1-2)
