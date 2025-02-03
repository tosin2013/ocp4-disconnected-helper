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

# Function to deploy Quay registry
deploy_quay() {
  echo "Deploying Quay infrastructure..."
  
  # First provision the VM using KVM provisioner
  echo "[INFO] Provisioning VM for Quay..."
  ansible-playbook -i localhost, playbooks/provision-quay-vm.yml -e "@extra_vars/setup-quay-registry-vars.yml" --connection=local
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] Failed to provision VM for Quay."
    exit 1
  fi
  
  # Wait for VM to be ready
  echo "[INFO] Waiting for VM to be ready..."
  sleep 30
  
  # Run the Quay setup playbook against the provisioned VM
  echo "[INFO] Setting up Quay registry..."
  ansible-playbook -i inventory/quay playbooks/setup-quay-registry.yml -e "@extra_vars/setup-quay-registry-vars.yml"
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] Failed to setup Quay registry."
    exit 1
  fi
  
  # Verify Quay is running
  echo "[INFO] Verifying Quay registry..."
  QUAY_HOST=$(grep -A1 '\[quay\]' inventory/quay | tail -n1)
  if ! curl -k -s "https://${QUAY_HOST}:8443/health/instance" | grep -q "healthy"; then
    echo "[ERROR] Quay registry health check failed."
    exit 1
  fi
  
  echo "[SUCCESS] Quay registry deployed and verified"
}

# Function to push tar files to registry
push_to_registry() {
  echo "Running push-tar-to-registry playbook..."
  ansible-lint playbooks/push-tar-to-registry.yml
  if [[ $? -ne 0 ]]; then
    echo "Ansible lint failed for push-tar-to-registry playbook."
    exit 1
  fi

  echo "Pushing tar files to registry..."
  ansible-playbook -i localhost, playbooks/push-tar-to-registry.yml -e "@extra_vars/push-tar-to-registry-vars.yml" --connection=local
  if [[ $? -ne 0 ]]; then
    echo "Failed to push tar files to registry."
    exit 1
  fi
}

# Function to check for existing valid tar files
check_existing_tars() {
  echo "Checking for existing OpenShift tar files..."
  TARGET_PATH="/opt/images"
  FOUND_OPENSHIFT=false
  
  # Check if directory exists and is accessible
  if [ ! -d "${TARGET_PATH}" ]; then
    return 1
  fi
  
  # Check if any tar files exist
  TAR_COUNT=$(find ${TARGET_PATH} -maxdepth 1 -name "*.tar" 2>/dev/null | wc -l)
  if [ "$TAR_COUNT" -eq 0 ]; then
    return 1
  fi
  
  echo "[INFO] Found ${TAR_COUNT} tar files in ${TARGET_PATH}"
  
  # Check each tar file
  while read -r tarfile; do
    # Check if file is a valid tar archive
    if ! tar tf "${tarfile}" &> /dev/null; then
      return 1
    fi
    
    # Check for OpenShift content
    if tar tf "${tarfile}" | grep -q "release.images" || tar tf "${tarfile}" | grep -q "openshift"; then
      FOUND_OPENSHIFT=true
      SIZE=$(du -h "${tarfile}" | cut -f1)
      echo "[INFO] Found valid OpenShift tar file: $(basename ${tarfile}) (${SIZE})"
    fi
  done < <(find ${TARGET_PATH} -maxdepth 1 -name "*.tar" 2>/dev/null)
  
  if [ "${FOUND_OPENSHIFT}" = "true" ]; then
    echo "[SUCCESS] Valid OpenShift tar files found, skipping download"
    return 0
  fi
  
  return 1
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

# Check for existing tar files and run download if needed
if ! check_existing_tars; then
  echo "[INFO] No valid OpenShift tar files found, running download-to-tar playbook..."
  run_download_tar
else
  echo "[INFO] Using existing tar files"
fi

# Validate the tar files
validate_tar_files

# Deploy Quay registry
deploy_quay

# Push tar files to registry
push_to_registry

echo "All operations completed successfully."
exit 0
