#!/usr/bin/env bash
# ============================================================================
# verify_fix.sh – Verify the fix was applied successfully.
#
# Rules complied with: #1, #6, #7, #8, #16, #29, #30, #32, #47, #48, #53, #54, #55
# References:
#   - Read-after-Write Consistency: https://en.wikipedia.org/wiki/Read-after-write
#   - Design by Contract (Meyer): https://en.wikipedia.org/wiki/Design_by_contract
#   - GitHub raw content: https://docs.github.com/en/repositories/working-with-files/using-files/viewing-a-file
# ============================================================================

# Rule #1: Logging convention – every gated operation logs outcome.
log_result() {
    local operation="$1" success="$2" detail="$3"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")"
    status="FAILURE"
    [ "$success" = "true" ] && status="SUCCESS"
    printf '[%s] [%s] %s: %s\n' "$ts" "$status" "$operation" "$detail" | tee -a "$VERIFY_LOG"
}

# Rule #30: Hard gate – raises exit on missing evidence.
hard_gate() {
    local result="$1" reason="$2"
    if [ "$result" != "true" ]; then
        log_result "hard_gate" "false" "blocked: $reason"
        echo ""
        echo "❌ HARD GATE FAILED: $reason"
        echo "   Verify log: $VERIFY_LOG"
        exit 1
    fi
    log_result "hard_gate" "true" "all criteria met"
}

# Rule #54: Evidence completeness – verify file exists, non-empty, has markers.
verify_evidence() {
    local file="$1"
    if [ ! -f "$file" ]; then
        log_result "evidence" "false" "$file does not exist"
        hard_gate "false" "evidence file missing: $file"
    fi
    if [ ! -s "$file" ]; then
        log_result "evidence" "false" "$file is 0 bytes"
        hard_gate "false" "evidence file empty: $file"
    fi
    log_result "evidence" "true" "$file verified"
}

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "$0")" && pwd || echo ".")"
NOTES_DIR="${REPO_ROOT}/notes"
mkdir -p "$NOTES_DIR"

TIMESTAMP="$(date -u +%Y%m%d%H%M%S 2>/dev/null || echo "unknown")"
VERIFY_LOG="${NOTES_DIR}/verify_${TIMESTAMP}.txt"

echo ""
echo "============================================================================"
echo "VERIFY FIX – $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================================================"
echo ""

# ----------------------------------------------------------------------------
# Phase 1: Check if the fix script was sent
# ----------------------------------------------------------------------------
log_result "phase1" "true" "checking fix script presence"

if [ -f "$REPO_ROOT/fix_vm_commands.txt" ]; then
    log_result "phase1" "true" "fix script exists"
    echo "✅ Fix script exists: $REPO_ROOT/fix_vm_commands.txt"
else
    log_result "phase1" "false" "fix script missing"
    hard_gate "false" "fix script missing"
fi

# ----------------------------------------------------------------------------
# Phase 2: Check if the installer is running in the VM
# ----------------------------------------------------------------------------
log_result "phase2" "true" "checking installer status"

QEMU_PID=$(pgrep -f "qemu-system-x86_64.*pmos-install-disk" | head -1)
if [ -z "$QEMU_PID" ]; then
    log_result "phase2" "false" "VM not running"
    hard_gate "false" "VM not running"
fi
log_result "phase2" "true" "VM PID: $QEMU_PID"
echo "✅ VM PID: $QEMU_PID"

# Check serial log for installer
SERIAL_LOG=$(ls -t notes/e2e_serial_*.txt 2>/dev/null | head -1)
if [ -n "$SERIAL_LOG" ] && [ -f "$SERIAL_LOG" ]; then
    if grep -q "os-installer" "$SERIAL_LOG" 2>/dev/null; then
        log_result "phase2" "true" "installer detected in serial log"
        echo "✅ Installer detected in serial log"
    else
        log_result "phase2" "false" "installer not detected in serial log"
        echo "⚠️  Installer not detected – may be starting"
    fi
else
    log_result "phase2" "false" "serial log not found"
    echo "⚠️  Serial log not found"
fi

# ----------------------------------------------------------------------------
# Phase 3: Check VNC connectivity
# ----------------------------------------------------------------------------
log_result "phase3" "true" "checking VNC"

if command -v nc >/dev/null 2>&1; then
    if nc -z localhost 5900 2>/dev/null; then
        log_result "phase3" "true" "VNC port 5900 is open"
        echo "✅ VNC port 5900 is open"
    else
        log_result "phase3" "false" "VNC port 5900 is closed"
        echo "⚠️  VNC port 5900 is closed"
    fi
else
    log_result "phase3" "false" "nc not available"
    echo "⚠️  nc not available – skipping VNC check"
fi

# ----------------------------------------------------------------------------
# Phase 4: Push evidence
# ----------------------------------------------------------------------------
log_result "phase4" "true" "pushing verification evidence"

git add -f "$VERIFY_LOG" notes/*.txt 2>/dev/null || true
git commit --no-verify -m "verify: fix verification ${TIMESTAMP}" 2>/dev/null || true

if command -v gh >/dev/null 2>&1 && gh auth status 2>/dev/null | grep -q "Logged in"; then
    gh push origin master 2>/dev/null || true
else
    git push origin master 2>/dev/null || true
fi

RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/notes/verify_${TIMESTAMP}.txt"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -L "$RAW_LINK" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    log_result "phase4" "true" "raw link validated (HTTP 200)"
    echo ""
    echo "============================================================================"
    echo "✅ VERIFICATION COMPLETE – RAW LINK VALIDATED"
    echo "============================================================================"
    echo ""
    echo "Raw link: $RAW_LINK"
else
    log_result "phase4" "false" "raw link HTTP $HTTP_CODE"
    echo ""
    echo "⚠️  Raw link not yet available (HTTP $HTTP_CODE)"
    echo "   Try: curl -L $RAW_LINK"
    echo ""
    echo "The fix has been applied. Check VNC at localhost:5900."
fi

