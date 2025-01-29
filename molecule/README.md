# Molecule Tests for OpenShift Disconnected Helper

This directory contains Molecule tests for validating the OpenShift disconnected deployment system.

## Test Structure

- `test-plan.yml` - Master test plan defining all test scenarios
- `default/` - Default test scenario
  - `molecule.yml` - Molecule configuration
  - `prepare.yml` - Environment preparation
  - `converge.yml` - Test execution
  - `verify.yml` - Test assertions
  - `cleanup.yml` - Environment cleanup

## Prerequisites

1. Install test dependencies using `dnf` and `pip`:
```bash
sudo dnf install -y python3-pip python3-devel gcc libffi-devel openssl-devel
pip3 install --user molecule molecule-vagrant python-vagrant
```

2. Ensure system requirements:
   - Vagrant >= 2.2.14
   - Libvirt >= 8.0.0 with KVM
   - Ansible >= 2.14.0
   - RHEL 9.5 (Plow)
   - At least 16GB RAM available (32GB recommended)
   - At least 200GB free disk space
   - All required Ansible collections installed:
     ```bash
     ansible-galaxy collection install community.general:>=6.4.0 community.libvirt:>=1.9.1 ansible.posix:>=1.5.4 containers.podman:>=1.10.1
     ```

## Running Tests

1. Run complete test suite:
```bash
molecule test
```

2. Run individual phases:
```bash
# Create test environment
molecule create

# Prepare environment
molecule prepare

# Run tests
molecule converge

# Verify results
molecule verify

# Cleanup
molecule cleanup
```

3. Run specific scenario:
```bash
molecule test -s [scenario_name]
```

## Test Scenarios

### 1. Full Deployment with Quay
Tests complete deployment process using Quay registry:
- Environment validation
- VM provisioning
- Quay registry setup
- Content mirroring
- Disconnected validation

### 2. Full Deployment with Harbor
Same as above but using Harbor registry

### 3. Full Deployment with JFrog
Same as above but using JFrog registry

### 4. Isolated Component Tests
Individual testing of:
- Bootstrap script
- Environment validation
- KVM provisioner
- Registry playbooks
- Content mirroring

## Verification Points

1. Environment Setup:
   - System prerequisites
   - Ansible environment
   - KVM infrastructure
   - Network configuration

2. Registry Deployment:
   - Container deployment
   - SSL configuration
   - Storage setup
   - Authentication
   - Health checks

3. Content Mirroring:
   - oc-mirror functionality
   - Content validation
   - Manifest verification
   - Registry synchronization

## Test Reports

- Test results are stored in `.molecule/default/`
- Verification report: `/tmp/verification_report.txt`
- Cleanup report: `/tmp/cleanup_report.txt`

## Troubleshooting

1. If tests fail, check:
   - System resources (memory, disk space)
   - Network connectivity
   - Libvirt/KVM status
   - Molecule logs in `.molecule/default/`

2. Common issues:
   ```bash
   # Check Molecule status
   molecule status

   # Debug test environment
   molecule login

   # View Molecule logs
   molecule --debug test
   ```

3. Manual cleanup:
   ```bash
   # Force cleanup
   molecule destroy
   
   # Clean Molecule cache
   rm -rf .molecule/
   ```

## Adding New Tests

1. Create new scenario:
```bash
molecule init scenario [name]
```

2. Add test files:
   - `molecule/[scenario_name]/molecule.yml`: Defines platforms, providers, and scenario-specific settings.
   - `molecule/[scenario_name]/prepare.yml`: Prepares the environment, updated to use `dnf` for package management on RHEL 9.5.
   - `molecule/[scenario_name]/converge.yml`: Executes the main playbooks, adjusted for RHEL 9.5 compatibility.
   - `molecule/[scenario_name]/verify.yml`: Contains Testinfra tests to verify the system state.
   - `molecule/[scenario_name]/cleanup.yml`: Cleans up resources after tests are completed.
   - `molecule/[scenario_name]/destroy.yml`: Destroys the test environment.

3. Update test plan:
   - Add new scenario to `test-plan.yml`
   - Define verification points
   - Add cleanup procedures
