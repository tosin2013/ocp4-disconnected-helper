#!/bin/bash
#
# Registry VM Deployment Wrapper
# Ensures proper libvirt permissions and environment
#

set -e

# Ensure virsh works without sudo
export LIBVIRT_DEFAULT_URI="qemu:///system"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

# Deploy registry VM
ansible-playbook -i inventory/ibm-cloud.yml playbooks/site.yml --tags registry \
  -e "vm_network=1924" \
  -e "vm_gateway=192.168.10.1" \
  -e '{"vm_dns_servers":["192.168.10.1","161.26.0.10"]}' \
  -e "vm_static_ip=192.168.10.10" \
  -e "vm_mac_address=52:54:00:10:00:10" \
  -e "vyos_managed_network=true" \
  -e "vm_network_timeout=180" \
  "$@"
