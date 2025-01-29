#!/bin/bash

# --- Configuration ---
# Allow users to specify the test scenario (default: full deployment with Quay)
TEST_SCENARIO="${1:-quay}"

# Allow users to specify whether to skip environment validation (default: no)
SKIP_VALIDATION="${2:-no}"

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

# Function to run a specific test scenario
run_test_scenario() {
  local scenario="$1"
  case "$scenario" in
    quay)
      echo "Running full deployment with Quay..."
      molecule test -s default -- --tags "quay"
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

# Validate the environment
validate_environment

# Run the selected test scenario
run_test_scenario "$TEST_SCENARIO"

echo "End-to-end tests completed successfully."
exit 0
