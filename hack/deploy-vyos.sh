#!/bin/bash
#
# VyOS Router Deployment Wrapper
# Deploys VyOS router VM for OpenShift disconnected infrastructure
# Reference: https://tosin2013.github.io/openshift-agent-install/vyos-manual-configuration.html
#

set -e

# Ensure virsh works without sudo
export LIBVIRT_DEFAULT_URI="qemu:///system"

# Environment configuration
export DOMAIN="${DOMAIN:-ocp4.sandbox3377.opentlc.com}"
export GUID="${GUID:-ocp4}"
export ZONE_NAME="${ZONE_NAME:-sandbox3377.opentlc.com}"
export DNS_FORWARDER="${DNS_FORWARDER:-161.26.0.10}"  # IBM Cloud DNS
export USE_SUDO="${USE_SUDO:-sudo}"

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  VyOS Router Deployment for OpenShift Disconnected Helper     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}Environment Configuration:${NC}"
echo "  Domain:        ${DOMAIN}"
echo "  GUID:          ${GUID}"
echo "  Zone:          ${ZONE_NAME}"
echo "  DNS Forwarder: ${DNS_FORWARDER}"
echo "  Cockpit URL:   https://$(hostname -I | awk '{print $1}'):9090"
echo ""

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command -v virt-install &> /dev/null; then
    echo -e "${RED}ERROR: virt-install not found${NC}"
    echo "Install with: sudo dnf install -y virt-install"
    exit 1
fi

if ! systemctl is-active --quiet libvirtd; then
    echo -e "${RED}ERROR: libvirtd is not running${NC}"
    echo "Start with: sudo systemctl start libvirtd"
    exit 1
fi

if ! systemctl is-active --quiet cockpit.socket; then
    echo -e "${YELLOW}WARNING: Cockpit is not running${NC}"
    echo "Starting cockpit for VyOS console access..."
    sudo systemctl start cockpit.socket
fi

echo -e "${GREEN}✓ All prerequisites met${NC}"
echo ""

# Execute the main VyOS router script
echo -e "${GREEN}Executing VyOS router deployment script...${NC}"
echo ""

cd "${SCRIPT_DIR}"

# Check if vyos-router.sh exists
if [ ! -f "${SCRIPT_DIR}/vyos-router.sh" ]; then
    echo -e "${RED}ERROR: vyos-router.sh not found${NC}"
    echo "Expected location: ${SCRIPT_DIR}/vyos-router.sh"
    exit 1
fi

# Set custom VyOS config script path
export VYOS_CONFIG_SCRIPT="${SCRIPT_DIR}/vyos-config-ocp4.sh"

# Set ACTION for vyos-router.sh (expects environment variable, not argument)
export ACTION="create"

# Run the VyOS deployment
bash "${SCRIPT_DIR}/vyos-router.sh"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}VyOS Router Deployment Initiated${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
echo "Next Steps:"
echo "  1. Access Cockpit: https://$(hostname -I | awk '{print $1}'):9090"
echo "  2. Navigate to Virtual Machines → vyos-router → Console"
echo "  3. Follow manual configuration instructions"
echo "  4. Script will wait up to 30 minutes for router to be accessible"
echo ""
echo "Reference Guide:"
echo "  https://tosin2013.github.io/openshift-agent-install/vyos-manual-configuration.html"
echo ""
