#!/bin/bash
# Preflight validation for AAP installer registry credentials
# Prevents deployment failures due to missing Control Plane EE authentication
# Related: ADR-0031

set -euo pipefail

INVENTORY_FILE="/opt/ansible-automation-platform/installer/inventory"
EXIT_CODE=0

echo "════════════════════════════════════════════════════════════════"
echo "  AAP 2.6 Registry Credentials Preflight Check"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check 1: Inventory file exists
if [ ! -f "$INVENTORY_FILE" ]; then
  echo "❌ FAIL: Inventory file not found at $INVENTORY_FILE"
  echo ""
  echo "Expected location:"
  echo "  /opt/ansible-automation-platform/installer/inventory"
  echo ""
  echo "If AAP installer is in a different location, update INVENTORY_FILE"
  echo "variable in this script."
  exit 1
fi

echo "✓ Inventory file found: $INVENTORY_FILE"
echo ""

# Check 2: Required variables present
REQUIRED_VARS=("registry_url" "registry_username" "registry_password")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
  if ! grep -q "^${var}=" "$INVENTORY_FILE"; then
    MISSING_VARS+=("$var")
  fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
  echo "❌ FAIL: Missing required registry credentials in inventory:"
  printf '  - %s\n' "${MISSING_VARS[@]}"
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  REQUIRED: Add to [all:vars] section in inventory file:"
  echo "═══════════════════════════════════════════════════════════════"
  echo ""
  echo "  registry_url='registry.redhat.io'"
  echo "  registry_username='<org-id>|<service-account-name>'"
  echo "  registry_password='<service-account-token>'"
  echo ""
  echo "Generate service account at:"
  echo "  https://access.redhat.com/terms-based-registry/"
  echo ""
  echo "Why this is required:"
  echo "  AAP Control Plane Execution Environment needs to pull images"
  echo "  from registry.redhat.io for project syncs. Credentials MUST"
  echo "  be in installer inventory before running setup.sh."
  echo ""
  echo "See: docs/adrs/0031-aap-installer-registry-credentials.md"
  echo ""
  exit 1
fi

echo "✓ All required registry variables present"
echo ""

# Check 3: Validate registry_url
REGISTRY_URL=$(grep "^registry_url=" "$INVENTORY_FILE" | cut -d"'" -f2)
if [ -z "$REGISTRY_URL" ]; then
  echo "⚠️  WARNING: registry_url is empty"
  EXIT_CODE=1
elif [ "$REGISTRY_URL" != "registry.redhat.io" ]; then
  echo "⚠️  WARNING: registry_url is '$REGISTRY_URL' (expected 'registry.redhat.io')"
  EXIT_CODE=1
else
  echo "✓ registry_url: $REGISTRY_URL"
fi

# Check 4: Validate username format (should contain pipe |)
REGISTRY_USERNAME=$(grep "^registry_username=" "$INVENTORY_FILE" | cut -d"'" -f2)
if [ -z "$REGISTRY_USERNAME" ]; then
  echo "⚠️  WARNING: registry_username is empty"
  EXIT_CODE=1
elif [[ ! "$REGISTRY_USERNAME" =~ \| ]]; then
  echo "⚠️  WARNING: registry_username should be '<org-id>|<service-account>' format"
  echo "   Current value does not contain pipe (|) separator"
  EXIT_CODE=1
else
  # Mask password but show username
  USERNAME_PART=$(echo "$REGISTRY_USERNAME" | cut -d'|' -f2)
  echo "✓ registry_username: *****|$USERNAME_PART"
fi

# Check 5: Validate password is not empty
REGISTRY_PASSWORD=$(grep "^registry_password=" "$INVENTORY_FILE" | cut -d"'" -f2)
if [ -z "$REGISTRY_PASSWORD" ]; then
  echo "❌ FAIL: registry_password is empty"
  EXIT_CODE=1
elif [ ${#REGISTRY_PASSWORD} -lt 50 ]; then
  echo "⚠️  WARNING: registry_password seems too short (expected JWT token ~2000+ chars)"
  echo "   Current length: ${#REGISTRY_PASSWORD} characters"
  EXIT_CODE=1
else
  echo "✓ registry_password: <REDACTED> (${#REGISTRY_PASSWORD} characters)"
fi

echo ""
echo "════════════════════════════════════════════════════════════════"

if [ $EXIT_CODE -eq 0 ]; then
  echo "  ✅ PREFLIGHT CHECK PASSED"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "Registry credentials are properly configured."
  echo "Safe to proceed with: ./setup.sh -i inventory"
  echo ""
else
  echo "  ⚠️  PREFLIGHT CHECK COMPLETED WITH WARNINGS"
  echo "════════════════════════════════════════════════════════════════"
  echo ""
  echo "Review warnings above before proceeding with setup.sh"
  echo ""
fi

exit $EXIT_CODE
