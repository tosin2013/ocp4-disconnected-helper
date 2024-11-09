#!/bin/bash
# sudo -E ./cicd.sh  -d false -g mjffm -h PASSWORD -p false -r true
# sudo -E ./cicd.sh  -d true -g mjffm -h PASSWORD -p false -r false
#  sudo -E ./cicd.sh  -d false -g mjffm -h PASSWORD -p true -r false
CODE_DIR="/home/lab-user/workspace/ocp4-disconnected-helper/"

# Function to display help menu
show_help() {
  echo "Usage: $0 [-d DOWNLOAD_TO_TAR] [-p PUSH_TAR_TO_REGISTRY] [-g GUID] [-h HARBOR_PASSWORD] [-r DELETE_DOWNLOADED_FILE]"
  echo
  echo "Options:"
  echo "  -d    Set to 'true' to enable downloading images to TAR."
  echo "  -p    Set to 'true' to enable pushing TAR images to the registry."
  echo "  -g    Specify the GUID for the operation."
  echo "  -r    Remove files in /opt/images."
  echo "  -h    Provide the Harbor password."
  echo
  echo "Example:"
  echo "  $0 -d true -p true -g YOUR_GUID -h YOUR_HARBOR_PASSWORD"
  echo
  exit 0
}

# Parse command-line arguments
while getopts "d:p:g:r:h:" opt; do
  case ${opt} in
    d) DOWNLOAD_TO_TAR="${OPTARG}" ;;
    p) PUSH_TAR_TO_REGISTRY="${OPTARG}" ;;
    g) GUID="${OPTARG}" ;;
    r) DELETE_DOWNLOADED_FILE="${OPTARG}" ;;
    h) HARBOR_PASSWORD="${OPTARG}" ;;
    \?) show_help ;;  # Show help on invalid option
    *) show_help ;;   # Show help if any other option is encountered
  esac
done

# If no arguments are provided, show help menu
if [ "$OPTIND" -eq 1 ]; then
  show_help
fi

# This script checks if the current user has root privileges.
# If the user is not root (EUID is not 0), it sets the USE_SUDO variable to "sudo".
# This allows subsequent commands to be run with sudo if necessary.
if [ "$EUID" -ne 0 ]
then
  export USE_SUDO="sudo"
fi


# Check required arguments
# This code block checks if the DOWNLOAD_TO_TAR variable is empty.
# If it is empty:
#   1. It prints an error message stating that the DOWNLOAD_TO_TAR argument is required.
#   2. It exits the script with a status code of 1, indicating an error.
#
# Variables used:
# - DOWNLOAD_TO_TAR: Expected to contain a boolean value indicating whether to download images to TAR.
#
# Note: This check ensures that the DOWNLOAD_TO_TAR argument is provided before proceeding with the script.
if [ -z "$DOWNLOAD_TO_TAR" ]; then
    echo "DOWNLOAD_TO_TAR argument is required."
    exit 1
fi

# This code block checks if the PUSH_TAR_TO_REGISTRY variable is empty.
# If it is empty:
#   1. It prints an error message stating that the PUSH_TAR_TO_REGISTRY argument is required.
#   2. It exits the script with a status code of 1, indicating an error.
#
# Variables used:
# - PUSH_TAR_TO_REGISTRY: Expected to contain a boolean value indicating whether to push TAR files to the registry.
#
# Note: This check ensures that the PUSH_TAR_TO_REGISTRY argument is provided before proceeding with the script.
if [ -z "$PUSH_TAR_TO_REGISTRY" ]; then
    echo "PUSH_TAR_TO_REGISTRY argument is required."
    exit 1
fi

# This code block checks if the GUID variable is empty.
# If it is empty:
#   1. It prints an error message stating that the GUID argument is required.
#   2. It exits the script with a status code of 1, indicating an error.
#
# Variables used:
# - GUID: Expected to contain a unique identifier for the operation.
#
# Note: This check ensures that the GUID is provided before proceeding with the script.
if [ -z "$GUID" ]; then
    echo "GUID argument is required."
    exit 1
fi

# This code block checks if the HARBOR_PASSWORD variable is empty.
# If it is empty:
#   1. It prints an error message stating that the HARBOR_PASSWORD argument is required.
#   2. It exits the script with a status code of 1, indicating an error.
#
# Variables used:
# - HARBOR_PASSWORD: Expected to contain the password for the Harbor registry.
#
# Note: This check ensures that the HARBOR_PASSWORD is provided before proceeding with operations that might require it.
if [ -z "$HARBOR_PASSWORD" ]; then
    echo "HARBOR_PASSWORD argument is required."
    exit 1
fi


# This code block checks for the existence of a default.env file and sources it along with helper functions.
# If the file exists:
#   1. It sources the default.env file, which likely contains environment variables.
#   2. It then sources the helper_functions.sh file, which probably contains utility functions.
# If the file doesn't exist:
#   1. It prints an error message.
#   2. It exits the script with a status code of 1, indicating an error.
#
# Variables used:
# - None explicitly defined in this block.
#
# Files referenced:
# - /opt/kcli-pipelines/helper_scripts/default.env
# - /opt/kcli-pipelines/helper_scripts/helper_functions.sh
#
# Note: This code assumes that the necessary permissions are in place to read and source these files.
if [ -f /opt/kcli-pipelines/helper_scripts/default.env ]; then
  source /opt/kcli-pipelines/helper_scripts/default.env
  source /opt/kcli-pipelines/helper_scripts/helper_functions.sh
else
  echo "default.env file does not exist"
  exit 1
fi

# if DOWNLOAD_TO_TAR is set to true, then run the playbook
# This section of the script handles downloading images to TAR if DOWNLOAD_TO_TAR is set to true.
# It performs the following steps:
# 1. Creates or cleans the directory for storing images.
# 2. Checks if the Ansible Vault file is encrypted and decrypts it if necessary.
# 3. Retrieves the domain and OpenShift pull secret from Ansible variables.
# 4. Saves the pull secret to a file.
# 5. Re-encrypts the Ansible Vault file.
# 6. Checks if the Harbor registry is accessible.
# 7. Executes an Ansible playbook to download images to TAR.
#
# Variables used:
# - DOWNLOAD_TO_TAR: Boolean flag to determine if images should be downloaded.
# - USE_SUDO: A variable that may contain "sudo" if elevated permissions are required.
# - ANSIBLE_VAULT_FILE: Path to the Ansible Vault file.
# - ANSIBLE_ALL_VARIABLES: Path to the file containing all Ansible variables.
# - CODE_DIR: The directory containing the code and playbooks.
#
# Note: This code uses sudo commands (if USE_SUDO is set) and assumes the necessary permissions are in place.

if [ "${DOWNLOAD_TO_TAR}" == "true" ];
then
    if [ ! -d /var/lib/libvirt/images/openshift-containers/images ];
    then
        ${USE_SUDO} rm -rf /opt/images/ /var/lib/libvirt/images/openshift-containers/images || exit $?
        ${USE_SUDO} mkdir -p /var/lib/libvirt/images/openshift-containers/images
        ${USE_SUDO} ln -s /var/lib/libvirt/images/openshift-containers/images /opt/images || exit $?
    else
       cd  /opt/images
       rm -rf * || exit $?
    fi

    # Check if the file contains the string $ANSIBLE_VAULT;1.1;AES256
    if grep -q '$ANSIBLE_VAULT;1.1;AES256' "$ANSIBLE_VAULT_FILE"; then
        echo "The file is encrypted with Ansible Vault. Decrypting the file..."
        ${USE_SUDO} /usr/local/bin/ansiblesafe -f "${ANSIBLE_VAULT_FILE}" -o 2
        if [ $? -eq 0 ]; then
            echo "File decrypted successfully."
        else
            echo "Failed to decrypt the file."
        fi
    else
        echo "The file is not encrypted with Ansible Vault."
    fi

    DOMAIN=$(yq eval '.domain' "${ANSIBLE_ALL_VARIABLES}")
    PULL_SECRET=$(yq eval '.openshift_pull_secret' "${ANSIBLE_VAULT_FILE}")
    if [ -z $PULL_SECRET ];
    then
        echo "openshift_pull_secret does not exist"
        exit 1
    fi
    ${USE_SUDO} yq eval '.openshift_pull_secret' "${ANSIBLE_VAULT_FILE}" | sudo tee ~/rh-pull-secret >/dev/null
    cat ~/rh-pull-secret

    ${USE_SUDO} /usr/local/bin/ansiblesafe -f "${ANSIBLE_VAULT_FILE}" -o 1
    curl --fail https://harbor.${DOMAIN}/ || exit $?
    echo "Downloading images to /opt/images"
    cd ${CODE_DIR}

    echo   ${USE_SUDO} /usr/bin/ansible-playbook playbooks/download-to-tar.yml  -e "@extra_vars/download-to-tar-vars.yml" -vv
    ${USE_SUDO} /usr/bin/ansible-playbook playbooks/download-to-tar.yml  -e "@extra_vars/download-to-tar-vars.yml"  -vv || exit $?
fi


# This section of the script handles pushing images to a registry if PUSH_TAR_TO_REGISTRY is set to true.
# It performs the following steps:
# 1. Retrieves the domain from the Ansible variables file.
# 2. Checks if the Harbor registry is accessible.
# 3. Updates the registry server and password in the push-tar-to-registry-vars.yml file.
# 4. Executes an Ansible playbook to push the TAR images to the registry.
#
# Variables used:
# - PUSH_TAR_TO_REGISTRY: Boolean flag to determine if images should be pushed.
# - DOMAIN: The domain name retrieved from Ansible variables.
# - HARBOR_PASSWORD: The password for the Harbor registry.
# - CODE_DIR: The directory containing the code and playbooks.
#
# Note: This code uses sudo commands and assumes the necessary permissions are in place.

if [ "${PUSH_TAR_TO_REGISTRY}" == "true" ];
then
    DOMAIN=$(yq eval '.domain' "${ANSIBLE_ALL_VARIABLES}")
    curl --fail https://harbor.${DOMAIN}/ || exit $?
    echo "Pushing images to registry"
    ${USE_SUDO} yq eval '.registries[0].server = "harbor.'${DOMAIN}'"' -i extra_vars/push-tar-to-registry-vars.yml || exit $?
    ${USE_SUDO} yq eval '.registries[0].password = "'${HARBOR_PASSWORD}'"'  -i extra_vars/push-tar-to-registry-vars.yml || exit $?
    echo ${USE_SUDO} /usr/bin/ansible-playbook playbooks/push-tar-to-registry.yml  -e "@extra_vars/push-tar-to-registry-vars.yml" -vv
    ${USE_SUDO} /usr/bin/ansible-playbook playbooks/push-tar-to-registry.yml  -e "@extra_vars/push-tar-to-registry-vars.yml" -vv || exit $?
fi

# This section of the script handles the deletion of downloaded files if DELETE_DOWNLOADED_FILE is set to true.
# It performs the following steps:
# 1. Checks if the DELETE_DOWNLOADED_FILE variable is set to "true".
# 2. If true, it checks if the /opt/images/ directory exists.
# 3. If the directory exists, it changes to that directory.
# 4. It then removes all files and subdirectories within /opt/images/.
# 5. Finally, it removes the .oc-mirror.log file.
#
# Variables used:
# - DELETE_DOWNLOADED_FILE: Boolean flag to determine if files should be deleted.
# - USE_SUDO: A variable that may contain "sudo" if elevated permissions are required.
#
# Note: This code uses sudo commands (if USE_SUDO is set) and assumes the necessary permissions are in place.

if [ "${DELETE_DOWNLOADED_FILE}" == "true" ];
then
  if [ -d /opt/images/ ];
  then
      cd /opt/images
      $USE_SUDO rm -rf *
      $USE_SUDO  rm -rf  .oc-mirror.log
  fi
fi