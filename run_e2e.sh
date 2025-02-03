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

# Function to validate OpenShift tar files
validate_tar_files() {
  echo "Validating OpenShift tar files..."
  TARGET_PATH="/opt/images"
  FOUND_OPENSHIFT=false
  
  # Check if directory exists and is accessible
  if [ ! -d "${TARGET_PATH}" ]; then
    echo "[ERROR] Directory ${TARGET_PATH} does not exist"
    exit 1
  fi
  
  # Check if any tar files exist (only in the main directory)
  TAR_COUNT=$(find ${TARGET_PATH} -maxdepth 1 -name "*.tar" 2>/dev/null | wc -l)
  if [ "$TAR_COUNT" -eq 0 ]; then
    echo "[ERROR] No tar files found in ${TARGET_PATH}"
    exit 1
  fi
  
  echo "[INFO] Found ${TAR_COUNT} tar files in ${TARGET_PATH}"
  
  # Validate each tar file
  while read -r tarfile; do
    echo "[INFO] Checking tar file: $(basename ${tarfile})"
    
    # Check if file is a valid tar archive
    if ! tar tf "${tarfile}" &> /dev/null; then
      echo "[ERROR] Invalid tar file: ${tarfile}"
      exit 1
    fi
    
    # Get and display the size
    SIZE=$(du -h "${tarfile}" | cut -f1)
    echo "[SUCCESS] Valid tar file: $(basename ${tarfile}) (${SIZE})"
    
    # Check the contents for OpenShift-related files
    if tar tf "${tarfile}" | grep -q "release.images" || tar tf "${tarfile}" | grep -q "openshift"; then
      echo "[SUCCESS] File contains OpenShift content: $(basename ${tarfile})"
      FOUND_OPENSHIFT=true
    fi
  done < <(find ${TARGET_PATH} -maxdepth 1 -name "*.tar" 2>/dev/null)
  
  # Check if we found any OpenShift content
  if [ "${FOUND_OPENSHIFT}" != "true" ]; then
    echo "[ERROR] No OpenShift content found in tar files"
    exit 1
  fi
  
  echo "[SUCCESS] Tar file validation completed successfully"
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

# Run the download-tar function
# run_download_tar

# Validate the tar files
validate_tar_files

echo "Download-tar and validation completed successfully."
exit 0
