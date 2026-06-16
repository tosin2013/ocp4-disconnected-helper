# Contributing to ocp4-disconnected-helper

Thank you for your interest in contributing to the OpenShift Disconnected Helper project! This guide will help you get started with development, testing, and submitting contributions.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Workflow](#development-workflow)
- [Testing Requirements](#testing-requirements)
- [Submitting Changes](#submitting-changes)
- [Coding Standards](#coding-standards)
- [Architecture Decisions](#architecture-decisions)

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/0/code_of_conduct/). By participating, you are expected to uphold this code. Please report unacceptable behavior to the project maintainers.

---

## Getting Started

### Prerequisites

- **Operating System**: CentOS Stream 10 or RHEL 10 compatible
- **Ansible**: 2.16.18 or later
- **Python**: 3.12 or later
- **Podman**: 5.8.2 or later (rootless mode)
- **Molecule**: 26.4.0 or later
- **Git**: 2.x

### Clone the Repository

```bash
git clone https://github.com/your-org/ocp4-disconnected-helper.git
cd ocp4-disconnected-helper
```

### Install Development Dependencies

```bash
# Install Ansible and collections
pip install ansible-core molecule[podman] molecule-plugins[podman]
ansible-galaxy collection install containers.podman ansible.posix

# Install linting tools
pip install ansible-lint yamllint
```

### Install Pre-commit Hook

The project includes a security pre-commit hook that blocks commits containing hardcoded credentials:

```bash
# Pre-commit hook is already installed if you cloned the repo
# Verify it exists:
ls -l .git/hooks/pre-commit

# If missing, copy from scripts:
cp scripts/pre-commit-hook.sh .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

---

## Development Workflow

### 1. Create a Feature Branch

```bash
git checkout -b feature/your-feature-name
```

Use descriptive branch names:
- `feature/operator-validation-caching`
- `fix/registry-certificate-permissions`
- `docs/aap-workflow-guide`

### 2. Make Your Changes

Follow the [Coding Standards](#coding-standards) section below.

### 3. Test Your Changes

**Run Molecule tests for affected roles:**

```bash
cd roles/common_vm
molecule test  # Full test cycle

# Or run specific test steps:
molecule converge  # Apply role
molecule verify    # Run assertions only
molecule destroy   # Clean up
```

**Run linting checks:**

```bash
yamllint .
ansible-lint roles/
```

### 4. Commit Your Changes

```bash
git add <files>
git commit -m "type: brief description

Detailed explanation of what changed and why.

- Bullet points for multiple changes
- Reference ADRs or issues if applicable

Closes #123"
```

**Commit message format:**
- `feat:` New feature
- `fix:` Bug fix
- `test:` Add or update tests
- `docs:` Documentation changes
- `ci:` CI/CD pipeline changes
- `refactor:` Code refactoring
- `chore:` Maintenance tasks

### 5. Push and Create Pull Request

```bash
git push origin feature/your-feature-name
```

Open a pull request on GitHub with:
- Clear title and description
- Reference to related issues or ADRs
- Test results (if applicable)

---

## Testing Requirements

### Molecule Testing Framework

All Ansible roles **must** include Molecule test scenarios. The project uses a rootless Podman driver with `userns: "nomap"` configuration (see ADR-0036).

**Minimum test coverage requirements:**
- **Core orchestration**: 100% (main.yml task flow)
- **Templates**: 100% (Jinja2 template validation)
- **Overall role coverage**: ≥60%

**Example test structure:**

```bash
roles/my_role/
├── molecule/
│   ├── default/           # Basic lifecycle test
│   ├── edge-case/         # Error handling tests
│   └── idempotence/       # Idempotency verification
```

### Required Test Scenarios

1. **default**: Basic role execution (provision → configure → verify)
2. **idempotence**: Second run produces zero changes
3. **error-handling**: Graceful degradation on failures

### Running Tests Locally

```bash
# Test a specific role
cd roles/registry_vm
molecule test -s default

# Test all scenarios in a role
molecule test --all

# Parallel execution (faster)
molecule test -s default & molecule test -s certificates & wait
```

### CI/CD Validation

Pull requests automatically trigger:
- Molecule tests for changed roles
- Ansible sanity checks (ansible-lint, yamllint)
- Security scanning (pre-commit hooks)

**CI must pass before merge.**

---

## Submitting Changes

### Pull Request Checklist

Before submitting your PR, ensure:

- [ ] Code follows project conventions (see [Coding Standards](#coding-standards))
- [ ] Molecule tests added for new roles or major changes
- [ ] All tests pass locally (`molecule test`)
- [ ] Documentation updated (README, ADRs, inline comments where needed)
- [ ] Commit messages follow format guidelines
- [ ] No hardcoded credentials or secrets
- [ ] Pre-commit hook passes
- [ ] ADR created for architectural changes (see [Architecture Decisions](#architecture-decisions))

### Review Process

1. **Automated Checks**: CI/CD runs Molecule tests, linting, and security scans
2. **Maintainer Review**: Project maintainers review code quality and architecture fit
3. **Feedback Loop**: Address review comments via additional commits
4. **Merge**: Maintainer merges after approval

---

## Coding Standards

### Ansible Best Practices

1. **Idempotency**: Tasks must be safe to run multiple times
   ```yaml
   # ✅ Good: Idempotent
   - name: Create directory
     ansible.builtin.file:
       path: /opt/data
       state: directory
       mode: '0755'

   # ❌ Bad: Not idempotent
   - name: Create directory
     ansible.builtin.command:
       cmd: mkdir /opt/data
   ```

2. **Atomic Roles**: Follow ADR-0024 atomic roles pattern
   - One role = one responsibility
   - Use `import_role` for delegation (e.g., `common_vm` for VM provisioning)

3. **Variable Naming**:
   - Role-specific prefix: `registry_port`, `aap_admin_password`
   - Boolean flags: `vm_use_static_ip`, `force_refresh`
   - No generic names: `port`, `password`, `enabled`

4. **Task Naming**:
   - Imperative form: "Install mirror-registry", "Verify certificate permissions"
   - Not "Installing...", "Checking if..."

5. **Error Handling**:
   ```yaml
   - name: Download installer
     ansible.builtin.get_url:
       url: "{{ installer_url }}"
       dest: "/tmp/installer.tar.gz"
     register: download_result
     failed_when: download_result.status_code != 200
     retries: 3
     delay: 10
   ```

### YAML Style

- **Indentation**: 2 spaces (no tabs)
- **Quote style**: Use single quotes for simple strings, double quotes for variables
  ```yaml
  name: 'Static string'
  dest: "{{ dynamic_path }}/file.txt"
  ```
- **Line length**: Maximum 120 characters
- **Blank lines**: One blank line between tasks for readability

### Security Guidelines

1. **Never commit credentials**:
   - Use Ansible Vault: `extra_vars/rhel-subscription-secrets.yml`
   - Environment variables: `lookup('env', 'API_TOKEN')`
   - Placeholders in documentation: `<YOUR-PASSWORD-HERE>`

2. **Certificate handling**:
   - Private keys: 0600 permissions, owner-only
   - Certificates: 0644 permissions, world-readable
   - Self-signed CA: Install in system trust store

3. **Pre-commit hook enforcement**:
   - Automatically blocks commits with pattern matches for secrets
   - Do **not** use `--no-verify` to bypass (fix the issue instead)

---

## Architecture Decisions

### When to Create an ADR

Create an Architecture Decision Record (ADR) when:
- Adding a new technology or framework
- Changing deployment architecture
- Making security or compliance decisions
- Establishing new patterns or conventions

### ADR Template

```markdown
# ADR-XXXX: Title of Decision

## Date
YYYY-MM-DD

## Status
Proposed | Accepted | Deprecated | Superseded by ADR-YYYY

## Context
What problem are we solving? What constraints exist?

## Decision
What did we decide to do?

## Consequences
### Positive
- Benefit 1
- Benefit 2

### Negative
- Trade-off 1
- Mitigation strategy

## Alternatives Considered
### Option A
...

### Option B (Rejected)
...

## References
- Link 1
- Link 2
```

### Existing ADRs

Review relevant ADRs before contributing:
- **ADR-0024**: Atomic Roles Architecture
- **ADR-0033**: AAP Workflow Validation Framework
- **ADR-0034**: Operator Catalog Validation
- **ADR-0036**: Molecule Testing Framework

See `docs/adrs/` for the complete list.

---

## Getting Help

- **Documentation**: Check `docs/TESTING.md` for testing guide
- **Issues**: Search existing GitHub issues
- **Discussions**: Open a GitHub discussion for questions
- **Maintainers**: Tag `@maintainers` in PRs for urgent reviews

---

## License

By contributing, you agree that your contributions will be licensed under the same license as the project (MIT License).

---

**Thank you for contributing to ocp4-disconnected-helper!** 🚀
