#!/bin/bash
# Rootless Podman Authentication Setup for AAP Custom Execution Environment Builds
#
# Implements the Stale Authentication Remediation Protocol (Section 4.2)
# Based on: Advanced Architecture and Authentication Workflows for Custom AAP EE
#           on CentOS Stream 10
#
# ADR Reference: ADR-0030 - Rootless Podman Authentication Architecture
#
# Usage:
#   ./setup-rootless-podman-auth.sh --registry-username 'USER' --registry-password 'TOKEN'
#
# Requirements:
#   - CentOS Stream 10 / RHEL 10
#   - Podman 5.x
#   - Non-root user execution
#   - Red Hat registry service account credentials

set -euo pipefail

# ============================================================================
# Configuration Variables
# ============================================================================

SCRIPT_VERSION="1.0.0"
SCRIPT_NAME=$(basename "$0")
CURRENT_USER=$(whoami)
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

# Paths per XDG Base Directory Specification
PERSISTENT_AUTH_DIR="${HOME}/.config/containers"
PERSISTENT_AUTH_FILE="${PERSISTENT_AUTH_DIR}/auth.json"
RUNTIME_DIR="/run/user/${CURRENT_UID}"
RUNTIME_AUTH_DIR="${RUNTIME_DIR}/containers"

# Registry configuration
REGISTRY_URL="registry.redhat.io"
REGISTRY_USERNAME=""
REGISTRY_PASSWORD=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

die() {
    log_error "$*"
    exit 1
}

check_root() {
    if [ "$CURRENT_UID" -eq 0 ]; then
        die "This script must NOT be run as root. Run as a standard user (e.g., vpcuser)."
    fi
}

check_dependencies() {
    local missing_deps=()

    for cmd in podman stat chmod; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    if [ ${#missing_deps[@]} -gt 0 ]; then
        die "Missing required commands: ${missing_deps[*]}"
    fi

    # Verify Podman version
    local podman_version
    podman_version=$(podman --version | awk '{print $3}')
    log_info "Detected Podman version: ${podman_version}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --registry-username)
                REGISTRY_USERNAME="$2"
                shift 2
                ;;
            --registry-password)
                REGISTRY_PASSWORD="$2"
                shift 2
                ;;
            --registry-url)
                REGISTRY_URL="$2"
                shift 2
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                die "Unknown parameter: $1. Use --help for usage."
                ;;
        esac
    done

    if [ -z "$REGISTRY_USERNAME" ] || [ -z "$REGISTRY_PASSWORD" ]; then
        die "Both --registry-username and --registry-password are required"
    fi
}

show_usage() {
    cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION}
Rootless Podman Authentication Setup for AAP Custom Execution Environment Builds

USAGE:
    ${SCRIPT_NAME} --registry-username 'USER' --registry-password 'TOKEN'

OPTIONS:
    --registry-username   Red Hat registry service account username
                          (Format: '12216224|ansible-execution-environment')
                          MUST be quoted due to pipe character

    --registry-password   Red Hat registry service account JWT token
                          (Format: 'eyJhbGciOiJSUzUxMiJ9...')

    --registry-url        Registry URL (default: registry.redhat.io)

    --help, -h            Show this help message

EXAMPLES:
    # Using vault-encrypted credentials
    ${SCRIPT_NAME} \\
        --registry-username '12216224|ansible-execution-environment' \\
        --registry-password "\$(ansible-vault view secrets.yml --vault-password-file ~/.vault_pass | grep password | cut -d: -f2)"

    # Using environment variables
    export RH_USERNAME='12216224|ansible-execution-environment'
    export RH_PASSWORD='eyJhbGci...'
    ${SCRIPT_NAME} --registry-username "\$RH_USERNAME" --registry-password "\$RH_PASSWORD"

ARCHITECTURE:
    This script implements the Stale Authentication Remediation Protocol per
    ADR-0030, addressing privilege bleed from Ansible's become: true and
    establishing persistent rootless authentication for ansible-builder.

    Key Concepts:
    - Volatile /run/user storage (tmpfs) vs. persistent ~/.config storage
    - DAC permission enforcement (0600 on auth.json, 0700 on parent dir)
    - REGISTRY_AUTH_FILE environment variable for subprocess inheritance
    - Root/non-root authentication state isolation

EOF
}

# ============================================================================
# Phase 1: Eradication of Stale Artifacts
# ============================================================================

eradicate_stale_artifacts() {
    log_info "Phase 1: Eradicating stale authentication artifacts..."

    local stale_files=()
    local sudo_required=()

    # Check for root-owned files in user runtime directory
    if [ -d "$RUNTIME_AUTH_DIR" ]; then
        if [ -f "${RUNTIME_AUTH_DIR}/auth.json" ]; then
            local owner
            owner=$(stat -c '%U:%G' "${RUNTIME_AUTH_DIR}/auth.json" 2>/dev/null || echo "unknown")
            if [ "$owner" = "root:root" ]; then
                log_warning "Found root-owned auth.json in ${RUNTIME_AUTH_DIR}"
                sudo_required+=("${RUNTIME_AUTH_DIR}/auth.json")
            else
                stale_files+=("${RUNTIME_AUTH_DIR}/auth.json")
            fi
        fi
    fi

    # Check for root-owned crun directory (causes build failures)
    if [ -d "${RUNTIME_DIR}/crun" ]; then
        local owner
        owner=$(stat -c '%U:%G' "${RUNTIME_DIR}/crun" 2>/dev/null || echo "unknown")
        if [ "$owner" = "root:root" ]; then
            log_warning "Found root-owned crun directory: ${RUNTIME_DIR}/crun"
            sudo_required+=("${RUNTIME_DIR}/crun")
        fi
    fi

    # Check for root-owned libpod directory
    if [ -d "${RUNTIME_DIR}/libpod" ]; then
        local owner
        owner=$(stat -c '%U:%G' "${RUNTIME_DIR}/libpod" 2>/dev/null || echo "unknown")
        if [ "$owner" = "root:root" ]; then
            log_warning "Found root-owned libpod directory: ${RUNTIME_DIR}/libpod"
            sudo_required+=("${RUNTIME_DIR}/libpod")
        fi
    fi

    # Remove root-owned files (requires sudo)
    if [ ${#sudo_required[@]} -gt 0 ]; then
        log_warning "The following root-owned artifacts require sudo to remove:"
        printf '  - %s\n' "${sudo_required[@]}"

        if command -v sudo &>/dev/null; then
            log_info "Attempting to remove root-owned artifacts with sudo..."
            for item in "${sudo_required[@]}"; do
                if sudo rm -rf "$item" 2>/dev/null; then
                    log_success "Removed: $item"
                else
                    log_error "Failed to remove: $item"
                fi
            done
        else
            log_error "sudo not available. Please manually remove the files listed above as root."
            die "Cannot proceed with root-owned artifacts present"
        fi
    fi

    # Remove user-owned stale files
    for file in "${stale_files[@]}"; do
        if rm -f "$file" 2>/dev/null; then
            log_success "Removed user-owned stale file: $file"
        fi
    done

    # Clean legacy Docker config locations
    if [ -f "${HOME}/.docker/config.json" ]; then
        log_info "Removing legacy Docker config: ${HOME}/.docker/config.json"
        rm -f "${HOME}/.docker/config.json" || true
    fi

    log_success "Phase 1 complete: Stale artifacts eradicated"
}

# ============================================================================
# Phase 2: Establishment of Persistent Storage Directories
# ============================================================================

establish_persistent_directories() {
    log_info "Phase 2: Establishing persistent storage directories..."

    # Create persistent auth directory with correct permissions
    if [ ! -d "$PERSISTENT_AUTH_DIR" ]; then
        mkdir -p "$PERSISTENT_AUTH_DIR"
        log_success "Created directory: $PERSISTENT_AUTH_DIR"
    fi

    # Enforce 0700 permissions (DAC policy)
    chmod 700 "$PERSISTENT_AUTH_DIR"

    # Verify ownership
    local dir_owner
    dir_owner=$(stat -c '%U:%G' "$PERSISTENT_AUTH_DIR")

    if [ "$dir_owner" != "${CURRENT_USER}:$(id -gn)" ]; then
        log_warning "Directory ownership mismatch. Expected: ${CURRENT_USER}:$(id -gn), Got: $dir_owner"

        if [ "$dir_owner" = "root:root" ]; then
            die "Directory is root-owned. Cannot proceed. Please manually fix ownership."
        fi
    fi

    # Display permission matrix
    local perms
    perms=$(stat -c '%a' "$PERSISTENT_AUTH_DIR")
    log_info "Directory permissions: $perms (required: 700)"
    log_info "Directory ownership: $dir_owner"

    if [ "$perms" != "700" ]; then
        log_warning "Permissions are not 0700. Correcting..."
        chmod 700 "$PERSISTENT_AUTH_DIR"
    fi

    log_success "Phase 2 complete: Persistent directory established"
}

# ============================================================================
# Phase 3: Execution of Rootless Login
# ============================================================================

execute_rootless_login() {
    log_info "Phase 3: Executing rootless Podman login..."

    # Critical: Use --authfile to target persistent storage
    # Critical: Username must be quoted to handle pipe character
    log_info "Authenticating to: $REGISTRY_URL"
    log_info "Username format: <numeric-id>|<service-account-name>"

    if echo "$REGISTRY_PASSWORD" | podman login \
        --authfile="$PERSISTENT_AUTH_FILE" \
        --username "$REGISTRY_USERNAME" \
        --password-stdin \
        "$REGISTRY_URL"; then
        log_success "Authentication successful"
    else
        die "Podman login failed. Check credentials and network connectivity."
    fi

    log_success "Phase 3 complete: Rootless login executed"
}

# ============================================================================
# Phase 4: Validation of DAC Permissions
# ============================================================================

validate_dac_permissions() {
    log_info "Phase 4: Validating Discretionary Access Control permissions..."

    if [ ! -f "$PERSISTENT_AUTH_FILE" ]; then
        die "auth.json not found at: $PERSISTENT_AUTH_FILE"
    fi

    # Check file permissions
    local file_perms
    file_perms=$(stat -c '%a' "$PERSISTENT_AUTH_FILE")

    if [ "$file_perms" != "600" ]; then
        log_warning "Incorrect permissions: $file_perms (expected: 600)"
        chmod 600 "$PERSISTENT_AUTH_FILE"
        log_success "Corrected permissions to 600"
    else
        log_success "Permissions correct: $file_perms"
    fi

    # Check file ownership
    local file_owner
    file_owner=$(stat -c '%U:%G' "$PERSISTENT_AUTH_FILE")

    if [ "$file_owner" != "${CURRENT_USER}:$(id -gn)" ]; then
        die "Ownership mismatch. Expected: ${CURRENT_USER}:$(id -gn), Got: $file_owner"
    fi

    log_success "Ownership correct: $file_owner"

    # Display security matrix
    echo ""
    log_info "Security Matrix:"
    echo "  File:        $PERSISTENT_AUTH_FILE"
    echo "  Permissions: $file_perms (rw-------)"
    echo "  Owner:       $file_owner"
    echo "  UID/GID:     ${CURRENT_UID}:${CURRENT_GID}"
    echo ""

    log_success "Phase 4 complete: DAC permissions validated"
}

# ============================================================================
# Phase 5: Global Environmental Export
# ============================================================================

export_environment_variables() {
    log_info "Phase 5: Exporting global environment variables..."

    local bashrc="${HOME}/.bashrc"
    local env_exports=(
        "# Rootless Podman Authentication (ADR-0030)"
        "# Required for ansible-builder subprocess authentication"
        "export XDG_RUNTIME_DIR=\"/run/user/\$(id -u)\""
        "export REGISTRY_AUTH_FILE=\"\${HOME}/.config/containers/auth.json\""
    )

    # Check if already present
    if grep -q "REGISTRY_AUTH_FILE" "$bashrc" 2>/dev/null; then
        log_info "REGISTRY_AUTH_FILE already exported in ~/.bashrc"
    else
        log_info "Adding environment exports to ~/.bashrc..."
        {
            echo ""
            for line in "${env_exports[@]}"; do
                echo "$line"
            done
        } >> "$bashrc"
        log_success "Environment variables added to ~/.bashrc"
    fi

    # Export for current session
    export XDG_RUNTIME_DIR="/run/user/${CURRENT_UID}"
    export REGISTRY_AUTH_FILE="$PERSISTENT_AUTH_FILE"

    log_success "Environment variables exported for current session"

    # Display export instructions
    echo ""
    log_info "Environment Configuration:"
    echo "  XDG_RUNTIME_DIR:     $XDG_RUNTIME_DIR"
    echo "  REGISTRY_AUTH_FILE:  $REGISTRY_AUTH_FILE"
    echo ""
    log_warning "To activate in NEW shell sessions, run:"
    echo "  source ~/.bashrc"
    echo ""

    log_success "Phase 5 complete: Environment variables configured"
}

# ============================================================================
# Verification and Testing
# ============================================================================

verify_authentication() {
    log_info "Verification: Testing authentication with Podman..."

    # Test that Podman can access the persistent auth file
    if podman info --format "{{.Host.RemoteSocket.Exists}}" &>/dev/null; then
        log_success "Podman runtime accessible"
    else
        log_warning "Podman info check failed (non-critical)"
    fi

    # Verify auth.json is valid JSON
    if command -v jq &>/dev/null; then
        if jq empty "$PERSISTENT_AUTH_FILE" 2>/dev/null; then
            log_success "auth.json is valid JSON"
        else
            log_warning "auth.json may be malformed"
        fi
    fi

    log_info "Authentication setup complete!"
}

display_next_steps() {
    cat <<EOF

${GREEN}═══════════════════════════════════════════════════════════════${NC}
  Rootless Podman Authentication Setup Complete ✓
${GREEN}═══════════════════════════════════════════════════════════════${NC}

${BLUE}Next Steps:${NC}

  1. ${YELLOW}Activate environment in current shell:${NC}
     ${GREEN}source ~/.bashrc${NC}

  2. ${YELLOW}Build custom Execution Environment:${NC}
     ${GREEN}cd /home/vpcuser/ocp4-aap-execution-environment${NC}
     ${GREEN}ansible-builder build --tag quay.io/USER/ocp4-aap-execution-environment:latest --container-runtime podman -v 3${NC}

  3. ${YELLOW}Or use the playbook (now with become: false):${NC}
     ${GREEN}ansible-playbook -i inventory/ibm-cloud.yml playbooks/build-custom-ee.yml \\
       -e@extra_vars/rhel-subscription-secrets.yml --vault-password-file ~/.vault_pass${NC}

${BLUE}Architecture Notes:${NC}

  • Authentication persists across reboots (stored in ${HOME}/.config)
  • All Podman operations run as ${CURRENT_USER} (UID ${CURRENT_UID})
  • ansible-builder subprocesses inherit REGISTRY_AUTH_FILE automatically
  • No sudo required for builds (rootless execution)

${BLUE}Troubleshooting:${NC}

  • If builds fail with "Unauthorized": Verify REGISTRY_AUTH_FILE is exported
  • If permission denied: Re-run this script to fix ownership
  • For verbose build output: Add -v 3 to ansible-builder commands

${GREEN}═══════════════════════════════════════════════════════════════${NC}

EOF
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo "${BLUE}Rootless Podman Authentication Setup v${SCRIPT_VERSION}${NC}"
    echo "ADR-0030: Rootless Podman Authentication Architecture"
    echo ""

    check_root
    check_dependencies
    parse_args "$@"

    echo ""
    log_info "Executing 5-phase remediation protocol..."
    echo ""

    eradicate_stale_artifacts
    echo ""

    establish_persistent_directories
    echo ""

    execute_rootless_login
    echo ""

    validate_dac_permissions
    echo ""

    export_environment_variables
    echo ""

    verify_authentication

    display_next_steps
}

main "$@"
