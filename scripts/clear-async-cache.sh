#!/bin/bash
# Clear Ansible async cache for oc-mirror operations
# Use this after failed oc-mirror playbook runs

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

DRY_RUN="${1:-}"

echo -e "${YELLOW}=== Ansible Async Cache Cleanup ===${NC}"
echo ""

# Check user async cache
USER_CACHE="${HOME}/.ansible_async"
if [ -d "$USER_CACHE" ]; then
    FILE_COUNT=$(find "$USER_CACHE" -type f 2>/dev/null | wc -l)
    if [ "$FILE_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}Found $FILE_COUNT files in $USER_CACHE${NC}"
        if [ "$DRY_RUN" = "--dry-run" ]; then
            echo -e "${GREEN}[DRY RUN] Would remove: rm -rf $USER_CACHE/*${NC}"
        else
            rm -rf "$USER_CACHE"/*
            echo -e "${GREEN}✓ Cleared user async cache${NC}"
        fi
    else
        echo -e "${GREEN}✓ User async cache already empty${NC}"
    fi
else
    echo -e "${GREEN}✓ No user async cache directory${NC}"
fi

echo ""

# Check root async cache
ROOT_CACHE="/root/.ansible_async"
if [ -d "$ROOT_CACHE" ]; then
    FILE_COUNT=$(sudo find "$ROOT_CACHE" -type f 2>/dev/null | wc -l)
    if [ "$FILE_COUNT" -gt 0 ]; then
        echo -e "${YELLOW}Found $FILE_COUNT files in $ROOT_CACHE${NC}"
        if [ "$DRY_RUN" = "--dry-run" ]; then
            echo -e "${GREEN}[DRY RUN] Would remove: sudo rm -rf $ROOT_CACHE/*${NC}"
        else
            read -p "Clear root async cache? This requires sudo. [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                sudo rm -rf "$ROOT_CACHE"/*
                echo -e "${GREEN}✓ Cleared root async cache${NC}"
            else
                echo -e "${YELLOW}⊘ Skipped root async cache${NC}"
            fi
        fi
    else
        echo -e "${GREEN}✓ Root async cache already empty${NC}"
    fi
else
    echo -e "${GREEN}✓ No root async cache directory${NC}"
fi

echo ""
echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo ""
echo "You can now re-run the oc-mirror playbook:"
echo "  ansible-playbook -i inventory/ibm-cloud.yml playbooks/download-to-disk-v2.yml -e @extra_vars/mirror-v2-test.yml"
