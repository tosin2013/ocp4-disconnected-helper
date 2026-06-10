#!/bin/bash
# scripts/validate-aap-workflow-templates.sh
# AAP Workflow Validation Framework - Layer 1 Workflow Template Checks
# ADR 0033: AAP Workflow Validation and Health Check Framework
#
# Purpose: Validate AAP workflow templates configured correctly
# Validates: ADR 0032 (workflow orchestration patterns)
#
# Usage:
#   export AAP_HOST="https://aap.sandbox3377.opentlc.com"
#   export AAP_CONTROLLER_PASSWORD="<admin_password>"
#   ./scripts/validate-aap-workflow-templates.sh
#
# Exit Codes:
#   0: All workflow templates valid
#   1: Workflow template validation failure
#   2: Configuration error (credentials missing, AAP unreachable)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

AAP_HOST="${AAP_HOST:-https://aap.sandbox3377.opentlc.com}"
AAP_USERNAME="${AAP_USERNAME:-admin}"
AAP_CONTROLLER_PASSWORD="${AAP_CONTROLLER_PASSWORD:-}"

# Expected workflow templates (ADR 0032 two-workflow pattern)
EXPECTED_WORKFLOWS=(
    "Deploy Disconnected OpenShift Infrastructure"
    "Teardown Disconnected OpenShift Infrastructure"
    "Deploy Registry Infrastructure"
    "Teardown Registry Infrastructure"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Validation results
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

    if ! command -v curl &> /dev/null; then
        log_fail "curl not installed"
        exit 2
    fi

    if ! command -v jq &> /dev/null; then
        log_fail "jq not installed"
        exit 2
    fi

    if [[ -z "$AAP_CONTROLLER_PASSWORD" ]]; then
        log_fail "AAP_CONTROLLER_PASSWORD not set"
        log_info "Set with: export AAP_CONTROLLER_PASSWORD='<admin_password>'"
        exit 2
    fi

    log_pass "Prerequisites satisfied"
}

# ============================================================================
# Workflow Template Validation Functions
# ============================================================================

check_workflow_templates_exist() {
    log_check "Checking workflow templates existence..."

    local workflows_response
    workflows_response=$(curl -sk -u "$AAP_USERNAME:$AAP_CONTROLLER_PASSWORD" \
        "$AAP_HOST/api/v2/workflow_job_templates/" 2>&1)

    if [[ $? -ne 0 ]]; then
        log_fail "Failed to retrieve workflow templates: $workflows_response"
        return 1
    fi

    local workflow_count
    workflow_count=$(echo "$workflows_response" | jq '.count // 0')

    if [[ "$workflow_count" -eq 0 ]]; then
        log_fail "No workflow templates found in AAP"
        log_info "Run configuration playbooks first: playbooks/aap-configuration/"
        return 1
    fi

    log_info "Found $workflow_count workflow templates"

    # Check each expected workflow
    local missing_workflows=()
    for workflow_name in "${EXPECTED_WORKFLOWS[@]}"; do
        local workflow_exists
        workflow_exists=$(echo "$workflows_response" | jq -r \
            ".results[] | select(.name == \"$workflow_name\") | .name" 2>/dev/null)

        if [[ -z "$workflow_exists" ]]; then
            missing_workflows+=("$workflow_name")
            log_warn "Missing workflow: $workflow_name"
        else
            log_info "✓ $workflow_name"
        fi
    done

    if [[ ${#missing_workflows[@]} -gt 0 ]]; then
        log_fail "${#missing_workflows[@]} expected workflow(s) missing"
        log_info "Run: ansible-playbook playbooks/aap-configuration/configure-*-workflows.yml"
        return 1
    fi

    log_pass "All expected workflow templates exist (${#EXPECTED_WORKFLOWS[@]} workflows)"
}

check_workflow_node_connectivity() {
    log_check "Validating workflow node connectivity..."

    local workflows_response
    workflows_response=$(curl -sk -u "$AAP_USERNAME:$AAP_CONTROLLER_PASSWORD" \
        "$AAP_HOST/api/v2/workflow_job_templates/" 2>&1)

    local total_nodes=0
    local orphaned_nodes=0

    for workflow_name in "${EXPECTED_WORKFLOWS[@]}"; do
        local workflow_id
        workflow_id=$(echo "$workflows_response" | jq -r \
            ".results[] | select(.name == \"$workflow_name\") | .id" 2>/dev/null)

        if [[ -z "$workflow_id" ]]; then
            continue
        fi

        # Get workflow nodes
        local nodes_response
        nodes_response=$(curl -sk -u "$AAP_USERNAME:$AAP_CONTROLLER_PASSWORD" \
            "$AAP_HOST/api/v2/workflow_job_templates/$workflow_id/workflow_nodes/" 2>&1)

        local node_count
        node_count=$(echo "$nodes_response" | jq '.count // 0')
        total_nodes=$((total_nodes + node_count))

        if [[ "$node_count" -eq 0 ]]; then
            log_warn "Workflow '$workflow_name' has no nodes configured"
            ((orphaned_nodes++))
        else
            log_info "$workflow_name: $node_count node(s)"
        fi
    done

    if [[ "$orphaned_nodes" -gt 0 ]]; then
        log_warn "$orphaned_nodes workflow(s) have no nodes"
        log_info "This may be expected for newly created workflows"
    fi

    if [[ "$total_nodes" -eq 0 ]]; then
        log_fail "No workflow nodes found across all workflows"
        return 1
    fi

    log_pass "Workflow nodes configured (total: $total_nodes nodes)"
}

check_job_template_references() {
    log_check "Validating job template references..."

    local job_templates_response
    job_templates_response=$(curl -sk -u "$AAP_USERNAME:$AAP_CONTROLLER_PASSWORD" \
        "$AAP_HOST/api/v2/job_templates/" 2>&1)

    if [[ $? -ne 0 ]]; then
        log_fail "Failed to retrieve job templates: $job_templates_response"
        return 1
    fi

    local template_count
    template_count=$(echo "$job_templates_response" | jq '.count // 0')

    if [[ "$template_count" -eq 0 ]]; then
        log_fail "No job templates found"
        log_info "Workflow nodes reference job templates - none configured"
        return 1
    fi

    # Check for common expected templates (from ADR 0032 pattern)
    local expected_templates=(
        "Check Registry VM Prerequisites"
        "Provision Registry VM"
        "Verify Registry Health"
        "Backup Registry Configuration"
        "Remove Registry Service"
        "Destroy Registry VM"
        "Teardown oc-mirror Workspace"
    )

    local found_count=0
    for template_name in "${expected_templates[@]}"; do
        local template_exists
        template_exists=$(echo "$job_templates_response" | jq -r \
            ".results[] | select(.name == \"$template_name\") | .name" 2>/dev/null)

        if [[ -n "$template_exists" ]]; then
            ((found_count++))
        fi
    done

    log_pass "Job templates available ($template_count total, $found_count expected templates found)"
}

check_workflow_ask_variables() {
    log_check "Checking workflow extra_vars configuration..."

    local workflows_response
    workflows_response=$(curl -sk -u "$AAP_USERNAME:$AAP_CONTROLLER_PASSWORD" \
        "$AAP_HOST/api/v2/workflow_job_templates/" 2>&1)

    local force_mode_count=0

    for workflow_name in "${EXPECTED_WORKFLOWS[@]}"; do
        if [[ "$workflow_name" == "Teardown"* ]]; then
            local workflow_data
            workflow_data=$(echo "$workflows_response" | jq -r \
                ".results[] | select(.name == \"$workflow_name\")" 2>/dev/null)

            local extra_vars
            extra_vars=$(echo "$workflow_data" | jq -r '.extra_vars // "{}"')

            # Check if force=true is set (fix from commit 68990bc)
            if echo "$extra_vars" | jq -e '.force == true' &>/dev/null; then
                log_info "$workflow_name: force=true configured ✓"
                ((force_mode_count++))
            else
                log_warn "$workflow_name: force=true NOT set (may block on prompts)"
                log_info "See commit 68990bc for fix"
            fi
        fi
    done

    if [[ "$force_mode_count" -gt 0 ]]; then
        log_pass "Teardown workflows configured with force=true ($force_mode_count workflows)"
    else
        log_warn "No teardown workflows have force=true set"
    fi
}

# ============================================================================
# Summary and Exit
# ============================================================================

print_summary() {
    echo ""
    log_header "Workflow Template Validation Summary"
    echo ""
    echo "Total Checks: $((CHECKS_PASSED + CHECKS_FAILED))"
    echo -e "Passed: ${GREEN}$CHECKS_PASSED${NC}"
    echo -e "Failed: ${RED}$CHECKS_FAILED${NC}"
    echo ""

    if [[ $CHECKS_FAILED -eq 0 ]]; then
        log_pass "All workflow template validations passed"
        echo ""
        log_info "ADR Compliance:"
        log_info "  ✓ ADR 0032: Two-workflow pattern implemented"
        log_info "  ✓ Workflow templates configured correctly"
        echo ""
        return 0
    else
        log_fail "$CHECKS_FAILED validation(s) failed"
        echo ""
        log_info "Troubleshooting:"
        log_info "  1. Run workflow configuration playbooks:"
        log_info "     ansible-playbook playbooks/aap-configuration/configure-registry-vm-workflows.yml"
        log_info "     ansible-playbook playbooks/aap-configuration/configure-teardown-workflow.yml"
        log_info "  2. Verify AAP project sync completed successfully"
        log_info "  3. Check workflow template configuration in AAP UI"
        echo ""
        return 1
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_header "AAP Workflow Template Validation (ADR 0033)"
    echo ""
    echo "Target: $AAP_HOST"
    echo "Username: $AAP_USERNAME"
    echo ""

    # Run all validation checks
    check_prerequisites

    echo ""
    log_header "Running Workflow Template Checks"
    echo ""

    check_workflow_templates_exist || true
    check_workflow_node_connectivity || true
    check_job_template_references || true
    check_workflow_ask_variables || true

    # Print summary and exit with appropriate code
    print_summary
    exit $?
}

# Run main function
main "$@"
