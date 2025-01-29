#!/bin/bash

echo "Environment Validation Script"
echo "==========================="

# Function to compare versions
version_compare() {
    if [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]; then 
        return 0
    else
        return 1
    fi
}

# Function to print status
print_status() {
    if [ $2 -eq 0 ]; then
        echo "✅ $1"
    else
        echo "❌ $1"
        EXIT_CODE=1
    fi
}

EXIT_CODE=0

# 1. Check Operating System
OS=$(uname -s)
print_status "Operating System is Linux" $([ "$OS" = "Linux" ] && echo 0 || echo 1)

# 2. Check Kernel Version
KERNEL_VERSION=$(uname -r | cut -d'-' -f1)
REQUIRED_KERNEL="5.14"
version_compare $KERNEL_VERSION $REQUIRED_KERNEL
print_status "Kernel Version >= 5.14 (Current: $KERNEL_VERSION)" $?

# 3. Check Ansible Version and Collections
if command -v ansible >/dev/null 2>&1; then
    ANSIBLE_VERSION=$(ansible --version | head -n1 | awk '{print $2}')
    REQUIRED_ANSIBLE="2.14.0"
    version_compare $ANSIBLE_VERSION $REQUIRED_ANSIBLE
    ANSIBLE_VERSION_STATUS=$?
    print_status "Ansible Version >= 2.14.0 (Current: $ANSIBLE_VERSION)" $ANSIBLE_VERSION_STATUS

    # Check for required collections
    REQUIRED_COLLECTIONS=("community.general" "community.libvirt" "ansible.posix" "containers.podman")
    for collection in "${REQUIRED_COLLECTIONS[@]}"; do
        collection_name=$(echo "$collection" | cut -d':' -f1)
        if ansible-galaxy collection list | grep -q "$collection_name"; then
            print_status "Required Ansible collection '$collection_name' is installed" 0
        else
            print_status "Required Ansible collection '$collection_name' is not installed" 1
        fi
    done
else
    print_status "Ansible is not installed" 1
fi

# 4. Check Libvirt Version
if command -v libvirtd >/dev/null 2>&1; then
    LIBVIRT_VERSION=$(libvirtd --version | awk '{print $3}')
    REQUIRED_LIBVIRT="8.0.0"
    version_compare $LIBVIRT_VERSION $REQUIRED_LIBVIRT
    print_status "Libvirt Version >= 8.0.0 (Current: $LIBVIRT_VERSION)" $?
else
    print_status "Libvirt is not installed" 1
fi

# 5. Check KVM Status
if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    KVM_NESTED=$(cat /sys/module/kvm_intel/parameters/nested 2>/dev/null || cat /sys/module/kvm_amd/parameters/nested 2>/dev/null)
    if [ "$KVM_NESTED" = "Y" ] || [ "$KVM_NESTED" = "1" ]; then
        print_status "KVM is enabled and nested virtualization is supported" 0
    else
        print_status "KVM is enabled but nested virtualization is not supported" 1
    fi
else
    print_status "KVM is not enabled or accessible" 1
fi

echo "==========================="
if [ $EXIT_CODE -eq 0 ]; then
    echo "✅ All environment checks passed"
else
    echo "❌ Some environment checks failed"
fi

exit $EXIT_CODE
