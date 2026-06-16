# Workflow Survey Parameters Reference

Complete reference for all AAP workflow survey parameters.

---

## Workflow 1: Registry Infrastructure Deployment

**Workflow Name**: `Workflow 1: Registry Infrastructure Deployment`

### Survey Parameters (2 total)

#### 1. Registry Type

**Variable**: `registry_type`  
**Type**: Multiple Choice (single select)  
**Required**: Yes  
**Default**: `quay`

**Options**:
- `quay` - Red Hat Quay mirror-registry v2 (recommended for OpenShift)
- `harbor` - Harbor containerized registry
- `jfrog` - JFrog Artifactory containerized registry

**Description**: Select container registry to deploy.

**Impact**:
- Determines which playbook is executed in Step 2 (Setup Registry)
- Quay: Runs `playbooks/setup-mirror-registry.yml`
- Harbor: Runs `playbooks/setup-harbor-registry.yml`
- JFrog: Runs `playbooks/setup-jfrog-registry.yml`

**Recommendation**: Use `quay` for official Red Hat support and OpenShift integration.

---

#### 2. Certificate Mode

**Variable**: `certificate_mode`  
**Type**: Multiple Choice (single select)  
**Required**: Yes  
**Default**: `selfsigned`

**Options**:
- `letsencrypt` - Let's Encrypt DNS-01 validation (requires Route53 DNS and AWS credentials)
- `selfsigned` - Self-signed CA certificate (for disconnected/air-gapped environments)

**Description**: Select certificate generation mode.

**Impact**:
- Determines SSL/TLS certificate source in Step 4 (Setup Certificates)
- Let's Encrypt: Publicly trusted, requires internet access and DNS control
- Self-signed: Works offline, requires CA distribution to clients

**Recommendation**:
- Use `letsencrypt` for cloud deployments with public DNS
- Use `selfsigned` for air-gapped deployments

---

## Workflow 2: OpenShift Image Mirroring

**Workflow Name**: `Workflow 2: OpenShift Image Mirroring`

### Survey Parameters (2 total)

#### 1. Operator Preset

**Variable**: `operator_preset_file`  
**Type**: Multiple Choice (single select)  
**Required**: Yes  
**Default**: `storage-operators`

**Options**:
- `storage-operators` - Persistent storage (local-storage, ODF, NFS, Hostpath) - 8 operators
- `networking-operators` - Advanced networking (Multus, SR-IOV, MetalLB) - 6 operators
- `observability-operators` - Monitoring and logging (Prometheus, Grafana, Loki) - 7 operators
- `security-operators` - Security and compliance (ACS, Compliance, Cert Manager) - 5 operators
- `virtualization-operators` - OpenShift Virtualization (CNV, CDI, HPP) - 4 operators
- `service-mesh-operators` - Service mesh (Istio, Kiali, Jaeger) - 6 operators
- `openshift-ai-operators` - AI/ML workloads (RHOAI, ODH) - 9 operators
- `rhacm-operators` - Multi-cluster management (RHACM, Submariner) - 5 operators

**Description**: Select operator bundle to mirror.

**Impact**:
- Loads operator list from `extra_vars/operators/<preset>.yml`
- Determines which operators are validated in Step 0 (Verify Prerequisites)
- Affects download size and time (4-9 operators per preset, ~10-30GB)

**Recommendation**: Start with `storage-operators` (most commonly needed).

---

#### 2. Registry URL

**Variable**: `target_registry`  
**Type**: Text (short answer)  
**Required**: Yes  
**Default**: `registry.example.com:8443`

**Format**: `hostname:port` or `ip:port`

**Examples**:
- `registry.example.com:8443`
- `192.168.10.10:8443`
- `quay.io/myorg` (public registries)

**Description**: Target container registry for image push.

**Impact**:
- Determines destination for `oc-mirror` push operation
- Must match registry deployed in Workflow 1
- Used in ImageContentSourcePolicy (ICSP) generation

**Validation**:
- Step 0 checks registry is accessible via HTTPS
- Step 0 validates authentication with credentials

**Recommendation**: Use FQDN (not IP) for production deployments.

---

## Parameter Validation

### Workflow 1 Validation

**No validation** - all parameters are valid choices from dropdown.

### Workflow 2 Validation

**Step 0: Verify Prerequisites** validates:
1. **Operator Preset**: All operators in preset exist in target catalog
2. **Registry URL**: Registry is accessible and authenticated

**Failure Behavior**:
- Invalid operators: Fails with fuzzy-matched suggestions
- Unreachable registry: Fails with connection error and remediation steps

---

## Parameter Override via CLI

### Override Survey Parameters

When launching workflows via Ansible Controller API:

```bash
curl -sk -u admin:"$GATEWAY_PASSWORD" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "extra_vars": {
      "registry_type": "harbor",
      "certificate_mode": "letsencrypt",
      "operator_preset_file": "networking-operators",
      "target_registry": "harbor.prod.example.com"
    }
  }' \
  "https://aap.sandbox3377.opentlc.com/api/controller/v2/workflow_job_templates/$WORKFLOW_ID/launch/"
```

### Override in Manual Playbook Execution

```bash
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e operator_preset_file=security-operators \
  -e target_registry=192.168.10.10:8443
```

---

## Parameter Dependencies

### Cross-Workflow Dependencies

**Workflow 2 depends on Workflow 1**:
- `target_registry` (Workflow 2) must match registry deployed in Workflow 1
- Certificate mode affects registry URL (HTTP vs HTTPS)

**Validation Enforcement**: Step 0 in Workflow 2 checks Workflow 1 completion.

### Certificate Mode Impact

**Let's Encrypt** requires:
- AWS credentials in AAP
- Route53 DNS zone control
- Public DNS hostname

**Self-signed** requires:
- CA certificate distribution to clients
- Manual trust configuration

---

## Survey Customization

### Add Custom Operator Preset

1. Create preset file:
```bash
cp extra_vars/operators/storage-operators.yml \
   extra_vars/operators/custom-operators.yml
```

2. Edit operator list:
```yaml
operator_preset_name: "custom-operators"
operators:
  - name: my-operator
    catalog: redhat-operator-index
```

3. Update workflow survey in AAP Web UI:
   - Navigate to **Templates → Workflows → Workflow 2**
   - Edit **Survey**
   - Add `custom-operators` to **Operator Preset** choices

### Change Default Values

Edit workflow configuration playbook:

```yaml
# playbooks/aap-configuration/configure-infrastructure-workflow.yml
survey_spec:
  spec:
    - question_name: "Registry Type"
      default: "harbor"  # Change from "quay"
```

Re-deploy workflow configuration:
```bash
ansible-playbook playbooks/aap-configuration/configure-infrastructure-workflow.yml
```

---

## Related Documentation

- [AAP Workflow Catalog](../AAP_WORKFLOW_CATALOG.md) - Complete workflow reference
- [Operator Presets Reference](operator-presets.md) - Detailed preset documentation
- [ADR-0032: Multi-Workflow Architecture](../adrs/adr-0032-aap-workflow-orchestration-strategy.md)
