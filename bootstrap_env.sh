#!/bin/bash

# This script is referenced in README.md and should be updated there if modified
# See: Environment Setup and Validation section
### To-Do 
# 1. pip install molecule
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print with color
print_status() {
    if [ $2 -eq 0 ]; then
        echo -e "${GREEN}✓ $1${NC}"
    else
        echo -e "${RED}✗ $1${NC}"
        return 1
    fi
}

print_section() {
    echo -e "\n${YELLOW}$1${NC}"
    echo "================================"
}

# Check if script is run with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run this script with sudo privileges${NC}"
    exit 1
fi

# Register the system and enable the virt module
print_section "Registering System with Red Hat Subscription Management"
if ! subscription-manager status | grep -q "Overall Status: Current"; then
    subscription-manager register --auto-attach
    if [[ $? -ne 0 ]]; then
        print_status "System registration failed" 1
        exit 1
    fi
    print_status "System registered successfully" 0
else
    print_status "System already registered" 0
fi

print_section "Enabling libvirt"
dnf install -y   libvirt libvirt-daemon libvirt-daemon-driver-qemu
if [[ $? -ne 0 ]]; then
    print_status "Failed to enable libvirt module" 1
    exit 1
fi
print_status "libvirt module enabled" 0

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

print_section "Updating System Package Lists"
dnf update -y
print_status "Package lists updated" $?

print_section "Installing Prerequisites"
dnf install -y epel-release
dnf install -y @development
dnf install -y python3-pip python3-devel gcc libffi-devel openssl-devel
dnf install -y ansible ansible-core
print_status "Prerequisites installed" $?

print_section "Installing Ansible Collections"
ansible-galaxy collection install community.general community.libvirt ansible.posix containers.podman
print_status "Required Ansible collections installed" $?

# Verify Ansible version
ANSIBLE_VERSION=$(ansible --version | head -n1 | awk '{print $2}')
if [[ "$(printf '%s\n' "2.14.0" "$ANSIBLE_VERSION" | sort -V | head -n1)" = "2.14.0" ]]; then
    print_status "Ansible version $ANSIBLE_VERSION meets requirements" 0
else
    print_status "Ansible version $ANSIBLE_VERSION does not meet minimum requirement of 2.14.0" 1
fi

print_section "Installing Libvirt"
dnf install -y libvirt libvirt-daemon libvirt-daemon-driver-qemu
print_status "Libvirt and dependencies installed" $?

# Start and enable libvirtd service
systemctl start libvirtd
systemctl enable libvirtd
print_status "Libvirt service started and enabled" $?

# Verify Libvirt version
LIBVIRT_VERSION=$(libvirtd --version | awk '{print $3}')
if [[ "$(printf '%s\n' "8.0.0" "$LIBVIRT_VERSION" | sort -V | head -n1)" = "8.0.0" ]]; then
    print_status "Libvirt version $LIBVIRT_VERSION meets requirements" 0
else
    print_status "Libvirt version $LIBVIRT_VERSION does not meet minimum requirement of 8.0.0" 1
fi


# Add current user to libvirt group
if [ -n "$SUDO_USER" ]; then
    usermod -aG libvirt "$SUDO_USER"
    usermod -aG kvm "$SUDO_USER"
    print_status "User $SUDO_USER added to libvirt and kvm groups" $?
else
    print_status "Could not determine user to add to libvirt groups" 1
fi

print_section "Verifying Installation"
echo "Running environment validation script..."
./validate_env.sh

print_section "Next Steps"
echo -e "${YELLOW}Important:${NC}"
echo "1. You may need to log out and back in for group changes to take effect"
echo "2. Run './validate_env.sh' again after logging back in to verify the environment"
echo "3. If any checks still fail, please check the error messages and system logs"
