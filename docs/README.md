# Testing the OpenShift Disconnected Helper with Molecule

This document explains how to use Molecule to test the Ansible playbooks in the `playbooks/` directory of the OpenShift Disconnected Helper project. It covers the testing methodology, setup, execution, and interpretation of results.

## Overview

The testing framework uses Molecule to automate the provisioning, configuration, and verification of the disconnected environment setup. It leverages Vagrant as a driver and Libvirt as the provider to create virtual machines for testing. The tests are defined using Ansible playbooks and verified using Testinfra.

## Test Structure

The Molecule tests are organized as follows:

-   **`molecule/`**: Root directory for Molecule tests
    -   **`test-plan.yml`**: Defines the overall test plan and scenarios.
    -   **`default/`**: Contains the default test scenario.
        -   **`molecule.yml`**: Main Molecule configuration file. Defines the driver, platforms, provisioner, verifier, and test sequences.
        -   **`prepare.yml`**: Playbook to prepare the test environment (e.g., install prerequisites, create directories).
        -   **`converge.yml`**: Playbook that includes and executes the Ansible playbooks from the `playbooks/` directory.
        -   **`verify.yml`**: Playbook that contains Testinfra tests to verify the system state after convergence.
        -   **`cleanup.yml`**: Playbook to clean up the test environment after tests are completed.
        -   **`destroy.yml`**: Playbook to destroy the test environment.
    -   **`README.md`**: This file, providing instructions on using the Molecule tests.

## Prerequisites

Before running the tests, ensure you have the following prerequisites installed:

1. **Ansible**: `pip install ansible`
2. **Molecule**: `pip install molecule molecule-vagrant python-vagrant`
3. **Vagrant**: [https://www.vagrantup.com/downloads](https://www.vagrantup.com/downloads)
4. **Libvirt**: Install the libvirt development package for your OS (e.g., `libvirt-devel` on Fedora/CentOS/RHEL, `libvirt-dev` on Debian/Ubuntu)
5. **Vagrant Libvirt Provider**: `vagrant plugin install vagrant-libvirt`
6. **Test dependencies**: `pip install -r requirements.txt` (where `requirements.txt` contains `molecule`, `molecule-vagrant`, `python-vagrant`)

## System Requirements

-   At least 16GB RAM (32GB recommended)
-   At least 200GB free disk space
-   A Linux-based host system (tested on Fedora, CentOS, and RHEL)

## How Molecule Tests the Playbooks

The Molecule tests are designed to thoroughly validate the functionality of the Ansible playbooks located in the `playbooks/` directory. Here's how it works:

1. **Converge Playbook (`converge.yml`)**:
    
    -   This playbook is the heart of the testing process. It's responsible for executing the playbooks that set up the disconnected environment.
    -   It uses the `include_tasks` module to dynamically include and run the playbooks from the `playbooks/` directory.
    -   For example, to test the Quay registry setup, it includes `../../playbooks/setup-quay-registry.yml`.
    -   Similarly, for content mirroring, it executes commands defined in `download-to-tar.yml` and `push-tar-to-registry.yml`.
2. **Provisioner Configuration (`molecule.yml`)**:
    
    -   The `molecule.yml` file configures the Ansible provisioner, which controls how playbooks are executed.
    -   The `playbooks` section defines the paths to playbooks used in different test phases.
    -   The `env` section sets `ANSIBLE_ROLES_PATH` to `../../roles`, allowing Ansible to find custom roles used by the playbooks.
3. **Inventory and Group Variables (`molecule.yml`)**:
    
    -   The `inventory` section defines group variables for different host groups (`registry_hosts`, `mirror_hosts`).
    -   These variables can be used in playbooks to customize behavior based on the target host.
    -   For instance, `setup-quay-registry.yml` can use variables specific to `registry_hosts`.
4. **Test Scenarios (`molecule.yml` and `test-plan.yml`)**:
    
    -   The `test_sequence` in `molecule.yml` defines the order of steps for the default test scenario.
    -   Each step corresponds to a specific playbook or action.
    -   The `converge` step executes `converge.yml`, which includes the relevant playbooks from `playbooks/`.
    -   `test-plan.yml` outlines the overall testing strategy and maps scenarios to playbooks and verification steps.
5. **Verification (`verify.yml`)**:
    
    -   After the `converge` step, the `verify.yml` playbook uses Testinfra to assert the system's state.
    -   It verifies that the playbooks in `playbooks/` have correctly configured the system by checking:
        -   Service status (e.g., Quay container, PostgreSQL)
        -   File existence and content (e.g., configuration files, SSL certificates)
        -   Network connectivity (e.g., registry health endpoint)
        -   Command outputs (e.g., `oc-mirror` results)
6. **Test Plan (`test-plan.yml`)**:
    
    -   Provides a high-level overview of the testing strategy.
    -   Maps test scenarios to specific playbooks and verification steps.
    -   Ensures comprehensive coverage of all components and workflows.

## Running the Tests

1. **Run the complete test suite:**
    
    ```bash
    molecule test
    
    ```
    
    This command executes all test scenarios defined in the `test_sequence` of `molecule.yml`.
    
2. **Run individual test phases:**
    
    ```bash
    # Create the test environment (VMs)
    molecule create
    
    # Prepare the environment (install prerequisites)
    molecule prepare
    
    # Run the convergence playbooks
    molecule converge
    
    # Verify the system state
    molecule verify
    
    # Clean up the environment (but keep VMs running)
    molecule cleanup
    
    # Destroy the test environment (stop and delete VMs)
    molecule destroy
    
    ```
    
3. **Run a specific test scenario:**
    
    ```bash
    molecule test -s [scenario_name]
    
    ```
    
    Replace `[scenario_name]` with the name of the scenario defined in `test-plan.yml` (e.g., `full-deployment-with-quay`).
    

## Interpreting Test Results

-   Molecule outputs detailed logs during test execution, which can be found in the `.molecule/default/` directory.
-   The `verify.yml` playbook generates a verification report at `/tmp/verification_report.txt` on each test VM.
-   The `cleanup.yml` playbook generates a cleanup report at `/tmp/cleanup_report.txt` on each test VM.
-   Successful test runs will show all tests passing in the Molecule output.
-   Failed tests will indicate which assertion failed and provide relevant error messages.

## Troubleshooting

1. **If tests fail:**
    
    -   Examine the Molecule logs in `.molecule/default/`.
    -   Check the verification and cleanup reports on the test VMs.
    -   Use `molecule login` to SSH into a test VM and investigate the issue.
    -   Increase verbosity with `molecule --debug test`.
2. **Common issues:**
    
    -   Insufficient system resources (memory, disk space).
    -   Network connectivity problems between VMs or to external resources.
    -   Vagrant/Libvirt configuration issues.
    -   Errors in Ansible playbooks or Testinfra tests.
3. **Manual cleanup:**
    
    ```bash
    # Force cleanup and destroy VMs
    molecule destroy
    
    # Remove Molecule's temporary directory
    rm -rf .molecule/
    
    ```
    

## Extending the Tests

To add new test scenarios or expand existing ones:

1. **Create a new scenario directory:**
    
    ```bash
    molecule init scenario [new_scenario_name]
    
    ```
    
2. **Modify the scenario files:**
    
    -   `molecule/[new_scenario_name]/molecule.yml`: Configure the scenario (e.g., platforms, provisioner settings).
    -   `molecule/[new_scenario_name]/prepare.yml`: Add any scenario-specific preparation steps.
    -   `molecule/[new_scenario_name]/converge.yml`: Define how the scenario invokes the playbooks being tested.
    -   `molecule/[new_scenario_name]/verify.yml`: Add Testinfra assertions to validate the scenario.
    -   `molecule/[new_scenario_name]/cleanup.yml`: Define cleanup steps for the scenario.
3. **Update `test-plan.yml`:**
    
    -   Add the new scenario to the `test_scenarios` section.
    -   Describe the scenario's purpose and verification points.
4. **Test the new scenario:**
    
    ```bash
    molecule test -s [new_scenario_name]
    
    ```
    

By following this structure, you can ensure that the OpenShift Disconnected Helper playbooks are thoroughly tested and function as expected in various deployment scenarios.
