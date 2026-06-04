#!/bin/bash
# Download RHEL 9 KVM Guest Image using curl (Method 1)
# Usage: ./download-rhel9-curl.sh [URL]

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Target location
TARGET_DIR="/var/lib/libvirt/images"
TARGET_FILE="${TARGET_DIR}/rhel9-kvm-guest.qcow2"
EXPECTED_SIZE_MB=1200

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  RHEL 9 KVM Guest Image Download (curl Method)                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ This script must be run as root (or with sudo)${NC}"
    echo "  Reason: Writing to ${TARGET_DIR} requires root permissions"
    echo ""
    echo "Usage: sudo $0 [URL]"
    exit 1
fi

# Check available disk space
AVAILABLE_MB=$(df -BM "${TARGET_DIR}" | awk 'NR==2 {print $4}' | sed 's/M//')
if [ "$AVAILABLE_MB" -lt $((EXPECTED_SIZE_MB * 2)) ]; then
    echo -e "${YELLOW}⚠️  Warning: Low disk space${NC}"
    echo "   Available: ${AVAILABLE_MB} MB"
    echo "   Recommended: $((EXPECTED_SIZE_MB * 2)) MB"
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Aborted${NC}"
        exit 1
    fi
fi

# Check if file already exists
if [ -f "$TARGET_FILE" ]; then
    echo -e "${YELLOW}⚠️  File already exists: ${TARGET_FILE}${NC}"
    FILE_SIZE=$(du -h "$TARGET_FILE" | cut -f1)
    echo "   Current size: $FILE_SIZE"
    echo ""
    echo "Options:"
    echo "  1) Delete and re-download"
    echo "  2) Resume download (if interrupted)"
    echo "  3) Keep existing and exit"
    echo ""
    read -p "Choose [1/2/3]: " -n 1 -r CHOICE
    echo

    case $CHOICE in
        1)
            echo -e "${YELLOW}Deleting existing file...${NC}"
            rm -f "$TARGET_FILE"
            ;;
        2)
            echo -e "${GREEN}Will attempt to resume download${NC}"
            RESUME_FLAG="-C -"
            ;;
        3)
            echo -e "${GREEN}Keeping existing file${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Exiting.${NC}"
            exit 1
            ;;
    esac
fi

# Get download URL
if [ $# -eq 0 ]; then
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Get Download URL from Red Hat Customer Portal${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "1. Navigate to: https://access.redhat.com/downloads/content/rhel"
    echo "2. Login with your Red Hat subscription"
    echo "3. Select: Red Hat Enterprise Linux 9.X KVM Guest Image"
    echo "4. Right-click download button → Copy Link Address"
    echo ""
    echo "The URL should look like:"
    echo "  https://access.cdn.redhat.com/content/origin/files/sha256/.../rhel-9.4-x86_64-kvm.qcow2?...auth_token=XXXXX"
    echo ""
    read -p "Paste the download URL here: " DOWNLOAD_URL

    if [ -z "$DOWNLOAD_URL" ]; then
        echo -e "${RED}✗ No URL provided${NC}"
        exit 1
    fi
else
    DOWNLOAD_URL="$1"
fi

# Validate URL
if [[ ! "$DOWNLOAD_URL" =~ ^https://access\.cdn\.redhat\.com/ ]]; then
    echo -e "${YELLOW}⚠️  Warning: URL doesn't look like a Red Hat CDN URL${NC}"
    echo "   Expected: https://access.cdn.redhat.com/..."
    echo "   Got: ${DOWNLOAD_URL:0:50}..."
    echo ""
    read -p "Continue anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Aborted${NC}"
        exit 1
    fi
fi

# Download the file
echo ""
echo -e "${GREEN}Starting download...${NC}"
echo "  Source: Red Hat CDN"
echo "  Target: ${TARGET_FILE}"
echo "  Expected size: ~${EXPECTED_SIZE_MB} MB"
echo ""

CURL_OPTS="-# -L -o ${TARGET_FILE}"
if [ -n "${RESUME_FLAG:-}" ]; then
    CURL_OPTS="${CURL_OPTS} ${RESUME_FLAG}"
fi

if curl $CURL_OPTS "$DOWNLOAD_URL"; then
    echo ""
    echo -e "${GREEN}✓ Download completed successfully${NC}"

    # Set proper permissions
    echo ""
    echo -e "${BLUE}Setting permissions...${NC}"
    chown qemu:qemu "$TARGET_FILE"
    chmod 644 "$TARGET_FILE"

    # Verify the downloaded file
    echo ""
    echo -e "${BLUE}Verifying downloaded file...${NC}"
    FILE_SIZE=$(du -h "$TARGET_FILE" | cut -f1)
    FILE_SIZE_MB=$(du -BM "$TARGET_FILE" | cut -f1 | sed 's/M//')

    echo "  Location: ${TARGET_FILE}"
    echo "  Size: ${FILE_SIZE} (${FILE_SIZE_MB} MB)"
    echo "  Owner: qemu:qemu"
    echo "  Permissions: 644"

    # Check if size is reasonable
    if [ "$FILE_SIZE_MB" -lt 100 ]; then
        echo ""
        echo -e "${RED}✗ Warning: File size is suspiciously small (${FILE_SIZE_MB} MB)${NC}"
        echo "  Expected: ~${EXPECTED_SIZE_MB} MB"
        echo "  Possible causes:"
        echo "    - Download URL expired (tokens are valid ~1 hour)"
        echo "    - Network error"
        echo "    - Downloaded an error page instead of the image"
        echo ""
        echo "  Try getting a fresh URL from Red Hat Customer Portal"
        exit 1
    fi

    # Verify qcow2 format
    if command -v qemu-img &> /dev/null; then
        echo ""
        echo -e "${BLUE}Checking image format...${NC}"
        if qemu-img info "$TARGET_FILE" | head -5; then
            echo ""
            echo -e "${GREEN}✓ Image format verified (qcow2)${NC}"
        else
            echo -e "${YELLOW}⚠️  Warning: Could not verify image format${NC}"
        fi
    fi

    # Success summary
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  ✓ RHEL 9 KVM Guest Image Downloaded Successfully             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Next step: Provision AAP VM"
    echo ""
    echo "  cd /home/vpcuser/ocp4-disconnected-helper"
    echo "  ansible-playbook -i inventory/ibm-cloud.yml playbooks/provision-aap-vm.yml"
    echo ""

else
    echo ""
    echo -e "${RED}✗ Download failed${NC}"
    echo ""
    echo "Common issues:"
    echo "  1. Download URL expired (tokens valid ~1 hour)"
    echo "     → Get a fresh URL from Red Hat Customer Portal"
    echo ""
    echo "  2. Network connectivity issue"
    echo "     → Check internet connection"
    echo ""
    echo "  3. Interrupted download"
    echo "     → Re-run script and choose option 2 (Resume)"
    echo ""
    exit 1
fi
