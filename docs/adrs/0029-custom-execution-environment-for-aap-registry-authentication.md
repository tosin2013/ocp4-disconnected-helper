# ADR-0029: Custom Execution Environment for AAP Registry Authentication

## Date
2026-06-05

## Status
Accepted

## Revision History
- **2026-06-10**: Enhanced with oc-mirror binary for image mirroring job templates (see § oc-mirror Enhancement)

## Context

Ansible Automation Platform (AAP) 2.6 uses execution environments (containerized Ansible runtimes) to run automation jobs. When importing the ocp4-disconnected-helper project into AAP, project syncs fail with:

```
Error: unable to retrieve auth token: invalid username/password: unauthorized: 
Please login to the Red Hat Registry using your Customer Portal credentials
```

**Root Cause**: AAP's Control Plane Execution Environment is immutable and cannot have container registry credentials assigned post-deployment. The environment attempts to pull images from `registry.redhat.io` but lacks authentication.

**Attempted Solutions (All Failed)**:
1. Created Container Registry credential via Web UI → Credential exists but not used
2. Created Container Registry credential via API → Organization-level, but not auto-detected
3. Attempted to assign credential to Control Plane EE → UI does not allow modification (immutable)

**Impact**: Complete blocker for AAP project import workflow. Cannot proceed with ADR 0021 (AAP adoption) without resolving registry authentication.

## Decision

Create a **custom execution environment** by forking `https://github.com/tosin2013/ansible-execution-environment.git`, embedding `registry.redhat.io` authentication credentials, building the container image, publishing to Quay.io, and configuring it as the default execution environment for the Default organization in AAP.

**Repository Naming**: Rename fork to `ocp4-aap-execution-environment` to reflect project specificity.

**Quay Registry**: Host custom EE image at `quay.io/[username]/ocp4-aap-execution-environment:latest`

**Implementation Components**:
1. **Repository Fork**: Clone and customize ansible-execution-environment
2. **Credential Embedding**: Add `registry.redhat.io` auth to `execution-environment.yml`
3. **Build Automation**: Ansible playbook using `ansible-builder` to generate container image
4. **Quay Integration**: Authenticate and push to Quay registry
5. **AAP Configuration**: Update Default organization to use custom EE

## Consequences

### Positive

1. **Resolves Authentication Blocker**: Enables AAP project syncs by providing authenticated registry access
2. **Full Control**: Complete ownership of execution environment contents and dependencies
3. **Future Extensibility**: Can add custom Ansible collections, Python packages, or system dependencies
4. **Best Practice Alignment**: Follows Red Hat's recommended approach for custom execution environments
5. **Quay Integration**: Leverages enterprise-grade container registry with access control and scanning

### Negative

1. **Build/Maintenance Workflow**: Adds EE build, test, and publish pipeline to project lifecycle
2. **Credential Security**: Registry credentials embedded in container image (mitigated by Quay private repository)
3. **Credential Rotation**: Must rebuild and republish EE when `registry.redhat.io` credentials rotate
4. **Upstream Dependency**: Relies on `tosin2013/ansible-execution-environment` for base configuration updates
5. **Storage Overhead**: Custom EE images consume Quay storage quota
6. **Image Size**: With oc-mirror binary (~300MB), total EE image size increases to ~3GB

### Security Considerations

**Credential Embedding Strategy**:
- Credentials stored in `execution-environment.yml` as environment variables
- Container image pushed to **private** Quay repository (not public)
- AAP authenticates to Quay using dedicated Container Registry credential
- Quay repository access restricted to authorized users only

**Credential Rotation Process**:
1. Update credentials in `extra_vars/rhel-subscription-secrets.yml`
2. Rebuild EE with new credentials: `ansible-playbook playbooks/build-custom-ee.yml`
3. Push updated image to Quay (overwrites `:latest` tag)
4. AAP automatically pulls updated image on next project sync (if `Always pull` enabled)

## Alternatives Considered

### 1. Wait for Red Hat to Fix Control Plane EE Credential Assignment
**Status**: Rejected  
**Reason**: Control Plane EE is immutable by design (per AAP 2.6 architecture). Not a bug - this is intended behavior.

### 2. Use Insecure Registry Access (`--skip-tls-verify`)
**Status**: Rejected  
**Reason**: Security violation. Would allow unauthenticated registry access, exposing system to man-in-the-middle attacks and unverified image pulls.

### 3. Deploy Local Container Registry Mirror
**Status**: Rejected  
**Reason**: Over-engineered for this use case. Adds complexity (registry deployment, sync automation, storage management) when custom EE directly solves the authentication problem.

### 4. Switch to Different Automation Platform
**Status**: Rejected  
**Reason**: ADR 0021 already committed to AAP 2.5 adoption. Switching platforms would contradict existing architectural decision and waste previous AAP deployment effort.

## Implementation Plan

### Phase 1: Repository Setup
```bash
# Fork repository
gh repo fork tosin2013/ansible-execution-environment \
  --clone --remote \
  --org tosin2013 \
  --fork-name ocp4-aap-execution-environment

# Update remote URLs and metadata
cd ocp4-aap-execution-environment
git remote rename origin upstream
git remote add origin git@github.com:tosin2013/ocp4-aap-execution-environment.git
```

### Phase 2: Quay Registry Setup
1. Create Quay repository: `quay.io/tosin2013/ocp4-aap-execution-environment`
2. Set visibility: **Private**
3. Generate robot account for AAP access
4. Configure Quay credentials in AAP:
   ```yaml
   Name: Quay Custom EE Registry
   Type: Container Registry
   Registry URL: quay.io
   Username: tosin2013+aap_robot
   Password: <robot_token>
   ```

### Phase 3: Build Automation
Create `playbooks/build-custom-ee.yml`:
```yaml
- name: Build and Publish Custom AAP Execution Environment
  hosts: localhost
  tasks:
    - name: Install ansible-builder
      ansible.builtin.pip:
        name: ansible-builder
        state: present

    - name: Build execution environment
      ansible.builtin.command:
        cmd: ansible-builder build --tag quay.io/tosin2013/ocp4-aap-execution-environment:latest
        chdir: /path/to/ocp4-aap-execution-environment

    - name: Authenticate to Quay
      ansible.builtin.command:
        cmd: podman login quay.io --username {{ quay_username }} --password {{ quay_password }}

    - name: Push to Quay registry
      ansible.builtin.command:
        cmd: podman push quay.io/tosin2013/ocp4-aap-execution-environment:latest
```

### Phase 4: AAP Configuration
```yaml
- name: Configure Custom Execution Environment in AAP
  ansible.controller.execution_environment:
    name: "Custom OCP4 EE"
    description: "Custom execution environment with registry.redhat.io authentication"
    image: "quay.io/tosin2013/ocp4-aap-execution-environment:latest"
    pull: "always"
    credential: "Quay Custom EE Registry"
    organization: "Default"
    controller_host: "{{ aap_host }}"
    controller_username: "admin"
    controller_password: "{{ admin_password }}"
    state: present

- name: Set as default EE for organization
  ansible.controller.organization:
    name: "Default"
    default_environment: "Custom OCP4 EE"
    controller_host: "{{ aap_host }}"
    controller_username: "admin"
    controller_password: "{{ admin_password }}"
```

## Verification

### Success Criteria
1. ✅ Custom EE built successfully with `ansible-builder`
2. ✅ Image pushed to `quay.io/tosin2013/ocp4-aap-execution-environment:latest`
3. ✅ AAP can authenticate to Quay and pull custom EE image
4. ✅ Project sync for `ocp4-disconnected-helper` succeeds (no registry auth errors)
5. ✅ Job templates execute successfully using custom EE

### Test Procedure
```bash
# 1. Verify EE image in Quay
curl -u "tosin2013+aap_robot:<token>" \
  https://quay.io/api/v1/repository/tosin2013/ocp4-aap-execution-environment

# 2. Trigger project sync in AAP
curl -k -u admin:<admin_password> \
  -X POST \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/projects/<project_id>/update/

# 3. Verify sync succeeded (status: successful)
curl -k -u admin:<admin_password> \
  https://aap.sandbox3377.opentlc.com/api/controller/v2/projects/<project_id>/

# 4. Launch test job template
awx job_templates launch --name="Deploy Registry VM"
```

## Related ADRs

- **ADR 0021**: Deprecate Airflow and Adopt AAP 2.5 - This ADR extends AAP adoption by resolving EE authentication
- **ADR 0028**: AAP 2.6 Multi-Node Password Architecture - Adds Quay registry credentials to credential taxonomy
- **ADR 0009**: Secrets Management (Ansible Vault → HashiCorp Vault) - Custom EE credentials stored via Ansible Vault

## References

- [AAP 2.6 Execution Environments Guide](https://docs.redhat.com/en/documentation/red_hat_ansible_automation_platform/2.6/html/creating_and_consuming_execution_environments/)
- [ansible-builder Documentation](https://ansible.readthedocs.io/projects/builder/)
- [Quay.io Container Registry](https://quay.io/)
- [Upstream EE Repository](https://github.com/tosin2013/ansible-execution-environment)

## oc-mirror Enhancement

### Context (2026-06-10)

AAP job template "Mirror OpenShift Images to Registry" fails with:
```
fatal: [localhost]: FAILED! => {"msg": "[Errno 2] No such file or directory: b'oc-mirror'"}
```

**Root Cause**: Custom EE includes `oc` and `kubectl` binaries but not `oc-mirror`, which is required for OpenShift image mirroring operations (ADR 0003).

**Storage Architecture Issue**: AAP controller VM (192.168.10.21) has only 60GB disk, insufficient for 50GB mirror operations. Hypervisor has 1TB at `/data` but AAP jobs run locally on controller by default.

### Decision Enhancement

**Add oc-mirror binary** to custom execution environment (similar to oc/kubectl installation pattern).

**Execution Model**: AAP job templates for mirroring will use **SSH delegation** to run on hypervisor (kvm-host) instead of AAP controller, ensuring downloads write to `/data/ocp-mirror/` with adequate storage.

### Implementation Changes

#### 1. execution-environment.yml
Add oc-mirror installation in `prepend_galaxy` section (after oc/kubectl installation):
```yaml
# Install oc-mirror from tarball (required for image mirroring job templates)
- >
  RUN OC_MIRROR_ENV="/_extras/optional/oc-mirror-install.env" ; \
      if [ -f "$OC_MIRROR_ENV" ]; then set -a; . "$OC_MIRROR_ENV"; set +a; fi ; \
      if [ -n "$OC_MIRROR_URL" ] || [ -n "$OC_MIRROR_VERSION" ]; then \
        echo "==> Installing oc-mirror from tarball" && \
        URL="${OC_MIRROR_URL:-https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OC_MIRROR_VERSION}/oc-mirror.tar.gz}" && \
        curl -L --fail --retry 3 --max-time 300 -o /tmp/oc-mirror.tgz "$URL" && \
        tar -C /usr/local/bin -xzf /tmp/oc-mirror.tgz && \
        chmod +x /usr/local/bin/oc-mirror && \
        ln -sf /usr/local/bin/oc-mirror /usr/bin/oc-mirror && \
        /usr/local/bin/oc-mirror version && \
        rm -f /tmp/oc-mirror.tgz ; \
      fi
```

Add in `append_final` section (after kubectl):
```yaml
- COPY --from=galaxy /usr/local/bin/oc-mirror /usr/local/bin/oc-mirror
- RUN ln -sf /usr/local/bin/oc-mirror /usr/bin/oc-mirror
```

#### 2. AAP Job Template Configuration
Update `playbooks/configure-aap-job-templates.yml`:
- Change mirror job template to target `kvm-host` via limit
- Add "KVM Hypervisor SSH Key" credential requirement
- Ensures execution on hypervisor with `/data` storage

#### 3. Inventory Update
Modify `kvm-host` in AAP inventory:
```yaml
kvm-host:
  ansible_host: "10.241.64.9"  # Internal IP
  ansible_user: "vpcuser"
  ansible_connection: "ssh"  # Changed from "local"
```

### Storage Flow

```
AAP Web UI (user clicks Launch)
    ↓
AAP Controller (spawns EE container)
    ↓
EE Container SSH → Hypervisor (10.241.64.9)
    ↓
oc-mirror executes on Hypervisor
    ↓
Downloads to /data/ocp-mirror/ (1TB storage ✅)
```

### Impact

- **EE Image Size**: +300MB (oc-mirror binary)
- **Build Time**: +2-3 minutes (download + extract)
- **Enables**: AAP job templates for `push-to-registry-v2.yml` playbook
- **Storage**: Mirroring uses hypervisor `/data` (1TB), not controller (60GB)

## CI/CD Integration (2026-06-17)

### Context

GitHub Actions workflows for Ansible sanity checks (`.github/workflows/ansible-sanity.yml`) need to validate playbook syntax for 26+ playbooks, including 9 AAP-specific playbooks that require `ansible.controller` collection. This collection is unavailable in standard pip-installed Ansible and requires either:
1. Licensed AAP instance with `automation-hub` access (not viable for CI)
2. Custom execution environment with pre-installed collections

**Challenge**: Installing `ansible.controller` via pip requires authentication to Ansible Automation Hub (`cloud.redhat.com`), which is not available in public GitHub Actions runners.

### Solution

**Use the same custom EE built for AAP in GitHub Actions CI/CD pipelines.**

**Registry Path**: `quay.io/takinosh/ocp4-aap-execution-environment:latest`

**Implementation**:
```yaml
# .github/workflows/ansible-sanity.yml
syntax-check:
  runs-on: ubuntu-latest
  steps:
    - name: Pull Custom AAP Execution Environment
      run: |
        # Source: https://github.com/tosin2013/ocp4-aap-execution-environment
        podman pull quay.io/takinosh/ocp4-aap-execution-environment:latest

    - name: Check playbook syntax (in custom EE container)
      run: |
        for playbook in playbooks/*.yml; do
          podman run --rm \
            -v $PWD:/workspace:Z \
            -w /workspace \
            quay.io/takinosh/ocp4-aap-execution-environment:latest \
            ansible-playbook --syntax-check "$playbook" \
            -i inventory/ibm-cloud.yml \
            || exit 1
        done
```

### Benefits

1. **Zero Credential Management**: No need to store Ansible Hub tokens in GitHub Secrets
2. **Complete Coverage**: All 26+ playbooks validated (no skipping AAP playbooks)
3. **Consistent Environment**: Same execution environment in CI and AAP runtime
4. **Faster CI**: Pull pre-built image (~3GB, 30-60s) vs pip install + collection downloads
5. **Dependency Parity**: Exact same Ansible collections, Python packages, and binaries

### Repository Alignment

**Custom EE Repository**: `https://github.com/tosin2013/ocp4-aap-execution-environment`
- Builds and publishes image to `quay.io/takinosh/ocp4-aap-execution-environment:latest`
- Uses GitHub Actions workflow (`.github/workflows/build-and-push.yml`)
- Runs on: push to main, workflow_dispatch, git tags

**This Repository**: `https://github.com/tosin2013/ocp4-disconnected-helper`
- Pulls public image from Quay in CI workflow
- No custom EE build logic (delegates to separate repo)
- CI workflow triggers on: PR, push to main, workflow_dispatch

### Deployment Model

```
┌─────────────────────────────────────┐
│ ocp4-aap-execution-environment repo │
│  - execution-environment.yml        │
│  - Makefile (build/test/publish)    │
│  - GitHub Actions workflow          │
└──────────────┬──────────────────────┘
               │ builds & pushes
               ↓
┌─────────────────────────────────────┐
│ quay.io/takinosh/                   │
│   ocp4-aap-execution-environment    │
│   :latest (public image)            │
└──────────────┬──────────────────────┘
               │ pulls from
     ┌─────────┴─────────┐
     ↓                   ↓
┌─────────────┐  ┌──────────────────┐
│ AAP Runtime │  │ GitHub Actions   │
│ Job Execute │  │ CI Syntax Checks │
└─────────────┘  └──────────────────┘
```

### Impact on v1.3.0 Release

**Before**: CI workflow failed with `couldn't resolve module/action 'ansible.controller.*'` errors, requiring skip patterns that prevented AAP playbook validation.

**After**: All playbooks validated in CI using same execution environment as AAP runtime, ensuring consistency between CI checks and production execution.

**Release Gate Compliance**: Satisfies v1.3.0 requirement: "GitHub Actions pipelines must pass for lint and Molecule testing" (per user requirement: "i would not consider the release a success until it actually deploys a disconnected openshift via aap and our github actions pipelines pass").

## Best Practices

### Version Pinning in CI/CD

**Always use specific version tags** (e.g., `v1.2.0`) instead of `latest` in CI/CD workflows for:

1. **Reproducibility**: Ensures builds are deterministic across time
2. **Cache Invalidation**: Avoids stale image caches from registry/runtime
3. **Explicit Upgrades**: Forces intentional EE updates with testing
4. **Rollback Safety**: Clear version history for quick rollback if needed

**Example** (`.github/workflows/ansible-sanity.yml`):

```yaml
# ✅ GOOD - Pinned to specific version
podman pull quay.io/takinosh/ocp4-aap-execution-environment:v1.2.1

# ❌ BAD - Latest tag may be cached or not yet updated
podman pull quay.io/takinosh/ocp4-aap-execution-environment:latest
```

**Rationale**: On 2026-06-17, the v1.2.0 release was published but the `latest` tag had not yet propagated to all registry caches. GitHub Actions workflows pulling `:latest` received an older image (May 25, 2026) missing `ansible.controller` collection, causing syntax check failures. Switching to `:v1.2.0` immediately resolved the issue.

**Update (2026-06-17)**: v1.2.1 released as critical patch to add missing `infra.aap_utilities` collection discovered by CI workflow during v1.2.0 validation. This demonstrates the value of version pinning - the CI caught the gap before it could affect deployments. All workflows updated to v1.2.1.

### Update Strategy

When a new EE version is released:

1. Review release notes: https://github.com/tosin2013/ocp4-aap-execution-environment/releases
2. Update workflow to new version tag: `vX.Y.Z`
3. Test CI workflow passes with new version
4. Merge PR and document version update in commit message

**Never use `latest` in production workflows** — only for local development/testing.

## Approval

**Approved By**: Project Architecture Team  
**Date**: 2026-06-05  
**Implementation Target**: Immediate (blocks Task #22 - AAP project import)  
**Enhancement Approved**: 2026-06-10 (oc-mirror + SSH delegation)  
**CI/CD Integration Approved**: 2026-06-17 (GitHub Actions container-based validation)  
**Version Pinning Practice Approved**: 2026-06-17 (Pin to v1.2.0 for reproducibility)  
**v1.2.1 Upgrade Approved**: 2026-06-17 (Critical patch for infra.aap_utilities collection)
