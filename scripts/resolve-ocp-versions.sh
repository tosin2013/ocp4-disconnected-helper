#!/bin/bash
# resolve-ocp-versions.sh - Query OpenShift API and update extra_vars
# Called by ocp_registry_sync DAG resolve_versions task

set -euo pipefail

# Argument parsing
SOURCE_VERSION="${1:-4.19}"
TARGET_VERSION="${2:-4.20}"
UPGRADE_TYPE="${3:-major}"
VARS_FILE="${4:-/root/ocp4-disconnected-helper/extra_vars/download-to-tar-vars.yml}"

echo "===================================================================="
echo "[INFO] Resolving OCP Versions from OpenShift API"
echo "===================================================================="
echo ""
echo "Source Version: $SOURCE_VERSION"
echo "Target Version: $TARGET_VERSION"
echo "Upgrade Type: $UPGRADE_TYPE"
echo "Vars File: $VARS_FILE"
echo ""

# Function to get the latest patch version for a given minor version
get_latest_patch() {
    local version=$1
    local channel="stable-${version}"
    
    local result=$(curl -s -H "Accept: application/json" \
        "https://api.openshift.com/api/upgrades_info/v1/graph?channel=${channel}" | \
        jq -r --arg ver "$version" '.nodes[] | select(.version | startswith($ver)) | .version' | \
        sort -V | tail -1)
    
    echo "$result"
}

echo "[INFO] Querying OpenShift API for latest patch versions..."

if [ "$UPGRADE_TYPE" = "patch" ]; then
    # Patch upgrade: only need target version
    echo "[INFO] Patch upgrade - only syncing target version"
    LATEST_TARGET=$(get_latest_patch "$TARGET_VERSION")
    
    if [ -z "$LATEST_TARGET" ]; then
        echo "[ERROR] Failed to resolve latest $TARGET_VERSION version"
        exit 1
    fi
    
    echo "[OK] Resolved target: $LATEST_TARGET"
    
    # Update openshift_releases with specific versions
    export OCP_NAME="stable-${TARGET_VERSION}"
    export OCP_MIN="$LATEST_TARGET"
    export OCP_MAX="$LATEST_TARGET"
    export OCP_TYPE="ocp"
    
    yq eval -i '
        .openshift_releases = [{
            "name": env(OCP_NAME),
            "minVersion": env(OCP_MIN),
            "maxVersion": env(OCP_MAX),
            "shortestPath": true,
            "type": env(OCP_TYPE)
        }]
    ' "$VARS_FILE"
    
    # Update operator catalog version (single target)
    export CATALOG_VER="$TARGET_VERSION"
    yq eval -i '
        .certified_operator_index_version = env(CATALOG_VER) |
        .redhat_operator_index_version = env(CATALOG_VER)
    ' "$VARS_FILE"
    
else
    # Major upgrade: need both source and target
    echo "[INFO] Major upgrade - syncing source and target versions"
    LATEST_SOURCE=$(get_latest_patch "$SOURCE_VERSION")
    LATEST_TARGET=$(get_latest_patch "$TARGET_VERSION")
    
    if [ -z "$LATEST_SOURCE" ] || [ -z "$LATEST_TARGET" ]; then
        echo "[ERROR] Failed to resolve versions"
        echo "  Source ($SOURCE_VERSION): $LATEST_SOURCE"
        echo "  Target ($TARGET_VERSION): $LATEST_TARGET"
        exit 1
    fi
    
    echo "[OK] Resolved source: $LATEST_SOURCE"
    echo "[OK] Resolved target: $LATEST_TARGET"
    
    # Update openshift_releases with both versions
    export SRC_NAME="stable-${SOURCE_VERSION}"
    export SRC_MIN="$LATEST_SOURCE"
    export SRC_MAX="$LATEST_SOURCE"
    export TGT_NAME="stable-${TARGET_VERSION}"
    export TGT_MIN="$LATEST_TARGET"
    export TGT_MAX="$LATEST_TARGET"
    export OCP_TYPE="ocp"
    
    yq eval -i '
        .openshift_releases = [
            {"name": env(SRC_NAME), "minVersion": env(SRC_MIN), "maxVersion": env(SRC_MAX), "type": env(OCP_TYPE)},
            {"name": env(TGT_NAME), "minVersion": env(TGT_MIN), "maxVersion": env(TGT_MAX), "shortestPath": true, "type": env(OCP_TYPE)}
        ]
    ' "$VARS_FILE"
    
    # Update operator catalog version (use target for upgrade)
    export CATALOG_VER="$TARGET_VERSION"
    yq eval -i '
        .certified_operator_index_version = env(CATALOG_VER) |
        .redhat_operator_index_version = env(CATALOG_VER)
    ' "$VARS_FILE"
fi

echo ""
echo "[OK] Versions resolved and updated in $VARS_FILE"
echo ""
echo "Updated openshift_releases:"
yq eval '.openshift_releases' "$VARS_FILE"

