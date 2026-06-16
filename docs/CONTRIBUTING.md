# Contributing to ocp4-disconnected-helper

Thank you for contributing! This guide covers testing requirements, development workflow, and best practices.

---

## Testing Requirements

All code changes must include tests. We use **Molecule** for role-level testing and **ansible-test** for sanity checks.

### Test Coverage Targets

| Component | Coverage Target | Status |
|-----------|----------------|--------|
| Ansible Roles | 80% | 🔄 In Progress |
| Playbooks | Syntax validation | ✅ Implemented |
| Templates | 100% | ✅ Implemented |

### Running Tests Locally

#### 1. Role Tests (Molecule)

```bash
# Install Molecule
pip install molecule[podman] molecule-plugins[podman]
pip install ansible-core

# Install collections
ansible-galaxy collection install containers.podman
ansible-galaxy collection install ansible.posix

# Run all tests for a role
cd roles/common_vm
molecule test

# Run specific scenario
molecule test --scenario-name static-ip

# Development workflow
molecule create    # Create test container
molecule converge  # Run role
molecule verify    # Run tests
molecule destroy   # Clean up
```

**Available Test Scenarios** (common_vm role):
- `default`: Basic role execution
- `static-ip`: Static IP network configuration
- `dhcp`: DHCP network configuration
- `error-handling`: Graceful error degradation
- `libvirt-xml`: VM domain XML validation
- `mac-address`: MAC generation and uniqueness
- `idempotence`: Ansible idempotence validation

#### 2. Syntax Checks

```bash
# YAML linting
pip install yamllint
yamllint playbooks/ roles/ inventory/

# Ansible linting
pip install ansible-lint
ansible-lint playbooks/ roles/

# Playbook syntax check
ansible-playbook --syntax-check playbooks/site.yml \
  -i inventory/ibm-cloud.yml
```

#### 3. Security Checks

```bash
# Check for hardcoded secrets (pre-commit hook)
.git/hooks/pre-commit

# Verify vault encryption
grep -q "\$ANSIBLE_VAULT" extra_vars/rhel-subscription-secrets.yml
```

---

## Development Workflow

### 1. Create Feature Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make Changes

Follow project conventions (see CLAUDE.md):
- Use atomic roles pattern (ADR-0024)
- Store secrets in Ansible Vault (ADR-0009)
- Document decisions in ADRs (docs/adrs/)

### 3. Write Tests

**For new roles**:
```bash
cd roles/your_role
molecule init scenario default --driver-name podman
# Edit molecule/default/molecule.yml, converge.yml, verify.yml
```

**For new features**:
- Add test scenario in `molecule/<scenario-name>/`
- Write assertions in `verify.yml`
- Test edge cases (error handling, validation)

### 4. Run Tests Locally

```bash
# Run Molecule tests
cd roles/your_role
molecule test

# Run sanity checks
yamllint roles/your_role/
ansible-lint roles/your_role/
```

### 5. Commit Changes

```bash
git add .
git commit -m "type: description"
```

**Commit message format**:
```
<type>: <description>

<optional body>

<optional footer>
```

**Types**:
- `feat`: New feature
- `fix`: Bug fix
- `test`: Add/update tests
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `chore`: Maintenance tasks

**Examples**:
```
feat: Add MAC address uniqueness validation to common_vm role

test: Add idempotence scenario for common_vm role

Validates that re-running the role produces zero changes when state
is already correct. Uses Molecule's double-converge test sequence.
```

### 6. Push and Create PR

```bash
git push origin feature/your-feature-name
# Create PR on GitHub
```

---

## CI/CD Pipeline

All PRs trigger automated testing via GitHub Actions:

### Molecule Tests (`.github/workflows/molecule-test.yml`)

- **Trigger**: Changes to `roles/**`
- **Runs**: All 7 test scenarios for affected roles
- **Runtime**: ~2 minutes per role
- **Fail Conditions**:
  - Template syntax errors
  - Assertion failures in verify.yml
  - Idempotence violations (2nd converge has changes)
  - XML validation failures (libvirt domain)

### Ansible Sanity (`.github/workflows/ansible-sanity.yml`)

- **Trigger**: Changes to `playbooks/`, `roles/`, `inventory/`
- **Checks**:
  - YAML syntax (yamllint)
  - Ansible best practices (ansible-lint)
  - Playbook syntax validation
  - Role metadata validation
  - Security scan (hardcoded secrets)
- **Runtime**: ~1 minute

### Required Checks

PRs must pass:
- ✅ All Molecule tests for changed roles
- ✅ YAML and Ansible linting
- ✅ Playbook syntax validation
- ✅ Security scan (no hardcoded secrets)

---

## Writing Good Tests

### Molecule Test Scenarios

**Structure**:
```
roles/your_role/molecule/<scenario>/
├── molecule.yml      # Platform and driver configuration
├── converge.yml      # Role execution with test variables
└── verify.yml        # Assertions and validation
```

**Best Practices**:

1. **Test ONE thing per scenario**
   - ❌ BAD: Test static IP + DHCP + error handling in one scenario
   - ✅ GOOD: Separate scenarios for each network mode

2. **Use descriptive scenario names**
   - ❌ BAD: `test1`, `test2`, `test3`
   - ✅ GOOD: `static-ip`, `dhcp`, `error-handling`

3. **Write comprehensive assertions**
   ```yaml
   # verify.yml
   - name: Assert network-config has static IP
     ansible.builtin.assert:
       that:
         - network_config.network.version == 2
         - network_config.network.ethernets.eth0.dhcp4 == false
         - network_config.network.ethernets.eth0.addresses | length > 0
       fail_msg: "Static IP not configured correctly"
       success_msg: "✓ Static IP configuration valid"
   ```

4. **Test edge cases**
   - Missing required variables
   - Invalid input formats
   - Empty/null values
   - Boundary conditions

5. **Validate template output**
   ```yaml
   - name: Validate YAML syntax
     ansible.builtin.command:
       cmd: "python3 -c 'import yaml; yaml.safe_load(open(\"{{ file }}\"))'"
     changed_when: false

   - name: Validate XML syntax
     ansible.builtin.command:
       cmd: "xmllint --noout {{ xml_file }}"
     changed_when: false
   ```

6. **Document expected behavior**
   ```yaml
   # converge.yml
   ---
   # Tests MAC address generation logic
   # Expected: Same vm_name always produces same MAC (deterministic)
   # Expected: Different vm_names produce unique MACs (no collisions)
   ```

### Test Coverage Guidelines

**Priority 1** (MUST test):
- Template rendering (all code paths)
- Idempotence (2x converge = 0 changes)
- Error handling (graceful degradation)
- Security (no credential leakage)

**Priority 2** (SHOULD test):
- Variable validation
- Conditional logic
- File permissions
- Service health checks

**Priority 3** (NICE to test):
- Performance benchmarks
- Multi-platform compatibility
- Integration with external services

---

## Code Review Guidelines

### For Reviewers

✅ **Approve if**:
- All CI checks pass
- Tests cover new code paths
- Documentation updated
- Follows project conventions

❌ **Request changes if**:
- Missing tests
- Hardcoded secrets
- Breaking changes without ADR
- Test coverage <80% for new roles

### For Contributors

**Respond to feedback promptly**:
- Address all review comments
- Re-request review after changes
- Explain design decisions if questioned

**Merge requirements**:
- 1 approving review from maintainer
- All CI checks passing
- No unresolved conversations
- Branch up-to-date with main

---

## Troubleshooting

### Molecule Tests Fail in CI but Pass Locally

**Cause**: Rootless Podman UID mapping differences

**Fix**: Verify `userns: "nomap"` in create.yml (see ADR-0036)

```yaml
# roles/*/molecule/*/create.yml
containers.podman.podman_container:
  userns: "nomap"  # Required for CentOS Stream 10
```

### yamllint Errors on Long Lines

**Cause**: Template expressions or long strings

**Fix**: Add `# yamllint disable-line rule:line-length`

```yaml
very_long_variable: "{{ some_complex_template_expression }}"  # yamllint disable-line rule:line-length
```

### ansible-lint False Positives

**Fix**: Add `.ansible-lint` ignore rule or inline comment

```yaml
# .ansible-lint
skip_list:
  - no-changed-when  # We use changed_when: false explicitly
```

### Security Scan Blocks Commit

**Cause**: Pre-commit hook detected potential secrets

**Fix**:
1. Replace real credentials with placeholders
2. Store secrets in Ansible Vault
3. Never use `--no-verify` to bypass

```bash
# Encrypt secrets
ansible-vault encrypt extra_vars/rhel-subscription-secrets.yml \
  --vault-password-file ~/.vault_pass
```

---

## Getting Help

- **Documentation**: See `docs/` directory
- **ADRs**: Check `docs/adrs/` for architectural decisions
- **Issues**: Open GitHub issue for bugs/feature requests
- **Testing Guide**: See `docs/TESTING.md` for detailed Molecule usage

---

## Project Structure

```
ocp4-disconnected-helper/
├── roles/                  # Ansible roles (atomic pattern)
│   ├── common_vm/
│   │   ├── molecule/       # Test scenarios
│   │   │   ├── default/
│   │   │   ├── static-ip/
│   │   │   ├── dhcp/
│   │   │   ├── error-handling/
│   │   │   ├── libvirt-xml/
│   │   │   ├── mac-address/
│   │   │   └── idempotence/
│   │   ├── tasks/
│   │   ├── templates/
│   │   └── meta/
│   └── registry_vm/
├── playbooks/              # Ansible playbooks
├── inventory/              # Inventory files
├── extra_vars/             # Variable files
├── docs/                   # Documentation
│   ├── adrs/               # Architecture decisions
│   ├── TESTING.md          # Testing guide
│   └── CONTRIBUTING.md     # This file
├── .github/
│   └── workflows/          # CI/CD pipelines
├── .yamllint.yml           # YAML linting config
└── .ansible-lint           # Ansible linting config (TBD)
```

---

## License

This project is licensed under the MIT License. By contributing, you agree to license your contributions under the same license.

---

**Thank you for contributing!** 🎉

Your tests and code reviews help maintain the quality and reliability of this project for enterprise disconnected OpenShift deployments.
