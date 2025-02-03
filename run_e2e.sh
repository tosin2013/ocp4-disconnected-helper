#!/bin/bash

# --- Configuration ---
# Allow users to specify the test scenario (default: full deployment with Quay)
TEST_SCENARIO="${1:-quay}"

# Allow users to specify whether to skip environment validation (default: no)
SKIP_VALIDATION="${2:-no}"

# Allow users to specify whether to destroy VMs after tests (default: no)
DESTROY_VMS="no"

# --- Functions ---

# Function to validate the environment
validate_environment() {
  if [[ "$SKIP_VALIDATION" == "no" ]]; then
    echo "Validating environment..."
    ./validate_env.sh
    if [[ $? -ne 0 ]]; then
      echo "Environment validation failed."
      exit 1
    fi
  else
    echo "Skipping environment validation."
  fi
}

# Function to run download-tar playbook with linting
run_download_tar() {
  echo "Running ansible-lint on download-to-tar playbook..."
  ansible-lint playbooks/download-to-tar.yml
  if [[ $? -ne 0 ]]; then
    echo "Ansible lint failed for download-to-tar playbook."
    exit 1
  fi

  echo "Running download-to-tar playbook..."
  ansible-playbook -i localhost, playbooks/download-to-tar.yml -e "@extra_vars/download-to-tar-vars.yml" -e "rh_pull_secret=/home/lab-user/pullsecret.json" --connection=local
  if [[ $? -ne 0 ]]; then
    echo "download-to-tar playbook failed."
    exit 1
  fi
}

# Function to run a specific test scenario
run_test_scenario() {
  local scenario="$1"
  local destroy_vms="$2"

  # Run download-tar first
  run_download_tar

  case "$scenario" in
    quay)
      echo "Running full deployment with Quay..."
      if [[ "$destroy_vms" == "yes" ]]; then
        molecule test -s default -- --tags "quay" -e "destroy_vms=true"
      else
        molecule test -s default -- --tags "quay"
      fi
      ;;
    harbor)
      echo "Running full deployment with Harbor..."
      molecule test -s default -- --tags "harbor"
      ;;
    jfrog)
      echo "Running full deployment with JFrog..."
      molecule test -s default -- --tags "jfrog"
      ;;
    *)
      echo "Invalid test scenario: $scenario"
      exit 1
      ;;
  esac

  if [[ $? -ne 0 ]]; then
    echo "Test scenario '$scenario' failed."
    exit 1
  fi
}

# --- Main Script ---

# Parse command line options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--destroy)
      DESTROY_VMS="yes"
      shift
      ;;
    *)
      break
      ;;
  esac
done

# Validate the environment
validate_environment

# Run the selected test scenario
run_test_scenario "$TEST_SCENARIO" "$DESTROY_VMS"

echo "End-to-end tests completed successfully."
exit 0
