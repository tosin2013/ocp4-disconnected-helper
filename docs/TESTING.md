# Testing Guide for ocp4-disconnected-helper

## Overview

This project uses a **multi-layered testing strategy** to ensure infrastructure automation quality:

1. **Role Unit Testing** (Molecule) — Fast feedback for role logic (seconds)
2. **Syntax/Lint Validation** (ansible-test) — YAML and module correctness (<1 minute)
3. **E2E Workflow Testing** (AAP Workflows) — Full deployment validation (45-90 minutes)

**Current Coverage**: v1.3.0 target is 80% test coverage via Molecule + ansible-test.

---

## Role Testing with Molecule

### Prerequisites

**Required**:
- Molecule 26.4.0+ (`pip install 'molecule[podman]'`)
- Podman 5.8.2+ (CentOS Stream 10: `sudo dnf install podman`)
- Ansible collections: `containers.podman` (1.20+), `ansible.posix`

**Installation**:
```bash
pip install 'molecule[podman]' molecule-plugins ansible-lint
ansible-galaxy collection install containers.podman ansible.posix
```

**Verification**:
```bash
molecule --version  # Should show 26.4.0+
podman --version    # Should show 5.8.2+
```

---

### Quick Start

**Run Full Test Cycle** (create → converge → verify → destroy):
```bash
cd roles/common_vm
molecule test
```

**Incremental Development Workflow**:
```bash
molecule create     # Create test container
molecule converge   # Run role
molecule verify     # Run test assertions
molecule destroy    # Clean up

# Shortcut: converge automatically creates if needed
molecule converge   # Create + run role
```

**List Test Scenarios**:
```bash
molecule list
```

---

### Platform Configuration

**Driver**: Podman (rootful — see Security Caveat below)  
**Base Image**: `registry.access.redhat.com/ubi9/ubi-init:latest` (systemd support)  
**Connection**: Direct `podman exec` commands (not SSH)  
**Supported Scenarios**: Default scenario in each role's `molecule/default/` directory

---

### ⚠️ Security Caveat: Rootful Podman Requirement

**Issue**: Rootless Podman is fundamentally broken on CentOS Stream 10 + Podman 5.8.2 due to UID mapping failures.

**Symptoms**:
```
Error: newuidmap: open of uid_map failed: Permission denied
Error: crun: creating uid map: Invalid argument
```

**Root Cause**:
- Podman tries to map container UID 0 → host UID 1001 (vpcuser)
- newuidmap utility from shadow-utils **explicitly rejects** this mapping
- Podman forbids including the user's own UID in `/etc/subuid`

**Current Workaround** (v1.3.0):
All Molecule playbooks use **rootful Podman with `sudo`**:
- `sudo podman pull` — Pull container images
- `sudo podman run` — Create test containers
- `sudo podman exec` — Execute commands inside containers
- `sudo podman rm` — Clean up containers

**Security Trade-offs**:
- ❌ Requires sudo access (violates least-privilege)
- ❌ Container escapes could compromise host
- ✅ Isolated to development/CI (not production workloads)
- ✅ Enables functional testing for 80% coverage goal

**Future Resolution** (v1.4.0):
When upgrading to **CentOS Stream 11+** or **RHEL 10**, re-test rootless Podman:
```bash
# Test command (without sudo)
podman pull quay.io/centos/centos:stream9

# If successful, migrate Molecule playbooks back to rootless
# by removing `sudo` from create.yml and destroy.yml
```

**Tracking**: GitHub Issue [#36](https://github.com/tosin2013/ocp4-disconnected-helper/issues/36)  
**Documentation**: See ADR-0036 for full technical analysis

---

### Test Scenario Structure

Each role has a `molecule/` directory with test scenarios:

```
roles/common_vm/
├── molecule/
│   └── default/              # Default test scenario
│       ├── molecule.yml      # Platform and driver config
│       ├── create.yml        # Container provisioning
│       ├── converge.yml      # Role execution
│       ├── verify.yml        # Test assertions
│       └── destroy.yml       # Cleanup
```

**Key Files**:

**molecule.yml** — Platform configuration:
```yaml
platforms:
  - name: instance
    image: registry.access.redhat.com/ubi9/ubi-init:latest
    command: /usr/sbin/init
    privileged: true  # Required for systemd
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw
    tmpfs:
      /run: ""
      /tmp: ""
```

**create.yml** — Container creation (uses `sudo` due to UID mapping issue):
```yaml
- name: Pull container image
  ansible.builtin.command:
    cmd: sudo podman pull {{ item.image }}
  loop: "{{ molecule_yml.platforms }}"
```

**converge.yml** — Role execution:
```yaml
- name: Test basic Ansible execution
  ansible.builtin.command:
    cmd: sudo podman exec instance /usr/bin/cat /etc/os-release
  register: os_release
```

**verify.yml** — Test assertions:
```yaml
- name: Verify systemd is running
  ansible.builtin.command:
    cmd: sudo podman exec instance systemctl is-system-running
  register: systemd_status
  failed_when: systemd_status.rc != 0
```

---

### Writing Tests for Roles

**Test Scenarios for common_vm** (example):

1. **Static IP Configuration**:
   - Verify cloud-init network-config v2 syntax
   - Validate gateway4 vs routes configuration
   - Check DNS servers JSON formatting

2. **DHCP Configuration**:
   - Verify `dhcp4: true` is set
   - Validate absence of static IP parameters

3. **Cloud-init ISO Creation**:
   - Verify ISO file exists at expected path
   - Check ISO contains user-data and meta-data

4. **Error Handling**:
   - Missing required variables (vm_name, vm_memory, vm_cpus)
   - Invalid network configuration (both static and DHCP)
   - Unsupported cloud_init_network_mode

**Example Test** (verify.yml):
```yaml
---
- name: Verify
  hosts: localhost
  gather_facts: false
  tasks:
    - name: Verify container is running
      ansible.builtin.command:
        cmd: sudo podman ps --filter name=instance --format '{{.Status}}'
      register: container_status
      changed_when: false

    - name: Assert container is running
      ansible.builtin.assert:
        that:
          - "'Up' in container_status.stdout"
        fail_msg: "Container is not running"
        success_msg: "Container is running"

    - name: Verify systemd is active
      ansible.builtin.command:
        cmd: sudo podman exec instance systemctl is-system-running
      register: systemd_status
      changed_when: false
      failed_when: systemd_status.rc not in [0, 1]  # 0=running, 1=degraded (acceptable)

    - name: Display systemd state
      ansible.builtin.debug:
        msg: "Systemd state: {{ systemd_status.stdout }}"
```

---

### Troubleshooting

#### Error: `newuidmap: Permission denied`

**Cause**: Rootless Podman UID mapping failure (CentOS Stream 10 + Podman 5.8.2)

**Fix**: Verify Molecule playbooks use `sudo` for all Podman commands:
```bash
# Check create.yml and destroy.yml
grep -n "sudo podman" roles/common_vm/molecule/default/create.yml
```

**Verification**:
```bash
# This should FAIL (rootless broken):
podman pull quay.io/centos/centos:stream9

# This should SUCCEED (rootful works):
sudo podman pull quay.io/centos/centos:stream9
```

---

#### Error: `crun: executable file '/usr/sbin/init' not found`

**Cause**: Base container image doesn't include systemd

**Fix**: Use `*-init` variant of base images:
```yaml
# ❌ Wrong
image: quay.io/centos/centos:stream9

# ✅ Correct
image: registry.access.redhat.com/ubi9/ubi-init:latest
```

---

#### Error: `UNREACHABLE! Failed to create temporary directory`

**Cause**: Ansible connection plugin incompatible with rootful containers

**Fix**: Use direct `podman exec` commands instead of connection plugin:
```yaml
# ❌ Wrong (uses connection plugin)
- name: Test
  hosts: instance
  tasks:
    - ansible.builtin.command: whoami

# ✅ Correct (direct exec)
- name: Test
  hosts: localhost
  tasks:
    - ansible.builtin.command:
        cmd: sudo podman exec instance whoami
```

---

#### Error: `Unsupported parameters: force`

**Cause**: containers.podman v1.20+ changed parameter name

**Fix**: Use `force_delete` instead of `force`:
```yaml
# ❌ Wrong
containers.podman.podman_container:
  force: true

# ✅ Correct
containers.podman.podman_container:
  force_delete: true

# ✅ Best (direct command)
ansible.builtin.command:
  cmd: sudo podman rm -f {{ item.name }}
```

---

#### Container Doesn't Start with Systemd

**Cause**: Missing required mounts for systemd in containers

**Fix**: Add cgroup mounts and tmpfs:
```yaml
platforms:
  - name: instance
    privileged: true  # Required for systemd
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:rw  # Required
    tmpfs:
      /run: ""   # Required for systemd sockets
      /tmp: ""   # Required for temp files
```

---

## Syntax and Lint Validation

**ansible-test** validates playbook syntax without execution.

### Quick Validation

**All Playbooks**:
```bash
ansible-test sanity --test validate-modules
ansible-test sanity --test yamllint
```

**Specific Playbook**:
```bash
ansible-playbook --syntax-check playbooks/site.yml
ansible-lint playbooks/site.yml
```

### Common Issues

**Undefined Variables**:
```yaml
# ❌ Wrong
- name: Use variable
  ansible.builtin.debug:
    msg: "{{ my_var }}"

# ✅ Correct
- name: Use variable
  ansible.builtin.debug:
    msg: "{{ my_var | default('default_value') }}"
```

**Deprecated Modules**:
```yaml
# ❌ Wrong
- name: Copy file
  copy:
    src: file.txt
    dest: /tmp/file.txt

# ✅ Correct
- name: Copy file
  ansible.builtin.copy:
    src: file.txt
    dest: /tmp/file.txt
```

---

## E2E Workflow Testing

**AAP Workflows** provide full deployment validation (45-90 minutes).

**Scope**:
- Complete infrastructure provisioning (VyOS + Registry + AAP)
- Operator mirroring with validation
- Multi-node AAP deployment
- Full integration testing

**Documentation**: See ADR-0033 (AAP Workflow Validation Framework)

**When to Use**:
- Pre-release validation
- Major architectural changes
- Production deployment rehearsal

**Complement, Not Replace**: Molecule tests provide fast feedback; AAP workflows validate full system.

---

## CI/CD Integration

### GitHub Actions Workflow (Future)

**Trigger**: Pull requests and pushes to main

**Jobs**:
1. **Syntax Check** (1 minute):
   - ansible-test sanity
   - ansible-lint
   - YAML validation

2. **Role Tests** (5 minutes):
   - Molecule test for changed roles
   - Parallel execution via matrix builds

3. **E2E Validation** (90 minutes, scheduled):
   - AAP workflow execution (nightly or on-demand)

**Example Workflow**:
```yaml
name: Ansible Testing

on:
  pull_request:
    paths:
      - 'roles/**'
      - 'playbooks/**'
      - '**.yml'

jobs:
  molecule:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        role: [common_vm, registry_vm]
    steps:
      - uses: actions/checkout@v4
      
      - name: Install Podman
        run: |
          sudo apt-get update
          sudo apt-get install -y podman
      
      - name: Install Molecule
        run: pip install 'molecule[podman]' molecule-plugins
      
      - name: Run Molecule Tests
        run: |
          cd roles/${{ matrix.role }}
          molecule test
```

---

## Pre-commit Hooks

**Install**:
```bash
pip install pre-commit
pre-commit install
```

**Configuration** (.pre-commit-config.yaml):
```yaml
repos:
  - repo: https://github.com/ansible/ansible-lint
    rev: v24.2.0
    hooks:
      - id: ansible-lint
        files: \.(yml|yaml)$
        args: [--fix]

  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: check-yaml
      - id: end-of-file-fixer
      - id: trailing-whitespace
```

---

## Test Coverage Goals

**v1.3.0 Target**: 80% test coverage

**Breakdown**:
- **Role Tests** (Molecule): 60% (covers common_vm, registry_vm, openshift_cluster_deploy)
- **Syntax/Lint** (ansible-test): 20% (covers all 26 playbooks)
- **E2E Workflows** (AAP): Not counted toward coverage (integration validation)

**Progress Tracking**:
```bash
# Count roles with Molecule tests
find roles/ -name molecule.yml | wc -l

# Count playbooks with lint validation
ansible-lint playbooks/*.yml | grep -c "passed"

# Calculate coverage
echo "scale=2; ($roles_tested / $total_roles) * 100" | bc
```

---

## Best Practices

### Role Testing Patterns

1. **Test Idempotence**: Run converge twice, second run should show 0 changed
2. **Test Error Conditions**: Verify graceful failure on invalid inputs
3. **Test Dependencies**: Mock role dependencies in test scenarios
4. **Test Delegated Tasks**: Verify libvirt delegation works correctly

### Naming Conventions

- **Scenarios**: `default`, `static-ip`, `dhcp`, `error-handling`
- **Test Files**: `verify.yml`, not `test.yml` (Molecule convention)
- **Assertions**: Use `ansible.builtin.assert` for clear failure messages

### Performance Optimization

- **Cache Base Images**: Pull once, reuse across tests
- **Parallel Scenarios**: Use Molecule's parallel execution
- **Incremental Testing**: Run only changed roles in CI

---

## References

- **Molecule Documentation**: https://molecule.readthedocs.io/
- **ansible-test Guide**: https://docs.ansible.com/ansible/latest/dev_guide/testing.html
- **Podman Documentation**: https://docs.podman.io/
- **ADR-0036**: Molecule Framework Adoption (this project)
- **ADR-0033**: AAP Workflow Validation (E2E testing)
- **GitHub Issue #36**: Rootless Podman limitation tracking
