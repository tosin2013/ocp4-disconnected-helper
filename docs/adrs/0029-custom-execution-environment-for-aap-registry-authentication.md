# ADR-0029: Custom Execution Environment for AAP Registry Authentication

## Date
2026-06-05

## Status
Accepted

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

## Approval

**Approved By**: Project Architecture Team  
**Date**: 2026-06-05  
**Implementation Target**: Immediate (blocks Task #22 - AAP project import)
