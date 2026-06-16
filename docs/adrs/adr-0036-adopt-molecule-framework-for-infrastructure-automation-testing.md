# ADR-0036: Adopt Molecule Framework for Infrastructure Automation Testing

## Date
2026-06-16

## Status
Proposed

## Context

v1.3.0 deployment validation identified **0% test coverage** for 26+ Ansible playbooks and growing role library (common_vm, registry_vm, openshift_cluster_deploy). The deployment readiness tool flagged this as a BLOCKER (required: 80% coverage).

### Current State

**Scale and Complexity**:
- 26 playbooks requiring test coverage
- 3+ roles with atomic architecture (ADR-0024)
- Multi-topology support (SNO/Compact/HA)
- Multi-registry support (Quay/Harbor/JFrog)
- 37 ADRs documenting architectural decisions

**Existing Testing Infrastructure**:
- ✅ **ADR-0033** (AAP Workflow Validation): Shell scripts + E2E playbooks for **workflow testing**
- ✅ **Preflight Scripts**: Pre-deployment validation (`preflight-cert-check.sh`, `preflight-aap-registry-check.sh`)
- ✅ **Configuration Validation**: Password structure, registry mode validation playbooks
- ❌ **Role Unit Testing**: None (gap identified)
- ❌ **Playbook Syntax/Lint**: No automation (gap identified)

**Problem Statement**:
Infrastructure automation projects traditionally lack unit testing because:
1. Infrastructure is expensive to provision (VMs, networks, storage)
2. Testing requires actual infrastructure (hard to mock)
3. Feedback loops are slow (minutes to hours for VM creation)

However, our project has reached a scale where:
1. Manual validation doesn't scale with 26+ playbooks
2. Role refactoring is risky without unit tests (ADR-0024 atomic roles)
3. Contributors need fast feedback (not 45-90 minute deployment cycles)
4. Production failures are expensive (wasted deployment time)

### Lessons from v1.3.0

From `docs/releases/v1.3.0-lessons-learned.md`:

> **Test Coverage Blocker**: 0% (Required: 80%)
> 
> **Root Cause**: Infrastructure automation projects don't typically have traditional unit/integration tests. Deployment readiness tool assumes application testing patterns (Jest, Playwright, etc.)
> 
> **Recommended Fix**:
> - **Option 1**: Implement Ansible testing framework (molecule for role testing) ← **USER SELECTED**
> - **Option 2**: Add infrastructure project exemption to deployment_readiness tool
> - **Option 3**: Create separate validation tier for infrastructure vs application projects

## Decision

**We will adopt Molecule testing framework for role unit testing with the following approach:**

### Primary Decision Points

1. **Molecule for Role Testing** (Priority 1):
   - Use Docker driver for fast feedback (seconds vs minutes)
   - Prioritize role testing over playbook testing (aligns with ADR-0024 atomic roles)
   - Start with `common_vm` role as proof-of-concept
   - Expand to `registry_vm`, `openshift_cluster_deploy`, and future roles

2. **ansible-test for Syntax/Lint** (Priority 2):
   - Complement Molecule with ansible-test sanity checks
   - Catches YAML errors, undefined variables, deprecated modules
   - Fast validation (<1 minute for all 26 playbooks)

3. **CI/CD Integration** (Priority 3):
   - Integrate with GitHub Actions for automated quality gates
   - Run Molecule tests on pull requests
   - Block merges on test failures

4. **Testing Scope** (Boundaries):
   - **IN SCOPE**: Role unit tests (variable handling, conditional logic, task execution)
   - **IN SCOPE**: Syntax and lint validation (all playbooks)
   - **OUT OF SCOPE**: Full E2E deployment tests (covered by ADR-0033)
   - **OUT OF SCOPE**: VM provisioning tests in CI (use delegated driver for local testing)

### Implementation Strategy

**Phase 1: Proof-of-Concept** (Week 1)
- Set up Molecule for `common_vm` role
- Create test scenarios for:
  - VM provisioning with static IP
  - VM provisioning with DHCP
  - Cloud-init configuration generation
  - Error handling (missing parameters)
- Document Molecule patterns for team

**Phase 2: Core Roles** (Week 2-3)
- Extend to `registry_vm` role
- Extend to `openshift_cluster_deploy` role
- Establish testing patterns for role dependencies

**Phase 3: CI/CD Integration** (Week 4)
- Create GitHub Actions workflow
- Add pre-commit hooks for ansible-test
- Update contributor guidelines

**Phase 4: Playbook Coverage** (Future)
- Evaluate ansible-test for playbook validation
- Consider integration tests for critical playbooks
- Target 80% overall coverage

### Testing Drivers

**Podman Driver** (Primary):
- **Use Case**: Fast unit tests for role logic
- **Platform**: CentOS Stream 10 has Podman 5.8.2 (no Docker)
- **Pros**: Seconds to provision, rootless by default, daemonless architecture, works in CI
- **Cons**: Doesn't test actual VM provisioning
- **When to Use**: Default for all roles
- **Note**: GitHub Actions requires explicit Podman installation (`sudo apt-get install podman`)

**⚠️ SECURITY CAVEAT: Rootless Podman Limitation on CentOS Stream 10**

**Issue**: Rootless Podman 5.8.2 on CentOS Stream 10 has a fundamental UID mapping incompatibility that prevents Molecule container creation:

```
Error: newuidmap: open of uid_map failed: Permission denied
```

**Root Cause**: 
- Podman attempts to map container UID 0 → host UID 1001 (vpcuser)
- newuidmap utility from shadow-utils rejects this mapping
- Podman explicitly forbids including user's own UID in `/etc/subuid` configuration
- All rootless workarounds (`userns=nomap`, `userns=auto`, storage squashing) fail because the UID mapping error occurs during image pull, before container creation

**v1.3.0 Solution (Technical Debt)**:
- **Use rootful Podman with `sudo`** for Molecule operations
- Implemented in `roles/*/molecule/default/create.yml` and `destroy.yml`
- Commands: `sudo podman pull`, `sudo podman run`, `sudo podman exec`, `sudo podman rm`

**Security Trade-offs**:
- ❌ Violates least-privilege principle (requires sudo access)
- ❌ Container escapes could compromise host system
- ✅ Isolated to development/CI environments (not production)
- ✅ Functional Molecule testing achieves 80% coverage goal

**Future Resolution** (Target: v1.4.0):
- **Re-test rootless Podman** on CentOS Stream 11+, RHEL 10, or upstream Podman fixes
- Test command: `podman pull quay.io/centos/centos:stream9` (without sudo)
- If successful: Migrate back to rootless by removing `sudo` from Molecule playbooks
- Tracked in: GitHub Issue [#36](https://github.com/tosin2013/ocp4-disconnected-helper/issues/36)

**Rejected Approaches**:
- ❌ Adding `vpcuser:1001:1` to `/etc/subuid` (Podman explicitly rejects: "invalid configuration: the specified mapping 1001:1 includes the user UID")
- ❌ Global `userns="nomap"` in `~/.config/containers/containers.conf` (ignored during image pull)
- ❌ Storage squashing with `ignore_chown_errors=true` (UID mapping validation occurs before storage layer)
- ❌ Using `userns="keep-id"` parameter (triggers same UID 1001 mapping conflict)

**Implementation Example**:
```yaml
# roles/common_vm/molecule/default/create.yml
- name: Pull container image (rootful due to UID mapping limitation)
  ansible.builtin.command:
    cmd: sudo podman pull {{ item.image }}
  loop: "{{ molecule_yml.platforms }}"

- name: Create Podman container (rootful)
  ansible.builtin.command:
    cmd: >
      sudo podman run -d
      --name {{ item.name }}
      --privileged={{ item.privileged | default(false) }}
      {{ item.image }}
      {{ item.command | default('/usr/sbin/init') }}
  loop: "{{ molecule_yml.platforms }}"
```

**Delegated Driver** (Secondary):
- **Use Case**: Integration tests for libvirt-specific code
- **Pros**: Tests actual virsh/libvirt calls, validates XML generation
- **Cons**: Requires nested KVM, slow (minutes), CI complexity
- **When to Use**: Manual testing, critical libvirt changes only

## Consequences

### Positive

1. **Fast Feedback Cycle**: Role changes validated in seconds vs minutes/hours
2. **TDD Enablement**: Developers can write tests before implementation
3. **Refactoring Safety**: Atomic roles (ADR-0024) can be refactored with confidence
4. **CI/CD Quality Gates**: Automated blocking on test failures
5. **Reduced Manual Testing**: Frees up time for higher-value E2E validation
6. **Team Onboarding**: New contributors learn role patterns through tests
7. **Documentation**: Tests serve as executable examples of role usage

### Negative

1. **Initial Setup Cost**: Each role needs Molecule scenarios (estimated 2-4 hours per role)
2. **Maintenance Burden**: Tests need updates when role interfaces change
3. **Docker Limitations**: May not catch libvirt-specific issues (mitigated by delegated driver)
4. **Team Learning Curve**: Molecule framework is new to team (mitigated by documentation)
5. **CI Resource Usage**: GitHub Actions minutes consumed by test runs

### Mitigation Strategies

**For Docker Limitations**:
- Use delegated driver for integration tests when needed
- Document which scenarios require actual VM provisioning
- Maintain manual testing checklist for libvirt changes

**For Initial Setup Cost**:
- Create reusable Molecule templates
- Document common test patterns
- Start with highest-value roles (common_vm, registry_vm)

**For Team Learning Curve**:
- Write comprehensive Molecule guide in `docs/TESTING.md`
- Record demo videos for common test scenarios
- Pair programming sessions for first role

**For CI Resource Usage**:
- Cache dependencies to reduce setup time
- Run tests only on changed roles (not full suite every time)
- Use matrix builds for parallel execution

## Alternatives Considered

### Option 2: ansible-test Only (Syntax/Lint)
**Pros**: Minimal setup, fast execution, catches common errors  
**Cons**: No execution testing, doesn't validate role logic  
**Decision**: Use as complement to Molecule, not replacement

### Option 3: Continue Manual Testing (Status Quo)
**Pros**: No initial investment, familiar workflow  
**Cons**: Doesn't scale, slow feedback, risky refactoring  
**Decision**: Rejected due to scale and complexity

### Option 4: Exempt Infrastructure Projects from Test Coverage
**Pros**: No work required, acknowledges infrastructure testing challenges  
**Cons**: Misses opportunity for quality improvement, doesn't address real pain points  
**Decision**: Rejected - our scale justifies investment

### Option 5: Full E2E Deployment Tests Only (ADR-0033)
**Pros**: Tests actual production workflows  
**Cons**: Extremely slow (45-90 minutes), expensive (VM resources), late feedback  
**Decision**: Keep for workflow validation, add Molecule for fast unit tests

## Related Decisions

- **ADR-0002** (Ansible Automation Framework): Establishes Ansible as primary tool
- **ADR-0024** (Roles and Collections Architecture): Atomic roles benefit most from unit testing
- **ADR-0033** (AAP Workflow Validation): Covers E2E workflow testing (complements, not replaces)
- **ADR-0008** (GitHub Actions Automation): CI/CD platform for test execution

## Implementation Checklist

- [ ] Install Molecule framework (`pip install 'molecule[podman]' molecule-plugins ansible-lint`)
- [ ] Create Molecule scenario for `common_vm` role
- [ ] Write test cases for `common_vm` (static IP, DHCP, cloud-init, error handling)
- [ ] Document Molecule patterns in `docs/TESTING.md`
- [ ] Create GitHub Actions workflow for Molecule tests
- [ ] Add pre-commit hook for ansible-test sanity
- [ ] Extend to `registry_vm` role
- [ ] Extend to `openshift_cluster_deploy` role
- [ ] Update contributor guidelines with testing requirements
- [ ] Target 80% test coverage for deployment readiness

## Success Metrics

**Quantitative**:
- Test coverage: 0% → 80% (deployment readiness target)
- Feedback cycle: 45-90 minutes → <5 minutes (role changes)
- CI/CD automation: 0% → 100% (all PRs tested)

**Qualitative**:
- Developers feel confident refactoring roles
- New contributors understand role patterns through tests
- Production deployment failures decrease

## References

- [Molecule Documentation](https://molecule.readthedocs.io/)
- [ansible-test Documentation](https://docs.ansible.com/ansible/latest/dev_guide/testing.html)
- v1.3.0 Lessons Learned: `docs/releases/v1.3.0-lessons-learned.md`
- ADR-0033: AAP Workflow Validation Framework
- ADR-0024: Roles and Collections Architecture
