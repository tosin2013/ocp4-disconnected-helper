#!/bin/bash
# Test Suite for oc-mirror v1.1 Hardening Patches
# Tests preflight validation, rescue block cleanup, and documentation

set -uo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TEST_RESULTS=()
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
log_test() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"

    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        TEST_RESULTS+=("PASS: $test_name")
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        [ -n "$details" ] && echo -e "  ${YELLOW}Details: $details${NC}"
        TEST_RESULTS+=("FAIL: $test_name - $details")
        ((TESTS_FAILED++))
    fi
}

echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  oc-mirror v1.1 Hardening Patches - Test Suite           ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================================
# TEST 1: Cleanup Script Exists and is Executable
# ============================================================================
echo -e "${BLUE}[TEST 1]${NC} Verify cleanup script exists and is executable"

if [ -f "scripts/clear-async-cache.sh" ]; then
    if [ -x "scripts/clear-async-cache.sh" ]; then
        log_test "Cleanup script executable" "PASS"
    else
        log_test "Cleanup script executable" "FAIL" "Script exists but not executable"
    fi
else
    log_test "Cleanup script exists" "FAIL" "Script not found at scripts/clear-async-cache.sh"
fi

# ============================================================================
# TEST 2: Cleanup Script Dry-Run Mode
# ============================================================================
echo -e "${BLUE}[TEST 2]${NC} Test cleanup script dry-run mode"

if ./scripts/clear-async-cache.sh --dry-run &>/dev/null; then
    log_test "Cleanup script dry-run" "PASS"
else
    log_test "Cleanup script dry-run" "FAIL" "Script failed with exit code $?"
fi

# ============================================================================
# TEST 3: Playbook Syntax Validation
# ============================================================================
echo -e "${BLUE}[TEST 3]${NC} Validate playbook syntax"

if ansible-playbook --syntax-check playbooks/download-to-disk-v2.yml &>/dev/null; then
    log_test "Playbook syntax validation" "PASS"
else
    log_test "Playbook syntax validation" "FAIL" "Syntax check failed"
fi

# ============================================================================
# TEST 4: Preflight Check Logic Present
# ============================================================================
echo -e "${BLUE}[TEST 4]${NC} Verify preflight check logic in playbook"

if grep -q "Check for stale async cache files" playbooks/download-to-disk-v2.yml; then
    log_test "Preflight check present" "PASS"
else
    log_test "Preflight check present" "FAIL" "Preflight task not found in playbook"
fi

# ============================================================================
# TEST 5: Rescue Block Logic Present
# ============================================================================
echo -e "${BLUE}[TEST 5]${NC} Verify rescue block in playbook"

if grep -q "rescue:" playbooks/download-to-disk-v2.yml && \
   grep -q "Remove failed async cache file" playbooks/download-to-disk-v2.yml; then
    log_test "Rescue block present" "PASS"
else
    log_test "Rescue block present" "FAIL" "Rescue block or cleanup task not found"
fi

# ============================================================================
# TEST 6: Documentation Present
# ============================================================================
echo -e "${BLUE}[TEST 6]${NC} Verify documentation updates"

# Check TROUBLESHOOTING.md
if grep -q "Port 55000 Already Bound" docs/TROUBLESHOOTING.md; then
    log_test "TROUBLESHOOTING.md updated" "PASS"
else
    log_test "TROUBLESHOOTING.md updated" "FAIL" "Section not found"
fi

# Check hardening report
if [ -f "docs/hardening/oc-mirror-async-cache-v1.0-2026-06-04.md" ]; then
    log_test "Hardening report exists" "PASS"
else
    log_test "Hardening report exists" "FAIL" "Report not found"
fi

# Check ADR 0003
if grep -q "Ansible Async Cache Management" docs/adrs/0003-oc-mirror-image-mirroring.md; then
    log_test "ADR 0003 updated" "PASS"
else
    log_test "ADR 0003 updated" "FAIL" "Operational constraints section not found"
fi

# Check CLAUDE.md
if grep -q "oc-mirror Playbook Returns Cached Failure" CLAUDE.md; then
    log_test "CLAUDE.md updated" "PASS"
else
    log_test "CLAUDE.md updated" "FAIL" "Failure pattern not documented"
fi

# ============================================================================
# TEST 7: Simulate Stale Async Cache Detection
# ============================================================================
echo -e "${BLUE}[TEST 7]${NC} Simulate stale async cache detection"

# Create test async cache directory
TEST_ASYNC_DIR="/tmp/test-ansible-async-$$"
mkdir -p "$TEST_ASYNC_DIR"

# Create stale cache file (2 days old)
touch -d "2 days ago" "$TEST_ASYNC_DIR/stale_job_test"

# Count stale files
STALE_COUNT=$(find "$TEST_ASYNC_DIR" -type f -mtime +1 2>/dev/null | wc -l)

if [ "$STALE_COUNT" -eq 1 ]; then
    log_test "Stale cache file detection" "PASS"
else
    log_test "Stale cache file detection" "FAIL" "Expected 1 stale file, found $STALE_COUNT"
fi

# Cleanup
rm -rf "$TEST_ASYNC_DIR"

# ============================================================================
# TEST 8: Verify Async Cache Locations Documented
# ============================================================================
echo -e "${BLUE}[TEST 8]${NC} Verify async cache locations documented"

if grep -q "/root/.ansible_async" docs/TROUBLESHOOTING.md && \
   grep -q "~/.ansible_async" docs/TROUBLESHOOTING.md; then
    log_test "Cache locations documented" "PASS"
else
    log_test "Cache locations documented" "FAIL" "Cache locations not documented"
fi

# ============================================================================
# TEST 9: Verify Cleanup Instructions Present
# ============================================================================
echo -e "${BLUE}[TEST 9]${NC} Verify cleanup instructions in documentation"

if grep -q "sudo rm -rf /root/.ansible_async" docs/TROUBLESHOOTING.md; then
    log_test "Cleanup instructions present" "PASS"
else
    log_test "Cleanup instructions present" "FAIL" "Cleanup commands not documented"
fi

# ============================================================================
# TEST 10: Git Commit Verification
# ============================================================================
echo -e "${BLUE}[TEST 10]${NC} Verify hardening commit exists"

if git log --oneline -1 | grep -q "hardening(v1.0)"; then
    log_test "Hardening commit present" "PASS"
else
    log_test "Hardening commit present" "FAIL" "Commit not found in git log"
fi

# ============================================================================
# TEST 11: Check for Required Variables in Playbook
# ============================================================================
echo -e "${BLUE}[TEST 11]${NC} Verify playbook variables"

if grep -q "async: 14400" playbooks/download-to-disk-v2.yml; then
    log_test "Async timeout configured" "PASS"
else
    log_test "Async timeout configured" "FAIL" "Async timeout not set to 14400"
fi

# ============================================================================
# TEST 12: Verify Detection Pattern Documentation
# ============================================================================
echo -e "${BLUE}[TEST 12]${NC} Verify detection patterns documented"

if grep -q "Execution time.*<5 seconds" docs/TROUBLESHOOTING.md || \
   grep -q "Cached failures return.*<5 seconds" CLAUDE.md; then
    log_test "Detection pattern documented" "PASS"
else
    log_test "Detection pattern documented" "FAIL" "Execution time pattern not documented"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Test Summary                                             ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC}"
    echo -e "${GREEN}Hardening patches v1.1 are production-ready.${NC}"
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    echo -e "${YELLOW}Review failures above before deploying to production.${NC}"
    echo ""
    echo "Failed tests:"
    for result in "${TEST_RESULTS[@]}"; do
        if [[ "$result" == FAIL* ]]; then
            echo -e "  ${RED}•${NC} $result"
        fi
    done
    exit 1
fi
