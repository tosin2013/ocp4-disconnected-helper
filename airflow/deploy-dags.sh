#!/bin/bash
# Deploy DAGs to qubinode_navigator Airflow
# This script syncs DAGs from ocp4-disconnected-helper to qubinode_navigator
#
# Usage:
#   ./deploy-dags.sh              # Deploy DAGs
#   ./deploy-dags.sh --check      # Check status only
#   ./deploy-dags.sh --remove     # Remove deployed DAGs

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/dags"
TARGET_DIR="${QUBINODE_NAVIGATOR_PATH:-/root/qubinode_navigator}/airflow/dags"
PROJECT_PREFIX="ocp_"  # All our DAGs start with this prefix

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_prerequisites() {
    if [ ! -d "$SOURCE_DIR" ]; then
        log_error "Source directory not found: $SOURCE_DIR"
        exit 1
    fi

    if [ ! -d "$TARGET_DIR" ]; then
        log_error "Target directory not found: $TARGET_DIR"
        log_error "Is qubinode_navigator installed at ${QUBINODE_NAVIGATOR_PATH:-/root/qubinode_navigator}?"
        exit 1
    fi
}

list_source_dags() {
    find "$SOURCE_DIR" -name "${PROJECT_PREFIX}*.py" -type f 2>/dev/null
}

list_deployed_dags() {
    find "$TARGET_DIR" -name "${PROJECT_PREFIX}*.py" -type f 2>/dev/null
}

deploy_dags() {
    log_info "Deploying DAGs from ocp4-disconnected-helper to qubinode_navigator..."
    
    local count=0
    for dag_file in $(list_source_dags); do
        local filename=$(basename "$dag_file")
        local target_file="$TARGET_DIR/$filename"
        
        # Copy the file
        cp "$dag_file" "$target_file"
        log_info "  Deployed: $filename"
        ((count++))
    done

    if [ $count -eq 0 ]; then
        log_warn "No DAGs found to deploy in $SOURCE_DIR"
    else
        log_info "Deployed $count DAG(s)"
        log_info ""
        log_info "DAGs will be available after Airflow scheduler picks them up."
        log_info "To force refresh: podman exec airflow_airflow-scheduler_1 airflow dags reserialize"
    fi
}

check_status() {
    log_info "Checking DAG deployment status..."
    echo ""
    
    echo "Source DAGs (ocp4-disconnected-helper):"
    for dag_file in $(list_source_dags); do
        local filename=$(basename "$dag_file")
        local mtime=$(stat -c %y "$dag_file" 2>/dev/null | cut -d. -f1)
        echo "  - $filename (modified: $mtime)"
    done
    
    echo ""
    echo "Deployed DAGs (qubinode_navigator):"
    local deployed=$(list_deployed_dags)
    if [ -z "$deployed" ]; then
        echo "  (none)"
    else
        for dag_file in $deployed; do
            local filename=$(basename "$dag_file")
            local mtime=$(stat -c %y "$dag_file" 2>/dev/null | cut -d. -f1)
            echo "  - $filename (modified: $mtime)"
        done
    fi
    
    echo ""
    echo "Sync status:"
    local needs_sync=false
    for dag_file in $(list_source_dags); do
        local filename=$(basename "$dag_file")
        local target_file="$TARGET_DIR/$filename"
        
        if [ ! -f "$target_file" ]; then
            echo "  - $filename: NOT DEPLOYED"
            needs_sync=true
        elif ! diff -q "$dag_file" "$target_file" > /dev/null 2>&1; then
            echo "  - $filename: OUT OF SYNC"
            needs_sync=true
        else
            echo "  - $filename: OK"
        fi
    done
    
    if [ "$needs_sync" = true ]; then
        echo ""
        log_warn "Run './deploy-dags.sh' to sync DAGs"
    fi
}

remove_dags() {
    log_info "Removing deployed DAGs from qubinode_navigator..."
    
    local count=0
    for dag_file in $(list_deployed_dags); do
        local filename=$(basename "$dag_file")
        rm -f "$dag_file"
        log_info "  Removed: $filename"
        ((count++))
    done

    if [ $count -eq 0 ]; then
        log_warn "No deployed DAGs found to remove"
    else
        log_info "Removed $count DAG(s)"
    fi
}

# Main
check_prerequisites

case "${1:-}" in
    --check)
        check_status
        ;;
    --remove)
        remove_dags
        ;;
    --help|-h)
        echo "Usage: $0 [--check|--remove|--help]"
        echo ""
        echo "Deploy ocp4-disconnected-helper DAGs to qubinode_navigator Airflow"
        echo ""
        echo "Options:"
        echo "  --check   Check deployment status"
        echo "  --remove  Remove deployed DAGs"
        echo "  --help    Show this help"
        echo ""
        echo "Environment variables:"
        echo "  QUBINODE_NAVIGATOR_PATH  Path to qubinode_navigator (default: /root/qubinode_navigator)"
        ;;
    *)
        deploy_dags
        ;;
esac
