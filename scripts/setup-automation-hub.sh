#!/bin/bash
# Configure Automation Hub authentication and install ansible.controller collection
#
# Prerequisites:
#   - Red Hat Automation Hub API token saved in ./token file
#   - Get token from: https://console.redhat.com/ansible/automation-hub/token
#
# Usage:
#   ./scripts/setup-automation-hub.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TOKEN_FILE="$PROJECT_ROOT/token"
ANSIBLE_CFG="$PROJECT_ROOT/ansible.cfg"

echo "============================================================"
echo "  Automation Hub Configuration & Collection Installation"
echo "============================================================"
echo

# =========================================================================
# Step 1: Verify token file exists
# =========================================================================
if [[ ! -f "$TOKEN_FILE" ]]; then
    echo "❌ ERROR: Token file not found at $TOKEN_FILE"
    echo
    echo "To create the token file:"
    echo "  1. Visit: https://console.redhat.com/ansible/automation-hub/token"
    echo "  2. Click 'Load token'"
    echo "  3. Copy the token string"
    echo "  4. Save to: $TOKEN_FILE"
    echo
    echo "Example:"
    echo "  echo 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...' > $TOKEN_FILE"
    exit 1
fi

echo "✅ Token file found: $TOKEN_FILE"
AUTOMATION_HUB_TOKEN=$(cat "$TOKEN_FILE" | tr -d '[:space:]')

# =========================================================================
# Step 2: Backup existing ansible.cfg
# =========================================================================
if [[ -f "$ANSIBLE_CFG" ]]; then
    BACKUP="$ANSIBLE_CFG.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$ANSIBLE_CFG" "$BACKUP"
    echo "✅ Backed up ansible.cfg to: $BACKUP"
fi

# =========================================================================
# Step 3: Configure Automation Hub in ansible.cfg
# =========================================================================
echo "✅ Configuring Automation Hub authentication in ansible.cfg"

# Check if [galaxy] section exists
if ! grep -q '^\[galaxy\]' "$ANSIBLE_CFG" 2>/dev/null; then
    echo "" >> "$ANSIBLE_CFG"
    echo "[galaxy]" >> "$ANSIBLE_CFG"
fi

# Add or update server_list
if grep -q '^server_list' "$ANSIBLE_CFG"; then
    sed -i 's/^server_list.*/server_list = automation_hub, release_galaxy/' "$ANSIBLE_CFG"
else
    sed -i '/^\[galaxy\]/a server_list = automation_hub, release_galaxy' "$ANSIBLE_CFG"
fi

# Add Automation Hub server configuration
if ! grep -q '^\[galaxy_server.automation_hub\]' "$ANSIBLE_CFG"; then
    cat >> "$ANSIBLE_CFG" << EOF

[galaxy_server.automation_hub]
url = https://console.redhat.com/api/automation-hub/content/published/
auth_url = https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token
token = $AUTOMATION_HUB_TOKEN

[galaxy_server.release_galaxy]
url = https://galaxy.ansible.com/
EOF
    echo "✅ Added Automation Hub server configuration"
else
    # Update existing token
    sed -i "/^\[galaxy_server.automation_hub\]/,/^\[/ s|^token.*|token = $AUTOMATION_HUB_TOKEN|" "$ANSIBLE_CFG"
    echo "✅ Updated existing Automation Hub token"
fi

# =========================================================================
# Step 4: Test Automation Hub connectivity
# =========================================================================
echo
echo "Testing Automation Hub connectivity..."
if curl -s -H "Authorization: Bearer $AUTOMATION_HUB_TOKEN" \
    https://console.redhat.com/api/automation-hub/v3/collections/ \
    | grep -q '"data"'; then
    echo "✅ Automation Hub authentication successful"
else
    echo "⚠️  WARNING: Could not verify Automation Hub connectivity"
    echo "   Proceeding anyway - ansible-galaxy will verify during install"
fi

# =========================================================================
# Step 5: Install ansible.controller collection
# =========================================================================
echo
echo "Installing ansible.controller collection from Automation Hub..."
if ansible-galaxy collection install ansible.controller --force; then
    echo "✅ ansible.controller collection installed successfully"
else
    echo "❌ ERROR: Failed to install ansible.controller collection"
    echo
    echo "Troubleshooting:"
    echo "  1. Verify token is valid at: https://console.redhat.com/ansible/automation-hub/token"
    echo "  2. Check ansible.cfg configuration: $ANSIBLE_CFG"
    echo "  3. Try manual install: ansible-galaxy collection install ansible.controller -vvv"
    exit 1
fi

# =========================================================================
# Step 6: Verify installation
# =========================================================================
echo
echo "Verifying installation..."
if ansible-galaxy collection list ansible.controller | grep -q "ansible.controller"; then
    INSTALLED_VERSION=$(ansible-galaxy collection list ansible.controller | grep "ansible.controller" | awk '{print $2}')
    echo "✅ ansible.controller $INSTALLED_VERSION installed and verified"
else
    echo "❌ ERROR: Collection installed but not found in collection list"
    exit 1
fi

# =========================================================================
# Success Summary
# =========================================================================
echo
echo "============================================================"
echo "  ✅ Automation Hub Setup Complete"
echo "============================================================"
echo
echo "Configuration:"
echo "  • ansible.cfg updated with Automation Hub authentication"
echo "  • Token file: $TOKEN_FILE (gitignored)"
echo "  • Backup: $BACKUP"
echo
echo "Installed Collections:"
ansible-galaxy collection list | grep -E "(ansible.controller|awx.awx)"
echo
echo "Next Steps:"
echo "  1. Run AAP project import: ansible-playbook playbooks/setup-aap-project.yml"
echo "  2. Verify playbook uses ansible.controller modules (not awx.awx)"
echo
echo "============================================================"
