# ADR 0030: Rootless Podman Authentication Architecture for Custom Execution Environments

**Date**: 2026-06-09

**Status**: Accepted

**Context**: CentOS Stream 10, Podman 5.8.2, ansible-builder 3.1.1

**Deciders**: Infrastructure Team, Security Team

**Related ADRs**:
- ADR 0029: Custom Execution Environment for AAP Registry Authentication
- ADR 0009: Secrets Management (Ansible Vault → HashiCorp Vault migration)
- ADR 0022: Standalone Architecture (Pure Ansible with async)

---

## Context and Problem Statement

Building custom Ansible Automation Platform (AAP) Execution Environments on CentOS Stream 10 using `ansible-builder` consistently fails with authentication errors when pulling the base image from `registry.redhat.io`. The failures manifest as:

1. **"Unauthorized" HTTP 401** errors despite valid Red Hat service account credentials
2. **Permission denied** errors on `/run/user/1001/containers/auth.json`
3. **Permission denied** errors on `/run/user/1001/crun/` directory during container build
4. **Mysterious credential expiration** after system reboots or session terminations

Root cause analysis revealed a fundamental architectural mismatch between:
- **Ansible's `become: true`** (privilege escalation to root)
- **Podman's rootless authentication** (user-namespace isolation)
- **ansible-builder's subprocess model** (environment variable inheritance)

## Decision Drivers

### Functional Requirements

- **FR1**: Build custom Execution Environments without `sudo` (principle of least privilege)
- **FR2**: Authenticate to `registry.redhat.io` using Red Hat service account credentials
- **FR3**: Persist authentication state across system reboots and session terminations
- **FR4**: Enable `ansible-builder` subprocesses to inherit authentication context
- **FR5**: Support automated CI/CD pipelines (Ansible playbooks, GitHub Actions)

### Non-Functional Requirements

- **NFR1**: Security - Credentials protected by DAC 0600 permissions
- **NFR2**: Portability - Solution must work on CentOS Stream 10, RHEL 10, Fedora 40+
- **NFR3**: Maintainability - Clear separation between volatile and persistent storage
- **NFR4**: Auditability - File ownership and permissions must be verifiable
- **NFR5**: Performance - Minimize network round-trips via local image caching

### Security Constraints

- **SC1**: Container builds must NOT run as root (supply chain risk mitigation)
- **SC2**: JWT tokens must NOT appear in shell history or process arguments
- **SC3**: Auth files owned by root in user directories are a critical vulnerability
- **SC4**: Credentials must NOT be embedded in container image layers

## Considered Options

### Option 1: Continue Using Root Execution (`sudo ansible-builder`)

**Pros**:
- Temporarily bypasses authentication issues
- Simple to implement

**Cons**:
- ❌ Violates principle of least privilege (SC1)
- ❌ Creates root-owned files in user workspace (filesystem contamination)
- ❌ Escalates supply chain compromise risk
- ❌ Breaks developer workflows (permission denied on subsequent runs)

**Decision**: **REJECTED** - Fundamentally incompatible with DevSecOps best practices

### Option 2: Share Root Credentials with Non-Root User

**Pros**:
- Could theoretically work with proper `chown` operations

**Cons**:
- ❌ Creates race conditions and permission drift
- ❌ Violates Linux namespace isolation principles
- ❌ Difficult to automate reliably
- ❌ Audit trail ambiguity (who authenticated?)

**Decision**: **REJECTED** - Anti-pattern that leads to persistent failures

### Option 3: Rootless Podman with Persistent Authentication (SELECTED)

**Architecture**: Enforce strict separation between volatile (`/run`) and persistent (`$HOME/.config`) credential storage, with explicit environment variable exports.

**Pros**:
- ✅ Fully rootless execution (FR1, SC1)
- ✅ Persistent across reboots (FR3)
- ✅ Subprocess inheritance via `REGISTRY_AUTH_FILE` (FR4)
- ✅ DAC-compliant security model (NFR1, SC2, SC3)
- ✅ Compatible with CI/CD automation (FR5)

**Cons**:
- Requires one-time remediation script to fix stale artifacts
- Requires environment variable exports in `~/.bashrc`

**Decision**: **ACCEPTED**

## Decision Outcome

We adopt **Option 3: Rootless Podman with Persistent Authentication**.

### Implementation Strategy

#### 1. Authentication File Path Resolution (XDG Spec Compliance)

Podman follows the XDG Base Directory Specification for credential storage:

| Path Type | Location | Persistence | Use Case |
|-----------|----------|-------------|----------|
| **Volatile** | `/run/user/$(id -u)/containers/auth.json` | tmpfs (wiped on reboot) | Single-session interactive use |
| **Persistent** | `$HOME/.config/containers/auth.json` | Disk-backed | CI/CD, automated builds |

**Decision**: Use `--authfile` flag to target persistent storage explicitly.

```bash
podman login --authfile="$HOME/.config/containers/auth.json" \
  --username '12216224|ansible-execution-environment' \
  --password-stdin \
  registry.redhat.io
```

#### 2. Environment Variable Configuration

To ensure `ansible-builder` subprocesses inherit authentication context, export globally:

```bash
# Add to ~/.bashrc
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export REGISTRY_AUTH_FILE="${HOME}/.config/containers/auth.json"
```

**Rationale**: Python's `subprocess.run()` inherits parent `os.environ`. Without `REGISTRY_AUTH_FILE`, podman subprocesses revert to querying the volatile `/run` path.

#### 3. Discretionary Access Control (DAC) Requirements

| Resource | Required Permissions | Required Ownership |
|----------|---------------------|-------------------|
| `~/.config/containers/` | `0700` (drwx------) | `vpcuser:vpcuser` |
| `auth.json` | `0600` (-rw-------) | `vpcuser:vpcuser` |

**Enforcement**: Any deviation from these permissions causes Podman to reject the file.

#### 4. Privilege Bleed Remediation

**Problem**: When Ansible playbooks use `become: true` (default in `ansible.cfg`), `podman login` executes as root but writes to the user's directory, creating root-owned files:

```bash
# BAD: Executed via Ansible with become: true
stat /run/user/1001/containers/auth.json
# Output: Permissions: 600 Owner: root:root
```

**Solution**: Add `become: false` to all Podman-related tasks:

```yaml
- name: Authenticate to registry.redhat.io
  ansible.builtin.shell:
    cmd: echo "{{ registry_password }}" | podman login ...
  become: false  # CRITICAL: Run as vpcuser, not root
```

#### 5. Red Hat Service Account Credential Handling

**Username Format**: `12216224|ansible-execution-environment`

The pipe character (`|`) is a shell control operator. **Must be quoted**:

```bash
# ✓ Correct - Single quotes prevent shell interpretation
podman login -u '12216224|ansible-execution-environment' registry.redhat.io

# ✗ Wrong - Shell interprets | as a pipe
podman login -u 12216224|ansible-execution-environment registry.redhat.io
# Error: bash: ansible-execution-environment: command not found
```

**Password Format**: JWT token (`eyJhbGci...`)

**Must use `--password-stdin`** to prevent token exposure in shell history:

```bash
# ✓ Correct - Token not visible in ps or history
echo "$TOKEN" | podman login -u 'USER' --password-stdin registry.redhat.io

# ✗ Wrong - Token visible in ps aux and ~/.bash_history
podman login -u 'USER' -p 'eyJhbGci...' registry.redhat.io
```

### Stale Authentication Remediation Protocol

A comprehensive 5-phase remediation script (`scripts/setup-rootless-podman-auth.sh`) implements:

**Phase 1**: Eradicate stale artifacts (root-owned auth.json, crun, libpod directories)

**Phase 2**: Establish persistent storage (`mkdir -p ~/.config/containers`, `chmod 700`)

**Phase 3**: Execute rootless login (`podman login --authfile ...`)

**Phase 4**: Validate DAC permissions (`stat`, verify 0600 ownership)

**Phase 5**: Export environment variables (append to `~/.bashrc`)

**Usage**:
```bash
./scripts/setup-rootless-podman-auth.sh \
  --registry-username '12216224|ansible-execution-environment' \
  --registry-password 'eyJhbGci...'
```

### ansible-builder Integration

With persistent authentication in place, `ansible-builder` operates transparently:

```bash
# Subprocess inherits REGISTRY_AUTH_FILE from parent shell
export REGISTRY_AUTH_FILE="$HOME/.config/containers/auth.json"

ansible-builder build \
  --tag quay.io/USER/ocp4-aap-execution-environment:latest \
  --container-runtime podman \
  -v 3
```

**No** `--build-arg REGISTRY_PASSWORD` required - authentication happens during base image pull, not during build.

## Consequences

### Positive

✅ **Security**: Fully rootless builds eliminate supply chain compromise vectors

✅ **Reliability**: Persistent authentication survives reboots and session changes

✅ **Auditability**: Clear UID/GID ownership simplifies compliance audits

✅ **Developer Experience**: Single remediation script fixes all permission issues

✅ **CI/CD Compatibility**: Works in GitHub Actions, AAP job templates, cron jobs

✅ **Performance**: Pre-cached base images eliminate redundant registry queries

### Negative

⚠️ **One-Time Setup**: Requires running remediation script once per user/host

⚠️ **Shell Configuration**: Requires `source ~/.bashrc` in new sessions

⚠️ **Documentation Overhead**: Teams must understand XDG spec and DAC policies

### Neutral

- **Podman-Specific**: Solution does not apply to Docker (different auth model)
- **CentOS 10 Optimized**: Leverages Podman 5.x features (pasta networking)

## Compliance and References

### Technical Standards

- **XDG Base Directory Specification** (freedesktop.org)
- **OCI Distribution Specification** (registry authentication)
- **POSIX Shell Quoting Rules** (pipe character handling)

### Red Hat Documentation

- [Podman Rootless Tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [ansible-builder Documentation](https://ansible-builder.readthedocs.io/)
- [Red Hat Registry Service Accounts](https://access.redhat.com/terms-based-registry/)

### Related Project Files

- `scripts/setup-rootless-podman-auth.sh` - Remediation automation
- `playbooks/build-custom-ee.yml` - Updated with `become: false`
- `docs/PODMAN_ENVIRONMENT_SETUP.md` - Troubleshooting guide
- `.github/workflows/build-custom-ee.yml` - CI/CD integration

## Verification and Testing

### Manual Verification

```bash
# 1. Verify persistent auth file exists and has correct permissions
stat ~/.config/containers/auth.json
# Expected: Permissions: 600 Owner: vpcuser:vpcuser

# 2. Verify environment variables are exported
echo $REGISTRY_AUTH_FILE
# Expected: /home/vpcuser/.config/containers/auth.json

# 3. Test authentication with base image pull
podman pull registry.redhat.io/ansible-automation-platform-25/ee-minimal-rhel9:latest
# Expected: Success (no "Unauthorized" error)

# 4. Test ansible-builder build
cd /home/vpcuser/ocp4-aap-execution-environment
ansible-builder build --tag test:latest --container-runtime podman
# Expected: Success (base image pull works without additional login)
```

### Automated Testing

```yaml
# Test playbook: verify-rootless-auth.yml
- name: Verify Rootless Podman Authentication
  hosts: localhost
  become: false  # Run as standard user
  tasks:
    - name: Check REGISTRY_AUTH_FILE is set
      assert:
        that:
          - lookup('env', 'REGISTRY_AUTH_FILE') != ''
        fail_msg: "REGISTRY_AUTH_FILE not exported"

    - name: Verify auth.json exists
      stat:
        path: "{{ lookup('env', 'HOME') }}/.config/containers/auth.json"
      register: auth_file

    - name: Validate auth.json permissions
      assert:
        that:
          - auth_file.stat.exists
          - auth_file.stat.mode == '0600'
          - auth_file.stat.pw_name == lookup('env', 'USER')
        fail_msg: "auth.json has incorrect permissions or ownership"
```

## Rollback Strategy

If rootless authentication proves unstable, the emergency fallback is:

1. **Run ansible-builder in a container** (Podman-in-Podman with privileged mode)
2. **Use buildah decoupled workflow** (`ansible-builder create` + `buildah build`)
3. **Pre-cache base image** (`podman pull` before `ansible-builder build`)

However, these workarounds do not address the underlying architecture and should be considered temporary.

## Future Considerations

### Planned Enhancements

1. **HashiCorp Vault Integration** (ADR 0009): Replace Ansible Vault with Vault agent for credential injection
2. **Sealed Secrets** (Kubernetes): Encrypted credentials in GitOps workflows
3. **AAP Custom Credential Type**: Native AAP integration for `REGISTRY_AUTH_FILE`

### Monitoring and Alerts

- **Metric**: `podman_login_failures_total` (auth.json permission errors)
- **Metric**: `ansible_builder_unauthorized_errors` (registry 401 responses)
- **Alert**: Trigger on 3+ consecutive build failures with "Permission denied"

## Approval

**Approved by**: Infrastructure Team Lead

**Date**: 2026-06-09

**Supersedes**: N/A (First formal rootless authentication ADR)

---

## Appendix A: Troubleshooting Decision Tree

```
Build fails with "Unauthorized" error
  ├─ Is REGISTRY_AUTH_FILE exported?
  │   ├─ NO → Run: export REGISTRY_AUTH_FILE="$HOME/.config/containers/auth.json"
  │   └─ YES → Continue
  ├─ Does auth.json exist?
  │   ├─ NO → Re-run setup-rootless-podman-auth.sh
  │   └─ YES → Continue
  ├─ Is auth.json owned by current user?
  │   ├─ NO (root:root) → Re-run setup-rootless-podman-auth.sh
  │   └─ YES → Continue
  └─ Are credentials valid?
      ├─ NO → Regenerate service account at access.redhat.com
      └─ YES → Check network connectivity to registry.redhat.io

Build fails with "Permission denied on /run/user/1001/crun"
  ├─ Is directory owned by root?
  │   ├─ YES → Run: sudo rm -rf /run/user/1001/crun
  │   └─ NO → Check SELinux denials
  └─ Retry build

Build succeeds locally but fails in CI/CD
  ├─ Is REGISTRY_AUTH_FILE exported in CI environment?
  │   ├─ NO → Add to workflow env block
  │   └─ YES → Continue
  └─ Is auth.json accessible in CI container?
      ├─ NO → Mount ~/.config/containers as volume
      └─ YES → Check CI user UID matches auth.json owner
```

## Appendix B: CentOS Stream 10 Specific Considerations

### Podman 5.x Architectural Changes

- **Default Runtime**: `crun` (not `runc`)
- **Rootless Networking**: `pasta` (replaces `slirp4netns`)
- **Storage Driver**: `overlay` with `fuse-overlayfs` for rootless
- **User Namespace**: Requires `/etc/subuid` and `/etc/subgid` configuration

### Known Issues

**Issue**: `newuidmap: open of uid_map failed: Permission denied`

**Cause**: User namespace limits exceeded

**Fix**: Increase limit:
```bash
sudo sysctl -w user.max_user_namespaces=15000
echo "user.max_user_namespaces=15000" | sudo tee -a /etc/sysctl.conf
```

## Appendix C: Implementation Checklist

- [x] Create remediation script (`setup-rootless-podman-auth.sh`)
- [x] Update `playbooks/build-custom-ee.yml` with `become: false`
- [x] Update `ansible.cfg` documentation (when to use `become`)
- [x] Create `docs/PODMAN_ENVIRONMENT_SETUP.md` troubleshooting guide
- [x] Add GitHub Actions workflow with `REGISTRY_AUTH_FILE` export
- [ ] Test script on fresh CentOS Stream 10 VM
- [ ] Document in main README.md
- [ ] Create video walkthrough for team training
- [ ] Add to onboarding documentation
- [ ] Integrate with AAP custom credential types

---

**Last Updated**: 2026-06-09  
**Reviewed By**: Infrastructure Team  
**Next Review**: 2026-09-09 (Quarterly)
