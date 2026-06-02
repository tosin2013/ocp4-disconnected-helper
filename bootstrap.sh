#!/bin/bash
#
# bootstrap.sh - Initial system setup for ocp4-disconnected-helper
#
# Purpose: Install minimal dependencies required to run Ansible playbooks
# Run this FIRST on a fresh RHEL/CentOS Stream 9.4+ system
#
# Usage: sudo ./bootstrap.sh
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}ocp4-disconnected-helper Bootstrap${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}ERROR: This script must be run as root (use sudo)${NC}"
  exit 1
fi

# Check OS version
echo -e "${YELLOW}[1/6] Checking OS version...${NC}"
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_NAME=$NAME
  OS_VERSION=$VERSION_ID

  if [[ "$ID" == "rhel" ]] || [[ "$ID" == "centos" ]]; then
    MAJOR_VERSION=$(echo $VERSION_ID | cut -d. -f1)
    if [ "$MAJOR_VERSION" -lt 9 ]; then
      echo -e "${RED}ERROR: Requires RHEL/CentOS Stream 9.4 or later${NC}"
      echo -e "${RED}Current: $OS_NAME $OS_VERSION${NC}"
      exit 1
    fi
    echo -e "${GREEN}✅ OS: $OS_NAME $OS_VERSION${NC}"
  else
    echo -e "${YELLOW}WARNING: Unsupported OS: $OS_NAME${NC}"
    echo -e "${YELLOW}Proceeding anyway, but issues may occur${NC}"
  fi
else
  echo -e "${RED}ERROR: Cannot determine OS version${NC}"
  exit 1
fi

# Install EPEL repository (for some dependencies)
echo -e "${YELLOW}[2/6] Installing EPEL repository...${NC}"
dnf install -y epel-release || {
  echo -e "${YELLOW}WARNING: EPEL install failed (may already be installed)${NC}"
}
echo -e "${GREEN}✅ EPEL repository ready${NC}"

# Install Ansible
echo -e "${YELLOW}[3/6] Installing ansible-core...${NC}"
dnf install -y ansible-core python3-pip
ANSIBLE_VERSION=$(ansible --version | head -n1)
echo -e "${GREEN}✅ Installed: $ANSIBLE_VERSION${NC}"

# Install Ansible collections
echo -e "${YELLOW}[4/6] Installing Ansible collections...${NC}"
ansible-galaxy collection install ansible.posix community.libvirt --force
echo -e "${GREEN}✅ Collections installed: ansible.posix, community.libvirt${NC}"

# Install git (required to clone repository)
echo -e "${YELLOW}[5/6] Installing git...${NC}"
dnf install -y git
echo -e "${GREEN}✅ Git installed${NC}"

# Verify Ansible is working
echo -e "${YELLOW}[6/6] Verifying Ansible setup...${NC}"
ansible localhost -m ping > /dev/null 2>&1 || {
  echo -e "${RED}ERROR: Ansible ping test failed${NC}"
  exit 1
}
echo -e "${GREEN}✅ Ansible is working${NC}"

echo ""
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Bootstrap Complete!${NC}"
echo -e "${GREEN}======================================${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo ""
echo "  1. Run the main setup playbook:"
echo "     ${GREEN}ansible-playbook playbooks/setup-dependencies.yml${NC}"
echo ""
echo "  2. Validate the setup:"
echo "     ${GREEN}ansible-playbook playbooks/validate-cockpit-libvirt.yml${NC}"
echo ""
echo "  3. Access Cockpit web console:"
echo "     ${GREEN}http://$(hostname -I | awk '{print $1}'):9090${NC}"
echo ""
echo -e "${YELLOW}Documentation:${NC}"
echo "  - PREREQUISITES.md - System requirements"
echo "  - COCKPIT_LIBVIRT_SETUP.md - Cockpit setup guide"
echo "  - REGISTRY_ROADMAP.md - Registry configuration options"
echo ""
