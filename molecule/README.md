# Molecule Testing

This directory contains Molecule test scenarios for the OpenShift Disconnected Helper project. The tests validate the deployment of various container registries and content mirroring functionality.

## Test Scenarios

1. **Default Scenario (Quay)**
   - Tests Quay registry deployment
   - Validates basic functionality
   - Checks content mirroring

2. **Harbor Scenario**
   - Tests Harbor registry deployment
   - Validates Harbor-specific features
   - Checks content mirroring

3. **JFrog Scenario**
   - Tests JFrog Artifactory deployment
   - Validates JFrog-specific features
   - Checks content mirroring

## Running Tests

To run all tests:
```bash
./run_all_molecule_tests.sh
```

To run a specific scenario:
```bash
molecule test -s [scenario_name]
```

## Test Structure

Each scenario follows these phases:
1. Create - Provisions test instances
2. Prepare - Sets up prerequisites
3. Converge - Deploys and configures services
4. Verify - Runs validation tests
5. Cleanup - Removes test artifacts
6. Destroy - Tears down test instances

## Configuration

- All scenarios use Podman driver for containerization
- Test instances are configured with appropriate resource limits
- Network and storage are properly isolated
