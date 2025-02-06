#!/bin/bash

# --- Configuration ---
# Default configurations
REGISTRY_TYPE="${1:-quay}"  # Supported: quay, harbor, jfrog
SKIP_VALIDATION="${2:-no}"
DESTROY_VMS="no"

# Validate registry type
validate_registry_type() {
  case "$REGISTRY_TYPE" in
    quay|harbor|jfrog)
      return 0
      ;;
    *)
      echo "Error: Invalid registry type. Supported types: quay, harbor, jfrog"
      exit 1
      ;;
  esac
}

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

# Function to ensure sshpass is installed
ensure_sshpass() {
  if ! command -v sshpass &> /dev/null; then
    echo "[INFO] Installing sshpass..."
    if command -v apt-get &> /dev/null; then
      sudo apt-get update && sudo apt-get install -y sshpass
    elif command -v dnf &> /dev/null; then
      sudo dnf install -y sshpass
    elif command -v yum &> /dev/null; then
      sudo yum install -y sshpass
    else
      echo "[ERROR] Package manager not found. Please install sshpass manually."
      exit 1
    fi
  fi
}

# Function to deploy registry infrastructure
deploy_registry() {
  echo "Deploying ${REGISTRY_TYPE} infrastructure..."
  
  # Ensure sshpass is installed
  ensure_sshpass
  
  # Provision VM with registry-specific configuration
  echo "[INFO] Provisioning ${REGISTRY_TYPE} VM..."
  ansible-playbook playbooks/provision-registry-vm.yml \
    -e "registry_type=${REGISTRY_TYPE}" \
    -e "@vars/rh_secrets.yml"
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] Failed to provision ${REGISTRY_TYPE} VM."
    exit 1
  fi
  
echo "[INFO] Setting up ${REGISTRY_TYPE} prerequisites..."
case "$REGISTRY_TYPE" in
  quay)
    ansible-playbook -i playbooks/inventory/quay playbooks/setup-quay-only.yml \
      -e "@playbooks/vars/quay-vars.yml" \
      -e "@vars/rh_secrets.yml"

    echo "[INFO] Installing mirror-registry..."
    # Get Quay VM IP from inventory
    QUAY_IP=$(grep -A1 '\[quay\]' playbooks/inventory/quay | tail -n1 | awk '{print $1}')
    if [ -z "$QUAY_IP" ]; then
      echo "[ERROR] Failed to get Quay host IP from inventory"
      exit 1
    fi

    # Run mirror-registry installation directly via SSH using sshpass
    SSHPASS='redhat' sshpass -e ssh -o StrictHostKeyChecking=no root@$QUAY_IP \
      "cd /root/mirror-registry && ./mirror-registry install --quayHostname=quay.example.com --initUser=admin --initPassword=redhat123 --ssh-key=/root/.ssh/quay_installer"
    if [ $? -ne 0 ]; then
      echo "[ERROR] Failed to install mirror-registry"
      exit 1
    fi

    # Update local hosts file
    echo "[INFO] Updating local /etc/hosts file..."
    if ! grep -q "quay.example.com" /etc/hosts; then
      echo "$QUAY_IP quay.example.com" | sudo tee -a /etc/hosts > /dev/null
    else
      sudo sed -i "s/.*quay\.example\.com/$QUAY_IP quay.example.com/" /etc/hosts
    fi
      
    # Verify Quay health
      if ! REGISTRY_HOST=$(grep -A1 '\[quay\]' playbooks/inventory/quay | tail -n1 | awk '{print $1}'); then
        echo "[ERROR] Failed to get Quay host from inventory."
        exit 1
      fi
      
      for i in {1..30}; do
        if curl -k -s "https://${REGISTRY_HOST}:8443/health/endtoend" | grep -q "\"status\": \"healthy\""; then
          echo "[SUCCESS] Quay registry is healthy"
          break
        fi
        if [ $i -eq 30 ]; then
          echo "[ERROR] Quay registry health check failed"
          exit 1
        fi
        echo "Attempt $i: Waiting for Quay to be ready..."
        sleep 10
      done
      ;;
      
    harbor)
      ansible-playbook playbooks/setup-harbor-registry.yml \
        -e "@extra_vars/setup-harbor-registry-vars.yml" \
        -e "@vars/rh_secrets.yml"
      ;;
      
    jfrog)
      ansible-playbook playbooks/setup-jfrog-registry.yml \
        -e "@extra_vars/setup-jfrog-registry-vars.yml" \
        -e "@vars/rh_secrets.yml"
      ;;
  esac
  
  if [[ $? -ne 0 ]]; then
    echo "[ERROR] Failed to deploy ${REGISTRY_TYPE} registry."
    exit 1
  fi
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

# Validate registry type
validate_registry_type

# Deploy selected registry
deploy_registry

# Push tar files to registry
push_to_registry

echo "All operations completed successfully."
exit 0
