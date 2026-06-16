# Operator Presets for OpenShift Disconnected Mirroring

Curated operator bundles for common OpenShift deployment scenarios with pre-validated operator selections.

## Quick Start

### 1. Validate Operators
```bash
# Validate RHACM operators before mirroring
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/rhacm-operators.yml
```

### 2. Mirror via AAP Workflow
```yaml
# In AAP workflow, select preset as extra_vars
@extra_vars/operators/rhacm-operators.yml
```

### 3. Mirror via CLI
```bash
# Download phase
ansible-playbook playbooks/download-to-disk-v2.yml \
  -e @extra_vars/operators/rhacm-operators.yml

# Push phase
ansible-playbook playbooks/push-to-registry-v2.yml \
  -e @extra_vars/operators/rhacm-operators.yml \
  -e target_registry=registry.example.com:8443
```

---

## Available Presets

### Atomic Presets (Single Focus Area)

| Preset | Use Case | Operators | Size Est. |
|--------|----------|-----------|-----------|
| [storage-operators.yml](storage-operators.yml) | Storage (local, ODF, LVMS) | 4 | ~15 GB |
| [rhacm-operators.yml](rhacm-operators.yml) | Multi-cluster management | 4 | ~20 GB |
| [openshift-ai-operators.yml](openshift-ai-operators.yml) | AI/ML workloads, GPU | 5 | ~35 GB |
| [virtualization-operators.yml](virtualization-operators.yml) | VMs + containers | 4 | ~25 GB |
| [service-mesh-operators.yml](service-mesh-operators.yml) | Istio, observability, tracing | 3 | ~18 GB |
| [observability-operators.yml](observability-operators.yml) | Logging, metrics, traces | 5 | ~22 GB |
| [security-operators.yml](security-operators.yml) | Compliance, FIM, registry | 4 | ~20 GB |
| [networking-operators.yml](networking-operators.yml) | Load balancing, multi-network | 4 | ~16 GB |

### Combination Presets (Multi-Capability Bundles)

| Preset | Use Case | Combines | Operators | Size Est. |
|--------|----------|----------|-----------|-----------|
| [full-platform.yml](full-platform.yml) | Complete enterprise platform | Storage + Observability + Security + Networking | 20 | ~70 GB |
| [enterprise-ready.yml](enterprise-ready.yml) | Multi-cluster production platform | RHACM + Storage + Security + Observability | 16 | ~65 GB |
| [developer-stack.yml](developer-stack.yml) | Modern app development + AI/ML | Service Mesh + Observability + AI + GitOps | 13 | ~60 GB |
| [vm-platform.yml](vm-platform.yml) | VMs + containers unified platform | Virtualization + Storage + Networking + Security | 13 | ~55 GB |

---

## Preset Details

### 1. Storage Operators
**File**: `storage-operators.yml`  
**Use Case**: Persistent storage for applications and VMs

**Operators**:
- `local-storage-operator` - Local persistent volumes
- `odf-operator` - OpenShift Data Foundation (Ceph)
- `lvms-operator` - Logical Volume Manager Storage
- `ocs-operator` - OpenShift Container Storage (legacy)

**When to Use**:
- Need persistent storage for stateful workloads
- Running databases (PostgreSQL, MongoDB)
- VM disk storage
- Multi-replica storage with replication

---

### 2. RHACM (Advanced Cluster Management)
**File**: `rhacm-operators.yml`  
**Use Case**: Hub-spoke multi-cluster management

**Operators**:
- `advanced-cluster-management` - RHACM core platform
- `multicluster-engine` - Cluster lifecycle management
- `submariner` - Cross-cluster networking
- `openshift-gitops-operator` - ArgoCD GitOps

**When to Use**:
- Managing 3+ OpenShift clusters
- Policy-based governance across clusters
- GitOps application delivery
- Multi-cluster service discovery

**Requirements**:
- Hub cluster: 16 GB RAM minimum
- Managed clusters: OpenShift 4.10+ or Kubernetes 1.19+

---

### 3. OpenShift AI
**File**: `openshift-ai-operators.yml`  
**Use Case**: AI/ML model training and serving

**Operators**:
- `rhods-operator` - OpenShift AI platform (Jupyter, model serving)
- `authorino-operator` - API security for AI services
- `servicemeshoperator` - Traffic management for AI apps
- `serverless-operator` - Knative auto-scaling for models
- `gpu-operator-certified` (certified catalog) - NVIDIA GPU support

**When to Use**:
- Machine learning model development
- GPU-accelerated training
- Model serving at scale
- Data science workbenches

**Requirements**:
- 32 GB RAM minimum (64 GB+ for GPU)
- NVIDIA GPUs with drivers
- S3-compatible object storage

---

### 4. OpenShift Virtualization
**File**: `virtualization-operators.yml`  
**Use Case**: VMs + containers on same platform

**Operators**:
- `kubevirt-hyperconverged` - VM lifecycle management
- `odf-operator` - Storage for VM disks
- `kubernetes-nmstate-operator` - Advanced networking for VMs
- `metallb-operator` - Load balancing for VM services

**When to Use**:
- Migrating from VMware/KVM to OpenShift
- Running Windows workloads
- Hybrid VM + container applications
- Legacy application modernization

**Requirements**:
- CPU with Intel VT-x or AMD-V
- 32 GB RAM minimum per worker
- 250 GB+ storage per worker

---

### 5. Service Mesh
**File**: `service-mesh-operators.yml`  
**Use Case**: Microservices traffic management

**Operators**:
- `servicemeshoperator` - Istio service mesh
- `kiali-ossm` - Service mesh observability console
- `tempo-product` - Distributed tracing backend

**When to Use**:
- Microservices architecture
- mTLS service-to-service encryption
- Canary deployments and A/B testing
- Traffic routing and circuit breaking

**Requirements**:
- 16 GB RAM minimum per worker
- Persistent storage for traces

---

### 6. Observability Stack
**File**: `observability-operators.yml`  
**Use Case**: Centralized logging, metrics, traces

**Operators**:
- `cluster-logging` - Log collection and forwarding
- `loki-operator` - Log aggregation backend
- `tempo-product` - Distributed tracing
- `cluster-observability-operator` - Unified observability
- `openshift-gitops-operator` - GitOps for config

**When to Use**:
- Centralized logging across clusters
- Long-term log retention
- Distributed tracing for debugging
- Cluster health monitoring

**Requirements**:
- 16 GB RAM minimum per worker
- 100 GB+ persistent storage for logs
- 50 GB+ persistent storage for traces
- S3-compatible object storage recommended

---

### 7. Security & Compliance
**File**: `security-operators.yml`  
**Use Case**: Security hardening and compliance

**Operators**:
- `compliance-operator` - CIS/NIST/PCI-DSS scans
- `file-integrity-operator` - File integrity monitoring (AIDE)
- `quay-operator` - Secure container registry with Clair scanning
- `quay-bridge-operator` - Quay<->OpenShift integration

**When to Use**:
- Compliance requirements (NIST, CIS, PCI-DSS)
- Security auditing and FIM
- Private container registry with vulnerability scanning
- Image trust and signing

**Requirements**:
- 16 GB RAM minimum per worker
- 500 GB+ persistent storage for Quay

---

### 8. Advanced Networking
**File**: `networking-operators.yml`  
**Use Case**: Bare metal load balancing, multi-network

**Operators**:
- `metallb-operator` - L2/BGP load balancing
- `kubernetes-nmstate-operator` - Network state management
- `submariner` - Multi-cluster networking
- `servicemeshoperator` - Istio networking

**When to Use**:
- Bare metal or on-premise clusters (no cloud LB)
- Advanced network configurations
- Multi-cluster service discovery
- Multiple network interfaces per node

**Requirements**:
- Bare metal or on-premise deployment
- BGP router (optional, for MetalLB BGP mode)
- Multiple NICs per node (for advanced configs)

---

## Combination Preset Details

### 1. Full Platform (Complete Enterprise)
**File**: `full-platform.yml`  
**Use Case**: Comprehensive OpenShift deployment with all foundational capabilities

**Includes**:
- **Storage**: ODF, LVMS, Local Storage, Portworx
- **Observability**: Logging, Loki, Tempo, Cluster Observability
- **Security**: Compliance, FIM, Quay Registry
- **Networking**: MetalLB, NMState, Submariner, Service Mesh

**When to Use**:
- New large-scale production deployment
- Enterprise platform with broad requirements
- Multi-tenant environments needing full capabilities
- Replacing legacy infrastructure with OpenShift

**Requirements**:
- 64 GB RAM minimum per worker
- 500 GB+ persistent storage
- 200 GB+ for operator images

---

### 2. Enterprise Ready (Multi-Cluster Production)
**File**: `enterprise-ready.yml`  
**Use Case**: Hub cluster managing multiple spoke clusters with governance

**Includes**:
- **RHACM**: Advanced Cluster Management, Multi-cluster Engine
- **Storage**: ODF, LVMS, Local Storage
- **Security**: Compliance, FIM, Quay Registry
- **Observability**: Logging, Loki, Cluster Observability
- **GitOps**: OpenShift GitOps (ArgoCD)

**When to Use**:
- Managing 3+ OpenShift clusters
- Enterprise governance and compliance requirements
- GitOps-based application delivery
- Multi-datacenter deployments

**Requirements**:
- Hub cluster: 64 GB RAM, 500 GB storage
- Spoke clusters: OpenShift 4.10+ or Kubernetes 1.19+
- S3-compatible object storage recommended

---

### 3. Developer Stack (Modern App Development)
**File**: `developer-stack.yml`  
**Use Case**: Microservices development with AI/ML capabilities

**Includes**:
- **Service Mesh**: Istio, Kiali, distributed tracing
- **Observability**: Logging, Loki, Cluster Observability
- **AI/ML**: OpenShift AI, GPU operator, Serverless
- **GitOps**: OpenShift GitOps (ArgoCD)
- **Storage**: ODF for notebooks and model storage

**When to Use**:
- Microservices architecture development
- Machine learning model training and serving
- Cloud-native application platform
- DevOps teams needing full observability

**Requirements**:
- 48 GB RAM minimum per worker
- NVIDIA GPUs (optional, for AI workloads)
- 200 GB+ persistent storage
- S3-compatible object storage for AI

---

### 4. VM Platform (Virtualization + Containers)
**File**: `vm-platform.yml`  
**Use Case**: Unified platform for VMs and containers (VMware replacement)

**Includes**:
- **Virtualization**: KubeVirt hyperconverged platform
- **Storage**: ODF, LVMS, Local Storage
- **Networking**: NMState, MetalLB, Service Mesh
- **Observability**: Logging, Loki (VM monitoring)
- **Security**: Compliance, FIM (VM security scanning)

**When to Use**:
- Migrating from VMware/KVM to OpenShift
- Running Windows + Linux VMs alongside containers
- Hybrid VM + container applications
- Legacy application modernization path

**Requirements**:
- CPU with Intel VT-x or AMD-V
- 64 GB RAM minimum per worker
- 500 GB+ storage per worker for VM disks
- Bare metal or nested virtualization support

---

## Combining Presets

You can combine multiple presets by merging their operator lists:

```yaml
# extra_vars/operators/custom-combo.yml
---
operators:
  # From storage-operators.yml
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
    packages:
      - name: local-storage-operator
        channels:
          - name: stable
      - name: odf-operator
        channels:
          - name: stable-4.21

  # From observability-operators.yml
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
    packages:
      - name: cluster-logging
        channels:
          - name: stable-6.5
      - name: loki-operator
        channels:
          - name: stable-6.5

# Common configuration
openshift_releases:
  - name: stable-4.21
    minVersion: 4.21.0
    maxVersion: 4.21.0
    shortestPath: true
```

---

## Validation

All presets are validated against Red Hat operator catalogs before mirroring:

```bash
# Validate all presets
for preset in extra_vars/operators/*-operators.yml; do
  echo "Validating $preset..."
  ansible-playbook playbooks/validate-operator-selection.yml -e @$preset
done
```

**Validation Benefits** (ADR-0034):
- ✅ Fails in <5 seconds (vs 10-30 min with oc-mirror)
- ✅ Catches typos with fuzzy-match suggestions
- ✅ Verifies channels are valid
- ✅ Saves bandwidth (no partial downloads)

---

## Creating Custom Presets

### 1. Discover Operators
```bash
# Search for operators by keyword
./scripts/discover-operators.sh --search "storage"
./scripts/discover-operators.sh --search "database"

# List all operators in a catalog
./scripts/discover-operators.sh --list-all
./scripts/discover-operators.sh --list-all --catalog certified
```

### 2. Create Your Preset
```yaml
# extra_vars/operators/my-custom-operators.yml
---
operators:
  - catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21
    packages:
      - name: <operator-name-from-discovery>
        channels:
          - name: <channel-from-discovery>

openshift_releases:
  - name: stable-4.21
    minVersion: 4.21.0
    maxVersion: 4.21.0
    shortestPath: true
```

### 3. Validate Your Preset
```bash
ansible-playbook playbooks/validate-operator-selection.yml \
  -e @extra_vars/operators/my-custom-operators.yml
```

---

## Troubleshooting

### Validation Fails - Operator Not Found
```
Invalid Operators:
  • local-storage (catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21)
    → Did you mean: local-storage-operator?
```

**Solution**: Use the suggested operator name from the validation output.

### Validation Fails - Invalid Channel
```
Invalid Channels:
  • loki-operator:stable-6.1 (catalog: registry.redhat.io/redhat/redhat-operator-index:v4.21)
    → Available channels: stable-6.5
```

**Solution**: Update to the suggested channel version.

### Mirroring Takes Longer Than Expected
- **Expected**: 5-60 minutes for download, 10-90 minutes for push (depending on operator count)
- **Actual**: Check network bandwidth and registry performance
- **Tip**: Use `--parallel-images 4 --parallel-layers 5` in extra_vars for faster mirroring

---

## Size Estimates

### Atomic Presets
| Operator Category | Typical Size | Notes |
|-------------------|--------------|-------|
| Single operator | 2-5 GB | Varies by operator complexity |
| Storage bundle | ~15 GB | 4 operators |
| RHACM bundle | ~20 GB | 4 operators + multi-cluster images |
| OpenShift AI | ~35 GB | Includes GPU operator and ML frameworks |
| Service Mesh | ~18 GB | 3 operators |
| Observability | ~22 GB | 5 operators |
| Security | ~20 GB | 4 operators |
| Networking | ~16 GB | 4 operators |

### Combination Presets
| Combination | Size | Operators | Bandwidth Savings vs Individual |
|-------------|------|-----------|----------------------------------|
| Full Platform | ~70 GB | 20 | ~40% (vs mirroring 4 presets separately) |
| Enterprise Ready | ~65 GB | 16 | ~35% (vs mirroring 4 presets separately) |
| Developer Stack | ~60 GB | 13 | ~30% (vs mirroring 4 presets separately) |
| VM Platform | ~55 GB | 13 | ~30% (vs mirroring 4 presets separately) |

**Bandwidth Savings**: Combination presets deduplicate shared dependencies (e.g., GitOps appears in multiple atomic presets but is mirrored once in combinations).

**Storage Planning**: Allocate 3x the estimated size for workspace + registry storage (e.g., 70 GB preset requires ~210 GB total disk space).

---

## Best Practices

1. **Start Small**: Mirror storage operators first to validate workflow
2. **Validate First**: Always run validation before expensive mirroring
3. **Use Presets**: Leverage curated presets instead of manually selecting operators
4. **Test Offline**: Mirror to test registry before production
5. **Monitor Space**: Ensure adequate disk space before mirroring
6. **Document Custom**: If you create custom presets, document them like these examples

---

## Related Documentation

- **ADR-0034**: Operator Catalog Validation Framework
- **Operator Discovery**: `scripts/discover-operators.sh --help`
- **Validation Quick Start**: `docs/OPERATOR_VALIDATION_QUICKSTART.md`
- **AAP Workflow Guide**: `docs/AAP_OPERATOR_VALIDATION_WORKFLOW.md`

---

**Created**: 2026-06-11  
**Maintainer**: OpenShift Disconnected Helper Project  
**License**: Apache 2.0
