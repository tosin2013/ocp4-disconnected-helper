#!/bin/bash
# Operator Discovery Tool
#
# Search Red Hat operator catalogs and display available operators with channels.
# Outputs valid YAML snippets for easy copy-paste into extra_vars files.
#
# Usage:
#   ./scripts/discover-operators.sh --search storage
#   ./scripts/discover-operators.sh --catalog redhat --version 4.21 --search logging
#   ./scripts/discover-operators.sh --list-all --catalog certified

set -euo pipefail

# Default values
CATALOG_TYPE="redhat"
OCP_VERSION="4.21"
SEARCH_TERM=""
LIST_ALL=false
CACHE_DIR="/var/cache/oc-mirror/catalogs"
PULL_SECRET="${HOME}/pull-secret.json"
OC_MIRROR_BIN="/usr/local/bin/oc-mirror"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage function
usage() {
    cat << EOF
Operator Discovery Tool

Search and discover Red Hat operators with channel information.

USAGE:
    $0 [OPTIONS]

OPTIONS:
    --search <term>      Search for operators matching keyword (e.g., "storage", "logging")
    --catalog <type>     Catalog type: redhat (default), certified, community
    --version <ver>      OpenShift version (default: 4.21)
    --list-all           List all operators in catalog (no search filter)
    --cache-dir <path>   Cache directory (default: /var/cache/oc-mirror/catalogs)
    --pull-secret <path> Pull secret path (default: ~/pull-secret.json)
    --help               Show this help message

EXAMPLES:
    # Search for storage operators in Red Hat catalog
    $0 --search storage

    # Search certified catalog for logging operators
    $0 --catalog certified --search logging

    # List all community operators for OCP 4.20
    $0 --catalog community --version 4.20 --list-all

    # Search with custom cache location
    $0 --search observability --cache-dir /tmp/cache

OUTPUT:
    Displays matching operators with:
      • Operator name
      • Available channels
      • Default channel
      • YAML snippet for copy-paste

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --search)
            SEARCH_TERM="$2"
            shift 2
            ;;
        --catalog)
            CATALOG_TYPE="$2"
            shift 2
            ;;
        --version)
            OCP_VERSION="$2"
            shift 2
            ;;
        --list-all)
            LIST_ALL=true
            shift
            ;;
        --cache-dir)
            CACHE_DIR="$2"
            shift 2
            ;;
        --pull-secret)
            PULL_SECRET="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
            usage
            exit 1
            ;;
    esac
done

# Validate inputs
if [[ "$LIST_ALL" == "false" && -z "$SEARCH_TERM" ]]; then
    echo -e "${RED}ERROR: Either --search or --list-all must be specified${NC}" >&2
    usage
    exit 1
fi

# Map catalog type to full name
case $CATALOG_TYPE in
    redhat)
        CATALOG_NAME="redhat-operator-index"
        ;;
    certified)
        CATALOG_NAME="certified-operator-index"
        ;;
    community)
        CATALOG_NAME="community-operator-index"
        ;;
    *)
        echo -e "${RED}ERROR: Invalid catalog type. Use: redhat, certified, or community${NC}" >&2
        exit 1
        ;;
esac

CATALOG_URL="registry.redhat.io/redhat/${CATALOG_NAME}:v${OCP_VERSION}"
CACHE_FILE="${CACHE_DIR}/${CATALOG_NAME}-v${OCP_VERSION}.json"

# Check prerequisites
if [[ ! -f "$PULL_SECRET" ]]; then
    echo -e "${RED}ERROR: Pull secret not found at ${PULL_SECRET}${NC}" >&2
    echo "Download from: https://console.redhat.com/openshift/install/pull-secret" >&2
    exit 1
fi

if [[ ! -x "$OC_MIRROR_BIN" ]]; then
    echo -e "${RED}ERROR: oc-mirror not found at ${OC_MIRROR_BIN}${NC}" >&2
    echo "Install with: ansible-playbook download-to-disk-v2.yml --tags install" >&2
    exit 1
fi

# Ensure cache directory exists
mkdir -p "$CACHE_DIR"

# Check if cache exists and is recent (< 24 hours old)
CACHE_EXPIRED=true
if [[ -f "$CACHE_FILE" ]]; then
    CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
    CACHE_AGE_HOURS=$(( CACHE_AGE / 3600 ))
    if [[ $CACHE_AGE_HOURS -lt 24 ]]; then
        CACHE_EXPIRED=false
        echo -e "${GREEN}ℹ️  Using cached catalog (age: ${CACHE_AGE_HOURS}h)${NC}"
    else
        echo -e "${YELLOW}⚠️  Cache expired (age: ${CACHE_AGE_HOURS}h) - refreshing...${NC}"
    fi
fi

# Download catalog if cache missing or expired
if [[ "$CACHE_EXPIRED" == "true" ]]; then
    echo -e "${BLUE}Downloading catalog: ${CATALOG_URL}${NC}"
    if ! $OC_MIRROR_BIN list operators \
        --catalog="$CATALOG_URL" \
        --authfile="$PULL_SECRET" \
        --v2 \
        2>/dev/null | tee "$CACHE_FILE" > /dev/null; then
        echo -e "${RED}ERROR: Failed to download catalog${NC}" >&2
        exit 1
    fi
    echo -e "${GREEN}✅ Catalog downloaded successfully${NC}"
fi

# Parse catalog JSON and search
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}Operator Discovery: ${CATALOG_NAME}${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo -e "Catalog: ${CATALOG_URL}"
echo -e "Search: ${SEARCH_TERM:-'<all operators>'}"
echo ""

# Extract operators matching search term (or all if LIST_ALL)
if [[ "$LIST_ALL" == "true" ]]; then
    OPERATORS=$(jq -r 'keys[]' "$CACHE_FILE" | sort)
else
    OPERATORS=$(jq -r 'keys[]' "$CACHE_FILE" | grep -i "$SEARCH_TERM" | sort || true)
fi

OPERATOR_COUNT=$(echo "$OPERATORS" | wc -l)

if [[ -z "$OPERATORS" || "$OPERATOR_COUNT" -eq 0 ]]; then
    echo -e "${YELLOW}No operators found matching: ${SEARCH_TERM}${NC}"
    echo ""
    echo "Try broader search terms or use --list-all to see all operators."
    exit 0
fi

echo -e "${GREEN}Found ${OPERATOR_COUNT} operator(s)${NC}"
echo ""

# Display each operator with details
for OP in $OPERATORS; do
    # Extract operator details
    DEFAULT_CHANNEL=$(jq -r --arg op "$OP" '.[$op].defaultChannel' "$CACHE_FILE")
    CHANNELS=$(jq -r --arg op "$OP" '.[$op].channels[].name' "$CACHE_FILE" | sort)
    CHANNEL_COUNT=$(echo "$CHANNELS" | wc -l)

    echo -e "${YELLOW}────────────────────────────────────────${NC}"
    echo -e "${GREEN}Operator: ${OP}${NC}"
    echo -e "Default Channel: ${DEFAULT_CHANNEL}"
    echo -e "Available Channels (${CHANNEL_COUNT}):"
    for CH in $CHANNELS; do
        if [[ "$CH" == "$DEFAULT_CHANNEL" ]]; then
            echo -e "  • ${CH} ${BLUE}(default)${NC}"
        else
            echo -e "  • ${CH}"
        fi
    done

    echo ""
    echo -e "${BLUE}YAML Snippet (copy-paste):${NC}"
    cat << EOF
  - name: ${OP}
    channels:
      - name: ${DEFAULT_CHANNEL}
EOF
    echo ""
done

echo -e "${YELLOW}────────────────────────────────────────${NC}"
echo ""
echo -e "${BLUE}Usage in extra_vars:${NC}"
cat << EOF

operators:
  - catalog: ${CATALOG_URL}
    packages:
EOF

for OP in $OPERATORS; do
    DEFAULT_CHANNEL=$(jq -r --arg op "$OP" '.[$op].defaultChannel' "$CACHE_FILE")
    cat << EOF
      - name: ${OP}
        channels:
          - name: ${DEFAULT_CHANNEL}
EOF
done

echo ""
echo -e "${GREEN}✅ Discovery complete${NC}"
echo ""
echo -e "Next steps:"
echo -e "  1. Copy YAML snippet(s) to your extra_vars file"
echo -e "  2. Validate: ansible-playbook validate-operator-selection.yml -e @extra_vars/operators.yml"
echo -e "  3. Mirror: ansible-playbook download-to-disk-v2.yml -e @extra_vars/operators.yml"
echo ""
