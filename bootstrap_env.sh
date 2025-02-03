#!/bin/bash

# This script is referenced in README.md and should be updated there if modified
# See: Environment Setup and Validation section
### To-Do 
# 1. pip install molecule
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_info() {
    echo -e "${BLUE}$1${NC}"
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
dnf install -y libvirt libvirt-daemon libvirt-daemon-driver-qemu
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
dnf install -y python3-pip python3-devel gcc libffi-devel openssl-devel qemu-kvm cockpit-machines
dnf install -y ansible ansible-core
dnf install -y genisoimage cloud-utils-growpart cloud-init libguestfs-tools libguestfs-tools-c
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
    sudo usermod -aG libvirt $SUDO_USER
    usermod -aG kvm "$SUDO_USER"
    print_status "User $SUDO_USER added to libvirt and kvm groups" $?
else
    print_status "Could not determine user to add to libvirt groups" 1
fi

print_section "Installing kcli"
if ! command_exists kcli; then
    print_info "Installing kcli..."
    curl -s https://raw.githubusercontent.com/karmab/kcli/main/install.sh | bash
    if [ $? -eq 0 ]; then
        print_status "kcli installed successfully" 0
    else
        print_status "Failed to install kcli" 1
        exit 1
    fi
else
    print_status "kcli is already installed" 0
fi

print_section "Setting up libvirt storage pool"
# Check existing storage pools
if virsh pool-list --all | grep -q "kvm_pool"; then
    print_info "Found existing kvm_pool..."
    # Ensure the pool is active
    if ! virsh pool-info kvm_pool | grep -q "State.*running"; then
        print_info "Starting kvm_pool..."
        virsh pool-start kvm_pool
    fi
    print_status "kvm_pool is ready" 0
else
    # Check if we have the LVM volume group and logical volumes
    if vgs vg_data >/dev/null 2>&1; then
        print_info "Setting up storage pool using vg_data/lv_images..."
        # Define a new storage pool using the LVM volume
        virsh pool-define-as --name kvm_pool --type dir --target /var/lib/libvirt/images
        virsh pool-build kvm_pool
        virsh pool-start kvm_pool
        virsh pool-autostart kvm_pool
        print_status "Storage pool created and started using vg_data" $?
    else
        print_info "Creating default storage pool..."
        mkdir -p /var/lib/libvirt/images
        virsh pool-define-as --name kvm_pool --type dir --target /var/lib/libvirt/images
        virsh pool-build kvm_pool
        virsh pool-start kvm_pool
        virsh pool-autostart kvm_pool
        print_status "Default storage pool created and started" $?
    fi
fi

# Update KCLI configuration to use kvm_pool
if [ -f "/root/.kcli/config.yml" ]; then
    print_info "Updating kcli configuration..."
    # Backup existing config
    cp /root/.kcli/config.yml /root/.kcli/config.yml.bak
    # Update or add pool configuration
    sed -i 's/pool: default/pool: kvm_pool/' /root/.kcli/config.yml || \
    echo -e "\ndefault:\n  pool: kvm_pool" >> /root/.kcli/config.yml
    print_status "kcli configuration updated" 0
else
    mkdir -p /root/.kcli
    echo -e "default:\n  pool: kvm_pool" > /root/.kcli/config.yml
    print_status "kcli configuration created" 0
fi

print_section "RHEL 8 KVM Image Setup"
if [ ! -f "/var/lib/libvirt/images/rhel8.qcow2" ]; then
    print_info "Downloading RHEL 8 KVM image using kcli..."
    if sudo kcli download image rhel8; then
        # Create a symlink if kcli downloads to a different location
        if [ ! -f "/var/lib/libvirt/images/rhel8.qcow2" ] && [ -f "/root/.kcli/pool/rhel8.qcow2" ]; then
            ln -s /root/.kcli/pool/rhel8.qcow2 /var/lib/libvirt/images/rhel8.qcow2
        fi
        print_status "RHEL 8 KVM image downloaded successfully" 0
    else
        print_status "Failed to download RHEL 8 KVM image" 1
        print_info "Please try manual download:"
        echo "1. Visit: https://access.redhat.com/downloads/content/479/ver=/rhel---8/8.10/x86_64/product-software"
        echo "2. Log in with your Red Hat account"
        echo "3. Download the 'Red Hat Enterprise Linux 8.10 KVM Guest Image'"
        echo "4. Once downloaded, move it to /var/lib/libvirt/images/rhel8.qcow2"
        echo ""
        print_info "Example commands after downloading:"
        echo "sudo mv ~/Downloads/rhel-8.10-x86_64-kvm.qcow2 /var/lib/libvirt/images/rhel8.qcow2"
        echo "sudo chown root:root /var/lib/libvirt/images/rhel8.qcow2"
        echo "sudo chmod 644 /var/lib/libvirt/images/rhel8.qcow2"
    fi
else
    print_status "RHEL 8 KVM image already exists" 0
fi

print_section "Verifying Installation"
echo "Running environment validation script..."
./validate_env.sh

print_section "Next Steps"
echo -e "${YELLOW}Important:${NC}"
echo "1. You may need to log out and back in for group changes to take effect"
echo "2. Run './validate_env.sh' again after logging back in to verify the environment"
echo "3. If any checks still fail, please check the error messages and system logs"
echo "4. Make sure the RHEL 8 KVM image is properly set up"
