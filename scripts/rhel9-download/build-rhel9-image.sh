#!/bin/bash
# Build RHEL 9 KVM Guest Image using Image Builder (Method 3)
# Requires: osbuild-composer, composer-cli

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Target location
TARGET_DIR="/var/lib/libvirt/images"
TARGET_FILE="${TARGET_DIR}/rhel9-kvm-guest.qcow2"
BLUEPRINT_NAME="rhel9-kvm-guest"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  RHEL 9 KVM Guest Image Builder (Method 3)                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ This script must be run as root (or with sudo)${NC}"
    exit 1
fi

# Check if RHEL is registered
if ! subscription-manager status &> /dev/null; then
    echo -e "${RED}✗ System is not registered with Red Hat${NC}"
    echo ""
    echo "Register with:"
    echo "  subscription-manager register --username <user> --password <pass>"
    echo "  subscription-manager attach --pool=<pool-id>"
    exit 1
fi

echo -e "${GREEN}✓ System is registered with Red Hat${NC}"

# Check for Image Builder
if ! command -v composer-cli &> /dev/null; then
    echo ""
    echo -e "${YELLOW}Image Builder not installed. Installing...${NC}"

    dnf install -y osbuild-composer composer-cli cockpit-composer

    echo -e "${BLUE}Enabling osbuild-composer service...${NC}"
    systemctl enable --now osbuild-composer.socket

    sleep 5
    echo -e "${GREEN}✓ Image Builder installed${NC}"
else
    echo -e "${GREEN}✓ Image Builder already installed${NC}"
fi

# Create blueprint
echo ""
echo -e "${BLUE}Creating blueprint: ${BLUEPRINT_NAME}${NC}"

BLUEPRINT_FILE="/tmp/${BLUEPRINT_NAME}.toml"

cat > "$BLUEPRINT_FILE" << 'EOF'
name = "rhel9-kvm-guest"
description = "RHEL 9 KVM Guest Image for AAP"
version = "1.0.0"
modules = []
groups = []

[[packages]]
name = "cloud-init"
version = "*"

[[packages]]
name = "podman"
version = "*"

[[packages]]
name = "firewalld"
version = "*"

[[packages]]
name = "python3"
version = "*"

[[customizations.user]]
name = "cloud-user"
description = "Cloud User"
groups = ["wheel"]
EOF

echo "Blueprint contents:"
cat "$BLUEPRINT_FILE"
echo ""

# Push blueprint
echo -e "${BLUE}Pushing blueprint to Image Builder...${NC}"
composer-cli blueprints push "$BLUEPRINT_FILE"

echo -e "${GREEN}✓ Blueprint pushed${NC}"

# List blueprints to confirm
echo ""
echo -e "${BLUE}Available blueprints:${NC}"
composer-cli blueprints list

# Start compose
echo ""
echo -e "${YELLOW}Starting image build (qcow2 format)...${NC}"
echo "  This will take 10-20 minutes"
echo ""

COMPOSE_UUID=$(composer-cli compose start "$BLUEPRINT_NAME" qcow2 | awk '{print $2}')

if [ -z "$COMPOSE_UUID" ]; then
    echo -e "${RED}✗ Failed to start compose${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build started${NC}"
echo "  UUID: $COMPOSE_UUID"
echo ""

# Monitor build progress
echo -e "${BLUE}Monitoring build progress...${NC}"
echo "  (Press Ctrl+C to stop monitoring - build continues in background)"
echo ""

while true; do
    STATUS=$(composer-cli compose status | grep "$COMPOSE_UUID" | awk '{print $2}')

    case $STATUS in
        FINISHED)
            echo ""
            echo -e "${GREEN}✓ Build completed successfully${NC}"
            break
            ;;
        FAILED)
            echo ""
            echo -e "${RED}✗ Build failed${NC}"
            echo ""
            echo "Check logs:"
            echo "  composer-cli compose log $COMPOSE_UUID"
            exit 1
            ;;
        RUNNING)
            echo -ne "  Status: ${STATUS} (building...)\\r"
            sleep 10
            ;;
        *)
            echo -ne "  Status: ${STATUS}\\r"
            sleep 10
            ;;
    esac
done

# Download the image
echo ""
echo -e "${BLUE}Downloading built image...${NC}"

TEMP_DIR="/tmp/rhel9-image-$$"
mkdir -p "$TEMP_DIR"
cd "$TEMP_DIR"

composer-cli compose image "$COMPOSE_UUID"

# Find the qcow2 file
QCOW2_FILE=$(find . -name "*.qcow2" -type f | head -1)

if [ -z "$QCOW2_FILE" ]; then
    echo -e "${RED}✗ Could not find qcow2 file${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Image downloaded${NC}"
echo "  File: $QCOW2_FILE"

# Move to target location
echo ""
echo -e "${BLUE}Moving image to ${TARGET_FILE}...${NC}"

mv "$QCOW2_FILE" "$TARGET_FILE"
chown qemu:qemu "$TARGET_FILE"
chmod 644 "$TARGET_FILE"

# Cleanup
cd /
rm -rf "$TEMP_DIR"
rm -f "$BLUEPRINT_FILE"

# Verify
echo ""
echo -e "${BLUE}Verifying image...${NC}"
FILE_SIZE=$(du -h "$TARGET_FILE" | cut -f1)

echo "  Location: ${TARGET_FILE}"
echo "  Size: ${FILE_SIZE}"
echo "  Owner: qemu:qemu"
echo ""

qemu-img info "$TARGET_FILE" | head -10

# Success
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ RHEL 9 KVM Guest Image Built Successfully                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Next step: Provision AAP VM"
echo ""
echo "  cd /home/vpcuser/ocp4-disconnected-helper"
echo "  ansible-playbook -i inventory/ibm-cloud.yml playbooks/provision-aap-vm.yml"
echo ""
echo "Cleanup (optional):"
echo "  composer-cli compose delete $COMPOSE_UUID"
echo "  composer-cli blueprints delete $BLUEPRINT_NAME"
echo ""
