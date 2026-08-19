#!/usr/bin/env bash
# ============================================================================
# test_baseline.sh – Foundational baseline test suite for pmOS scripts.
#
# This test suite verifies the ACTUAL scripts in the repository:
#   1. boot-pmos-virtio-tablet-fixed_0005.sh – canonical boot script
#   2. fix-pmos-installer.sh – canonical fix script
#
# Run with: ./scripts/test_baseline.sh
# ============================================================================

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIMESTAMP="$(date -u +%Y%m%d%H%M%S)"
TEST_LOG="${REPO_ROOT}/notes/baseline_test_${TIMESTAMP}.txt"

log_test() {
    local test_name="$1" result="$2" detail="$3"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '[%s] [%s] %s: %s\n' "$ts" "$result" "$test_name" "$detail" | tee -a "$TEST_LOG"
}

echo ""
echo "============================================================================"
echo "FOUNDATIONAL BASELINE TEST SUITE – $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================================================"
echo ""
echo "Repository: $REPO_ROOT"
echo "Test log: $TEST_LOG"
echo ""

# --- Test 1: Canonical boot script exists and is executable ---
echo "Test 1: Canonical boot script"
BOOT_SCRIPT="${REPO_ROOT}/boot-pmos-virtio-tablet-fixed_0005.sh"
if [ -f "$BOOT_SCRIPT" ] && [ -x "$BOOT_SCRIPT" ]; then
    log_test "boot_script_exists" "PASS" "$BOOT_SCRIPT is present and executable"
    echo "  ✅ Boot script present and executable"
else
    log_test "boot_script_exists" "FAIL" "$BOOT_SCRIPT missing or not executable"
    echo "  ❌ Boot script missing or not executable"
    exit 1
fi

# --- Test 2: Canonical fix script exists and is executable ---
echo ""
echo "Test 2: Canonical fix script"
FIX_SCRIPT="${REPO_ROOT}/fix-pmos-installer.sh"
if [ -f "$FIX_SCRIPT" ] && [ -x "$FIX_SCRIPT" ]; then
    log_test "fix_script_exists" "PASS" "$FIX_SCRIPT is present and executable"
    echo "  ✅ Fix script present and executable"
else
    log_test "fix_script_exists" "FAIL" "$FIX_SCRIPT missing or not executable"
    echo "  ❌ Fix script missing or not executable"
    exit 1
fi

# --- Test 3: Syntax check both scripts ---
echo ""
echo "Test 3: Syntax check"
if bash -n "$BOOT_SCRIPT" 2>/dev/null; then
    log_test "boot_syntax" "PASS" "boot script syntax OK"
    echo "  ✅ Boot script syntax OK"
else
    log_test "boot_syntax" "FAIL" "boot script syntax error"
    echo "  ❌ Boot script syntax error"
    exit 1
fi

if bash -n "$FIX_SCRIPT" 2>/dev/null; then
    log_test "fix_syntax" "PASS" "fix script syntax OK"
    echo "  ✅ Fix script syntax OK"
else
    log_test "fix_syntax" "FAIL" "fix script syntax error"
    echo "  ❌ Fix script syntax error"
    exit 1
fi

# --- Test 4: Boot script QEMU features ---
echo ""
echo "Test 4: Boot script QEMU features"
FEATURES_PASS=0
FEATURES_TOTAL=6

if grep -q 'qemu-system-x86_64' "$BOOT_SCRIPT" 2>/dev/null; then
    echo "  ✅ QEMU command present"
    FEATURES_PASS=$((FEATURES_PASS + 1))
else
    echo "  ❌ QEMU command missing"
fi

if grep -q '\-kernel' "$BOOT_SCRIPT" 2>/dev/null; then
    echo "  ✅ Kernel flag present"
    FEATURES_PASS=$((FEATURES_PASS + 1))
else
    echo "  ❌ Kernel flag missing"
fi

if grep -q '\-initrd' "$BOOT_SCRIPT" 2>/dev/null; then
    echo "  ✅ Initrd flag present"
    FEATURES_PASS=$((FEATURES_PASS + 1))
else
    echo "  ❌ Initrd flag missing"
fi

if grep -q '\-vnc' "$BOOT_SCRIPT" 2>/dev/null; then
    echo "  ✅ VNC flag present"
    FEATURES_PASS=$((FEATURES_PASS + 1))
else
    echo "  ❌ VNC flag missing"
fi

if grep -q '\-serial stdio' "$BOOT_SCRIPT" 2>/dev/null; then
    echo "  ✅ Serial console present"
    FEATURES_PASS=$((FEATURES_PASS + 1))
else
    echo "  ❌ Serial console missing"
fi

if grep -q '\-vga' "$BOOT_SCRIPT" 2>/dev/null; then
    echo "  ✅ VGA present"
    FEATURES_PASS=$((FEATURES_PASS + 1))
else
    echo "  ❌ VGA missing"
fi

if [ "$FEATURES_PASS" -eq "$FEATURES_TOTAL" ]; then
    log_test "boot_features" "PASS" "all $FEATURES_TOTAL features present"
    echo "  ✅ All boot script features validated"
else
    log_test "boot_features" "FAIL" "only $FEATURES_PASS/$FEATURES_TOTAL features present"
    echo "  ❌ Not all boot script features present"
    exit 1
fi

# --- Test 5: Fix script features ---
echo ""
echo "Test 5: Fix script features"
FIX_FEATURES_PASS=0
FIX_FEATURES_TOTAL=6

if grep -q 'log_result()' "$FIX_SCRIPT" 2>/dev/null; then
    echo "  ✅ log_result() present"
    FIX_FEATURES_PASS=$((FIX_FEATURES_PASS + 1))
else
    echo "  ❌ log_result() missing"
fi

if grep -q 'hard_gate()' "$FIX_SCRIPT" 2>/dev/null; then
    echo "  ✅ hard_gate() present"
    FIX_FEATURES_PASS=$((FIX_FEATURES_PASS + 1))
else
    echo "  ❌ hard_gate() missing"
fi

if grep -q 'polkit' "$FIX_SCRIPT" 2>/dev/null; then
    echo "  ✅ Polkit bypass present"
    FIX_FEATURES_PASS=$((FIX_FEATURES_PASS + 1))
else
    echo "  ❌ Polkit bypass missing"
fi

if grep -q 'symlink' "$FIX_SCRIPT" 2>/dev/null; then
    echo "  ✅ Symlink fix present"
    FIX_FEATURES_PASS=$((FIX_FEATURES_PASS + 1))
else
    echo "  ❌ Symlink fix missing"
fi

if grep -q 'tmpfs' "$FIX_SCRIPT" 2>/dev/null; then
    echo "  ✅ Tmpfs mount present"
    FIX_FEATURES_PASS=$((FIX_FEATURES_PASS + 1))
else
    echo "  ❌ Tmpfs mount missing"
fi

if grep -q 'chpasswd' "$FIX_SCRIPT" 2>/dev/null; then
    echo "  ✅ Password setting present"
    FIX_FEATURES_PASS=$((FIX_FEATURES_PASS + 1))
else
    echo "  ❌ Password setting missing"
fi

if [ "$FIX_FEATURES_PASS" -eq "$FIX_FEATURES_TOTAL" ]; then
    log_test "fix_features" "PASS" "all $FIX_FEATURES_TOTAL features present"
    echo "  ✅ All fix script features validated"
else
    log_test "fix_features" "FAIL" "only $FIX_FEATURES_PASS/$FIX_FEATURES_TOTAL features present"
    echo "  ❌ Not all fix script features present"
    exit 1
fi

# --- All tests passed ---
echo ""
echo "============================================================================"
echo "✅ ALL TESTS PASSED – BASELINE CONFIRMED"
echo "============================================================================"
echo ""
echo "Test log: $TEST_LOG"
echo ""
echo "The foundational baseline is now established:"
echo "  - Boot script: $BOOT_SCRIPT"
echo "  - Fix script: $FIX_SCRIPT"
echo ""
echo "Run this test suite again in CI to verify the baseline is maintained."
echo ""
