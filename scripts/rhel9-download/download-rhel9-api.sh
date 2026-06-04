#!/bin/bash
# Download RHEL 9 KVM Guest Image using Red Hat API (Method 2)
# Requires: jq, curl

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

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  RHEL 9 KVM Guest Image Download (API Method)                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ This script must be run as root (or with sudo)${NC}"
    echo "  Usage: sudo $0"
    exit 1
fi

# Check for required tools
if ! command -v jq &> /dev/null; then
    echo -e "${RED}✗ jq is not installed${NC}"
    echo "  Install with: dnf install -y jq"
    exit 1
fi

# Get offline token
if [ -n "${RH_OFFLINE_TOKEN:-}" ]; then
    OFFLINE_TOKEN="$RH_OFFLINE_TOKEN"
    echo -e "${GREEN}✓ Using RH_OFFLINE_TOKEN from environment${NC}"
else
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}  Red Hat API Offline Token Required${NC}"
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "1. Navigate to: https://access.redhat.com/management/api"
    echo "2. Login with your Red Hat account"
    echo "3. Click 'Generate Token'"
    echo "4. Copy the offline token (starts with 'eyJh...')"
    echo ""
    echo "Note: Offline tokens don't expire and can be reused"
    echo "      Store securely (e.g., in Ansible Vault)"
    echo ""
    read -sp "Paste your offline token here: " OFFLINE_TOKEN
    echo

    if [ -z "$OFFLINE_TOKEN" ]; then
        echo -e "${RED}✗ No token provided${NC}"
        exit 1
    fi
fi

# Exchange offline token for access token
echo ""
echo -e "${BLUE}Exchanging offline token for access token...${NC}"

TOKEN_RESPONSE=$(curl -s -d grant_type=refresh_token \
    -d client_id=rhsm-api \
    -d refresh_token="$OFFLINE_TOKEN" \
    https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token)

if ! echo "$TOKEN_RESPONSE" | jq -e '.access_token' &> /dev/null; then
    echo -e "${RED}✗ Failed to get access token${NC}"
    echo ""
    echo "Error response:"
    echo "$TOKEN_RESPONSE" | jq '.'
    echo ""
    echo "Common issues:"
    echo "  - Invalid offline token"
    echo "  - Token has been revoked"
    echo "  - Network connectivity issue"
    exit 1
fi

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
TOKEN_EXPIRES_IN=$(echo "$TOKEN_RESPONSE" | jq -r '.expires_in')

echo -e "${GREEN}✓ Access token obtained (valid for ${TOKEN_EXPIRES_IN} seconds)${NC}"

# Attempt to find RHEL 9 image download URL via API
echo ""
echo -e "${YELLOW}⚠️  Note: Red Hat API Limitation${NC}"
echo ""
echo "The Red Hat Customer Portal API does not currently provide a direct"
echo "endpoint to list or download RHEL KVM guest images programmatically."
echo ""
echo "The API is primarily for subscription management, not content downloads."
echo ""
echo -e "${BLUE}Fallback: Use Web UI Method${NC}"
echo ""
echo "Recommended approach:"
echo "  1. Get download URL from: https://access.redhat.com/downloads/content/rhel"
echo "  2. Run: sudo ./download-rhel9-curl.sh <URL>"
echo ""
echo "Or for automation, store the download URL in a secure location"
echo "(e.g., Ansible Vault) and use curl directly."
echo ""
echo -e "${YELLOW}Access token is available for 15 minutes:${NC}"
echo "  export RH_ACCESS_TOKEN='${ACCESS_TOKEN}'"
echo ""
echo "You can use this token for authenticated Red Hat API calls:"
echo "  curl -H \"Authorization: Bearer \$RH_ACCESS_TOKEN\" <API_ENDPOINT>"
echo ""

# Save token to file for potential use
TOKEN_FILE="/tmp/rh_access_token_$(date +%s).txt"
echo "$ACCESS_TOKEN" > "$TOKEN_FILE"
chmod 600 "$TOKEN_FILE"

echo -e "${GREEN}Access token saved to: ${TOKEN_FILE}${NC}"
echo "  (expires in 15 minutes, will be auto-cleaned)"
echo ""

# Schedule cleanup
(sleep 900 && rm -f "$TOKEN_FILE" 2>/dev/null) &

exit 0
