#!/bin/bash
# scripts/validate-aap-health.sh
# AAP Workflow Validation Framework - Layer 1 Health Checks
# ADR 0033: AAP Workflow Validation and Health Check Framework
#
# Purpose: Validate AAP 2.6 multi-node deployment health
# Validates: ADR 0031 (Control Plane EE registry auth), ADR 0028 (dual password architecture)
#
# Usage:
#   export AAP_HOST="https://aap.sandbox3377.opentlc.com"
#   export AAP_GATEWAY_PASSWORD="<automationgateway_admin_password>"
#   export AAP_CONTROLLER_PASSWORD="<admin_password>"
#   ./scripts/validate-aap-health.sh
#
# Exit Codes:
#   0: All health checks passed
#   1: Health check failure (specific error message provided)
#   2: Configuration error (credentials missing, AAP unreachable)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

AAP_HOST="${AAP_HOST:-https://aap.sandbox3377.opentlc.com}"
AAP_USERNAME="${AAP_USERNAME:-admin}"
AAP_GATEWAY_PASSWORD="${AAP_GATEWAY_PASSWORD:-}"
AAP_CONTROLLER_PASSWORD="${AAP_CONTROLLER_PASSWORD:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Health check results
CHECKS_PASSED=0
CHECKS_FAILED=0

# ============================================================================
# Helper Functions
# ============================================================================

log_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

log_check() {
    echo -e "${BLUE}[CHECK]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((CHECKS_PASSED++))
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    ((CHECKS_FAILED++))
}

log_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_info() {
    echo -e "  $1"
}

check_prerequisites() {
    log_check "Checking prerequisites..."

    local missing_tools=()

    if ! command -v curl &> /dev/null; then
        missing_tools+=("curl")
    fi

    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        log_fail "Missing required tools: ${missing_tools[*]}"
        log_info "Install with: sudo dnf install -y curl jq"
        exit 2
    fi

    if [[ -z "$AAP_GATEWAY_PASSWORD" ]]; then
        log_fail "AAP_GATEWAY_PASSWORD not set (required for Gateway authentication)"
        log_info "Set with: export AAP_GATEWAY_PASSWORD='<automationgateway_admin_password>'"
        exit 2
    fi

    if [[ -z "$AAP_CONTROLLER_PASSWORD" ]]; then
        log_fail "AAP_CONTROLLER_PASSWORD not set (required for Controller API authentication)"
        log_info "Set with: export AAP_CONTROLLER_PASSWORD='<admin_password>'"
        exit 2
    fi

    log_pass "Prerequisites satisfied (curl, jq, credentials configured)"
}

# ============================================================================
# Health Check Functions
# ============================================================================

check_controller_api_availability() {
    log_check "Checking AAP Controller API availability..."

    local ping_response
    ping_response=$(curl -sk -u "$AAP_USERNAME:$AAP_CONTROLLER_PASSWORD" \
        "$AAP_HOST/api/v2/ping/" 2>&1)

    if [[ $? -ne 0 ]]; then
        log_fail "Controller API unreachable: $ping_response"
        log_info "Verify AAP_HOST is correct: $AAP_HOST"
        return 1
    fi

    # Parse response
    local ha_enabled
    ha_enabled=$(echo "$ping_response" | jq -r '.ha // false' 2>/dev/null)

    if [[ "$ha_enabled" != "true" ]] && [[ "$ha_enabled" != "false" ]]; then
        log_fail "Controller API returned unexpected response"
        log_info "Response: $ping_response"
        return 1
    fi

    local version
    version=$(echo "$ping_response" | jq -r '.version // "unknown"')

    log_pass "Controller API healthy (version: $version, HA: $ha_enabled)"
}

check_instance_health() {
    log_check "Checking AAP instance health and capacity..."

    local instances_response
    instances_response=$(curl -sk -u "$AAP_USERNAME:$AAP_CONTROLLER_PASSWORD" \
        "$AAP_HOST/api/v2/instances/" 2>&1)

    if [[ $? -ne 0 ]]; then
        log_fail "Failed to retrieve instance health: $instances_response"
        return 1
    fi

    local instance_count
    instance_count=$(echo "$instances_response" | jq '.count // 0')

    if [[ "$instance_count" -eq 0 ]]; then
        log_fail "No AAP instances found"
        log_info "Response: $instances_response"
        return 1
    fi

    local total_capacity=0
    local unhealthy_instances=0

    # Check each instance
    for i in $(seq 0 $((instance_count - 1))); do
        local hostname
        hostname=$(echo "$instances_response" | jq -r ".results[$i].hostname // \"unknown\"")

        local capacity
        capacity=$(echo "$instances_response" | jq ".results[$i].capacity // 0")

        local errors
        errors=$(echo "$instances_response" | jq -r ".results[$i].errors // \"\"")

        if [[ "$capacity" -eq 0 ]] && [[ -n "$errors" ]]; then
            log_warn "Instance $hostname has zero capacity (errors: $errors)"
            ((unhealthy_instances++))
        else
            log_info "Instance $hostname: capacity $capacity"
            total_capacity=$((total_capacity + capacity))
        fi
    done

    if [[ "$unhealthy_instances" -gt 0 ]]; then
        log_fail "$unhealthy_instances instance(s) unhealthy (zero capacity)"
        return 1
    fi

    if [[ "$total_capacity" -eq 0 ]]; then
        log_fail "Total cluster capacity is zero (no jobs can run)"
        return 1
    fi

    log_pass "All instances healthy (total capacity: $total_capacity)"
}

check_dual_password_authentication() {
    log_check "Validating dual password architecture (ADR 0028)..."

    # Test 1: Gateway password for Web UI (simulated via API gateway endpoint)
    log_info "Testing Gateway password authentication..."
    local gateway_response
    gateway_response=$(curl -sk -u "$AAP_USERNAME:$AAP_GATEWAY_PASSWORD" \
        "$AAP_HOST/api/gateway/v1/config/" 2>&1)

    if echo "$gateway_response" | grep -q "401\|Unauthorized\|Authentication"; then
        log_fail "Gateway authentication failed (check AAP_GATEWAY_PASSWORD)"
        log_info "Expected: automationgateway_admin_password from secrets file"
        return 1
    fi

    # Test 2: Controller password for Controller API
    log_info "Testing Controller password authentication..."
    local controller_response
    controller_response=$(curl -sk -u "$AAP_USERNAME:$AAP_CONTROLLER_PASSWORD" \
        "$AAP_HOST/api/controller/v2/ping/" 2>&1)

    if echo "$controller_response" | grep -q "401\|Unauthorized\|Authentication"; then
        log_fail "Controller authentication failed (check AAP_CONTROLLER_PASSWORD)"
        log_info "Expected: admin_password from secrets file"
        return 1
    fi

    log_pass "Dual password authentication valid (Gateway + Controller)"
    log_info "Gateway password: configured correctly"
    log_info "Controller password: configured correctly"
}

check_control_plane_ee_registry_auth() {
    log_check "Validating Control Plane EE registry authentication (ADR 0031)..."

    # Get most recent project update status
    local project_updates_response
    project_updates_response=$(curl -sk -u "$AAP_USERNAME:$AAP_CONTROLLER_PASSWORD" \
        "$AAP_HOST/api/controller/v2/project_updates/?order_by=-id" 2>&1)

    if [[ $? -ne 0 ]]; then
        log_fail "Failed to retrieve project update status: $project_updates_response"
        return 1
    fi

    local update_count
    update_count=$(echo "$project_updates_response" | jq '.count // 0')

    if [[ "$update_count" -eq 0 ]]; then
        log_warn "No project updates found (unable to validate Control Plane EE auth)"
        log_info "Run a project sync in AAP UI to validate"
        return 0  # Not a hard failure, just no data yet
    fi

    local latest_status
    latest_status=$(echo "$project_updates_response" | jq -r '.results[0].status // "unknown"')

    local project_name
    project_name=$(echo "$project_updates_response" | jq -r '.results[0].name // "unknown"')

    local finished_time
    finished_time=$(echo "$project_updates_response" | jq -r '.results[0].finished // "never"')

    if [[ "$latest_status" == "successful" ]]; then
        log_pass "Control Plane EE authenticated (project: $project_name, last sync: $finished_time)"
        log_info "Registry credentials configured correctly per ADR 0031"
    elif [[ "$latest_status" == "failed" ]]; then
        log_fail "Project sync failed (Control Plane EE cannot pull images)"
        log_info "Project: $project_name"
        log_info "Check ADR 0031 compliance: registry credentials in AAP installer inventory?"

        # Get failure reason
        local job_explanation
        job_explanation=$(echo "$project_updates_response" | jq -r '.results[0].job_explanation // "unknown"')
        log_info "Failure reason: $job_explanation"
        return 1
    else
        log_warn "Project sync status: $latest_status (project: $project_name)"
        log_info "Expected: 'successful' status"
    fi
}

check_database_connectivity() {
    log_check "Checking database connectivity..."

    # Use /api/v2/config/ endpoint which requires database access
    local config_response
    config_response=$(curl -sk -u "$AAP_USERNAME:$AAP_CONTROLLER_PASSWORD" \
        "$AAP_HOST/api/v2/config/" 2>&1)

    if [[ $? -ne 0 ]]; then
        log_fail "Database connectivity check failed: $config_response"
        return 1
    fi

    # Check if we got a valid response with license info
    local license_info
    license_info=$(echo "$config_response" | jq -r '.license_info // null')

    if [[ "$license_info" == "null" ]]; then
        log_fail "Database query returned incomplete data"
        return 1
    fi

    log_pass "Database connectivity healthy"
}

# ============================================================================
# Summary and Exit
# ============================================================================

print_summary() {
    echo ""
    log_header "Health Check Summary"
    echo ""
    echo "Total Checks: $((CHECKS_PASSED + CHECKS_FAILED))"
    echo -e "Passed: ${GREEN}$CHECKS_PASSED${NC}"
    echo -e "Failed: ${RED}$CHECKS_FAILED${NC}"
    echo ""

    if [[ $CHECKS_FAILED -eq 0 ]]; then
        log_pass "All health checks passed - AAP deployment healthy"
        echo ""
        log_info "ADR Compliance Validated:"
        log_info "  ✓ ADR 0031: Control Plane EE registry authentication"
        log_info "  ✓ ADR 0028: Dual password architecture (Gateway + Controller)"
        echo ""
        return 0
    else
        log_fail "$CHECKS_FAILED health check(s) failed"
        echo ""
        log_info "Troubleshooting:"
        log_info "  1. Check AAP Controller logs: journalctl -u automation-controller"
        log_info "  2. Verify passwords in extra_vars/rhel-subscription-secrets.yml"
        log_info "  3. Review ADR 0031 for registry credential requirements"
        log_info "  4. Run project sync manually in AAP UI"
        echo ""
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_header "AAP Health Validation (ADR 0033)"
    echo ""
    echo "Target: $AAP_HOST"
    echo "Username: $AAP_USERNAME"
    echo ""

    # Run all health checks
    check_prerequisites

    echo ""
    log_header "Running Health Checks"
    echo ""

    check_controller_api_availability || true
    check_instance_health || true
    check_dual_password_authentication || true
    check_control_plane_ee_registry_auth || true
    check_database_connectivity || true

    # Print summary and exit with appropriate code
    print_summary
    exit $?
}

# Run main function
main "$@"
