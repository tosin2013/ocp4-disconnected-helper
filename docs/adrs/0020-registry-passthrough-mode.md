# ADR 0020: Registry Passthrough Mode for Container Image Distribution

## Status
Proposed

## Date
2025-12-12

## Context

Disconnected OpenShift environments require transparent container image access where workloads reference upstream registries (e.g., `quay.io`, `registry.redhat.io`) but actually pull from a local registry. This "passthrough mode" enables:

1. **Transparent redirection** - Workloads use standard image references without modification
2. **Tarfile-based distribution** - Images distributed as tar archives for air-gapped transfer
3. **Registry abstraction** - Local registry acts as cache/mirror for upstream content
4. **ICSP integration** - OpenShift ImageContentSourcePolicy handles redirection automatically

### Current Gaps

Existing ADRs cover registry setup (0004, 0017) and image mirroring (0003) but lack:
- End-to-end tarfile → registry → ICSP workflow
- Registry authentication automation (robot accounts/tokens)
- Standardized repository naming conventions
- Validation procedures for mirrored content
- Integration patterns with existing playbooks

## Decision

Implement **Registry Passthrough Mode** as a comprehensive workflow combining:
- Tarfile-based image distribution
- Local registry mirroring (Quay/Harbor/mirror-registry)
- ICSP-based transparent redirection
- Automated authentication and validation

### Key Components

1. **Repository Naming Convention**
   - Standardized mapping: `registry.local/mirror/<upstream-registry>/<path>`
   - Example: `registry.local/mirror/quay.io/organization/image:tag`

2. **Authentication Automation**
   - Robot accounts for Harbor
   - Robot tokens for Quay
   - Secure credential management via Ansible vault

3. **Tarfile Workflow**
   - Connected side: `oc-mirror` → tar archives
   - Disconnected side: Load → Push → ICSP generation

4. **Validation Procedures**
   - Verify image existence in local registry
   - Test ICSP redirection functionality
   - Automated pull tests

## Rationale

### Why Passthrough Mode?

1. **No workload modifications** - Applications use standard image references
2. **Air-gap optimized** - Designed for disconnected environments
3. **Registry agnostic** - Works with Quay, Harbor, or mirror-registry
4. **Automated workflow** - End-to-end automation via Ansible playbooks
5. **Production ready** - Matches enterprise deployment patterns

### Benefits

- **Simplicity** - Workloads reference `quay.io/app:tag` normally
- **Transparency** - ICSP handles redirection automatically
- **Flexibility** - Supports multiple registry types
- **Reliability** - Automated validation ensures content availability
- **Security** - Proper authentication and certificate management

## Consequences

### Positive

- **Zero application changes** - Existing manifests work unmodified
- **Standardized workflow** - Consistent process across deployments
- **Registry flexibility** - Choice of Quay, Harbor, or mirror-registry
- **Automated validation** - Reduced manual verification
- **Air-gap optimized** - Designed for disconnected transfer

### Negative

- **ICSP dependency** - Requires OpenShift 4.3+
- **Registry overhead** - Additional infrastructure component
- **Complexity** - Multiple steps in the workflow
- **Storage requirements** - Duplicate image storage

### Trade-offs

| Requirement | Solution | Alternative |
|-------------|----------|-------------|
| Simple deployment | Passthrough mode | Direct registry references |
| Air-gap support | Tarfile distribution | Network mirroring |
| Zero app changes | ICSP redirection | Manifest rewriting |
| Multiple registries | Standardized naming | Registry-specific configs |

## Implementation

### 1. Repository Naming Convention

```yaml
# Standard mapping template
registry_local: "registry.disconnected.local:8443"
naming_pattern: "{{ registry_local }}/mirror/{{ upstream_registry }}/{{ image_path }}"

# Examples
quay.io/app:tag → registry.local/mirror/quay.io/app:tag
registry.redhat.io/rhel8:latest → registry.local/mirror/registry.redhat.io/rhel8:latest
```

### 2. Authentication Setup

```yaml
# Harbor robot account
harbor_robot_accounts:
  - name: "ocp-mirror"
    permissions: ["pull", "push"]
    projects: ["mirror"]

# Quay robot token
quay_robot_tokens:
  - name: "ocp-mirror"
    permissions: ["read", "write"]
    repositories: ["mirror/*"]
```

### 3. Tarfile Workflow

#### Connected Side
```bash
# Download to tar archives
oc-mirror -c imageset-config.yml \
    file:///opt/mirror \
    --v2 \
    --continue-on-error
```

#### Disconnected Side
```bash
# Load and push to registry
skopeo copy docker-archive:images.tar \
    docker://registry.local/mirror/quay.io/organization/app:tag

# Generate ICSP
cat <<EOF > icsp.yaml
apiVersion: config.openshift.io/v1
kind: ImageContentSourcePolicy
metadata:
  name: registry-mirror
spec:
  repositoryDigestMirrors:
  - mirrors:
    - registry.local/mirror/quay.io
    source: quay.io
    - mirrors:
    - registry.local/mirror/registry.redhat.io
    source: registry.redhat.io
EOF
```

### 4. New Playbooks

#### `playbooks/setup-registry-passthrough.yml`
```yaml
- name: Configure Registry Passthrough Mode
  hosts: registry
  vars:
    registry_type: "{{ registry_type | default('mirror-registry') }}"
    naming_convention: "{{ naming_pattern }}"
  tasks:
    - name: Create robot accounts
      include_tasks: "tasks/setup-{{ registry_type }}-auth.yml"
    
    - name: Configure repository structure
      include_tasks: "tasks/setup-repository-structure.yml"
    
    - name: Generate ICSP template
      include_tasks: "tasks/generate-icsp-template.yml"
```

#### `playbooks/validate-passthrough-mode.yml`
```yaml
- name: Validate Registry Passthrough Mode
  hosts: orchestration
  tasks:
    - name: Test image pull via ICSP
      include_tasks: "tasks/test-icsp-redirection.yml"
    
    - name: Verify image existence
      include_tasks: "tasks/verify-mirrored-images.yml"
```

### 5. Integration with Existing Workflows

```yaml
# Updated Airflow DAG
validate_environment
    → setup_certificates
    → setup_registry (existing)
    → setup_registry_passthrough (NEW)
    → download_to_tar (existing)
    → push_tar_to_registry (existing)
    → apply_icsp_policy (NEW)
    → validate_passthrough_mode (NEW)
    → build_appliance
```

### 6. ICSP Template Generation

```yaml
# templates/icsp-policy.yml.j2
apiVersion: config.openshift.io/v1
kind: ImageContentSourcePolicy
metadata:
  name: registry-passthrough-{{ registry_type }}
spec:
  repositoryDigestMirrors:
{% for mirror in registry_mirrors %}
  - mirrors:
    - {{ registry_local }}/mirror/{{ mirror.source }}
    source: {{ mirror.source }}
{% endfor %}
```

## Validation Procedures

### 1. Image Existence Validation
```bash
# Verify all referenced images exist in local registry
for image in $(oc get images -o jsonpath='{.items[*].dockerImageReference}'); do
    skopeo inspect docker://$image --tls-verify=false
done
```

### 2. ICSP Redirection Test
```bash
# Deploy test pod referencing upstream image
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-passthrough
spec:
  containers:
  - name: test
    image: quay.io/centos/centos:stream8
EOF

# Verify pull from local registry
oc logs test-passthrough | grep "Pulling from"
```

### 3. End-to-End Workflow Test
```bash
# Complete workflow test
ansible-playbook playbooks/test-passthrough-workflow.yml \
    -e @extra_vars/passthrough-test-vars.yml
```

## Security Considerations

### 1. Certificate Management
- Use ADR 0016 for trusted certificate generation
- Add registry CA to OpenShift cluster trust store
- Validate certificate chain for all registry communications

### 2. Authentication Security
- Store robot credentials in Ansible vault
- Rotate tokens regularly
- Use least privilege principle for robot accounts

### 3. Network Security
- Restrict registry access to cluster nodes only
- Use network policies to control traffic
- Enable TLS for all registry communications

## Migration Path

### For Existing Deployments
1. **Current State**: Direct registry references in manifests
2. **Transition**: Apply ICSP while keeping existing references
3. **Target State**: Full passthrough mode with automated workflows

### Migration Steps
1. Deploy registry with passthrough configuration
2. Generate and apply ICSP policies
3. Validate redirection functionality
4. Update automation workflows
5. Decommission direct registry access

## Related ADRs

- [ADR 0003: oc-mirror v2 for Image Mirroring](0003-oc-mirror-image-mirroring.md) - Base mirroring functionality
- [ADR 0004: Dual Registry Support](0004-dual-registry-support.md) - Registry setup playbooks
- [ADR 0017: Quay Mirror Registry](0017-quay-mirror-registry.md) - Lightweight registry option
- [ADR 0018: Registry VM Deployment](0018-registry-vm-deployment.md) - Dedicated registry infrastructure
- [ADR 0016: Trusted Certificate Management](0016-trusted-certificate-management.md) - Certificate handling

## Implementation Tasks

1. [x] Create `playbooks/setup-registry-passthrough.yml`
2. [x] Create `playbooks/validate-passthrough-mode.yml`
3. [x] Create `tasks/setup-*auth.yml` for each registry type (harbor, quay, mirror-registry, jfrog)
4. [x] Create `tasks/setup-repository-structure.yml`
5. [x] Create `tasks/generate-icsp-template.yml`
6. [x] Create `tasks/test-icsp-redirection.yml`
7. [x] Create `tasks/verify-mirrored-images.yml`
8. [x] Update `push-tar-to-registry.yml` with naming convention
9. [x] Update Airflow DAGs with passthrough tasks (`ocp_registry_sync.py`)
10. [x] Create `extra_vars/passthrough-example.yml`
11. [ ] Create validation test suite
12. [ ] Update documentation

## Implementation Status

**Completed: 2025-12-12**

### Files Created
- `playbooks/setup-registry-passthrough.yml` - Main passthrough configuration playbook
- `playbooks/validate-passthrough-mode.yml` - Validation playbook
- `playbooks/tasks/setup-harbor-auth.yml` - Harbor authentication
- `playbooks/tasks/setup-quay-auth.yml` - Quay authentication
- `playbooks/tasks/setup-mirror-registry-auth.yml` - Mirror registry authentication
- `playbooks/tasks/setup-jfrog-auth.yml` - JFrog authentication
- `playbooks/tasks/setup-repository-structure.yml` - Repository structure setup
- `playbooks/tasks/generate-icsp-template.yml` - ICSP template generation
- `playbooks/tasks/test-icsp-redirection.yml` - ICSP redirection testing
- `playbooks/tasks/verify-mirrored-images.yml` - Image verification
- `playbooks/tasks/create-mirror-repo-harbor.yml` - Harbor mirror repo creation
- `playbooks/tasks/create-mirror-repo-quay.yml` - Quay mirror repo creation
- `playbooks/tasks/create-mirror-repo-mirror-registry.yml` - Mirror registry repo creation
- `playbooks/tasks/create-mirror-repo-jfrog.yml` - JFrog mirror repo creation
- `playbooks/templates/icsp-policy.yml.j2` - ICSP policy template
- `playbooks/templates/apply-icsp.sh.j2` - ICSP application script
- `extra_vars/passthrough-example.yml` - Example configuration

### Files Updated
- `airflow/dags/ocp_registry_sync.py` - Added passthrough mode support
- `playbooks/push-tar-to-registry.yml` - Added ADR references and passthrough vars

### Registry Mirror Configuration (Red Hat Requirements)
Based on Red Hat Solution 2998411, the following registries are configured:
- **Core**: registry.access.redhat.com, registry.redhat.io, registry.connect.redhat.com
- **High Priority**: quay.io, cdn.quay.io, docker.io, storage.googleapis.com/openshift-release
- **Medium Priority**: sso.redhat.com, github.com, gitlab.com

## References

- [OpenShift ImageContentSourcePolicy](https://docs.openshift.com/container-platform/latest/applications/operators/configuring-image-content-source-policy.html)
- [oc-mirror documentation](https://docs.openshift.com/container-platform/latest/cli/reference/oc-mirror/)
- [Quay mirror-registry](https://github.com/quay/mirror-registry)
- [Harbor documentation](https://goharbor.io/docs/)
- [Skopeo documentation](https://github.com/containers/skopeo)
