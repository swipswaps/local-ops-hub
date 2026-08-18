#!/usr/bin/env bash
set -u

# Helper: log to stderr only
log() { echo "$*" >&2; }

# Set credential helper (quietly)
git config --global credential.helper '!gh auth git-credential' 2>/dev/null
git config --local credential.helper '!gh auth git-credential' 2>/dev/null

TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
DIAG_FILE="notes/diagnostic_raw_${TIMESTAMP}.txt"
mkdir -p notes

# Start the file with a header
{
    echo "=== Diagnostic Raw Data ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
} > "$DIAG_FILE"

echo "=== Triggering workflow ===" | tee -a "$DIAG_FILE"
gh workflow run "Deploy to GitHub Pages" --ref master 2>&1 | tee -a "$DIAG_FILE"

# Wait for a run to appear
RUN_ID=""
for i in {1..15}; do
    RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
    if [ -n "$RUN_ID" ]; then
        break
    fi
    sleep 5
done

if [ -z "$RUN_ID" ]; then
    echo "ERROR: No run ID found." | tee -a "$DIAG_FILE"
    gh run list --workflow="deploy.yml" --limit 5 --json databaseId,status,conclusion,displayTitle >> "$DIAG_FILE" 2>&1
    exit 1
fi

echo "Run ID: $RUN_ID" | tee -a "$DIAG_FILE"
echo "Polling every 10s for completion (printing raw JSON each time)..." | tee -a "$DIAG_FILE"

poll_count=0
while true; do
    # Capture full raw JSON (no truncation)
    RAW_JSON=$(gh api "repos/swipswaps/local-ops-hub/actions/runs/$RUN_ID" 2>/dev/null)
    STATUS=$(echo "$RAW_JSON" | jq -r '.status // "unknown"')
    CONCLUSION=$(echo "$RAW_JSON" | jq -r '.conclusion // "null"')
    
    # Print raw JSON to stdout AND append to file
    echo "--- Poll $poll_count: $(date -u +%Y-%m-%dT%H:%M:%SZ) ---" | tee -a "$DIAG_FILE"
    echo "$RAW_JSON" | tee -a "$DIAG_FILE"
    echo "" | tee -a "$DIAG_FILE"
    
    if [ "$STATUS" = "completed" ]; then
        break
    fi
    poll_count=$((poll_count + 1))
    sleep 10
done

# Capture all additional raw data
{
    echo ""
    echo "=== Additional Raw Data ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "--- Full run JSON (final) ---"
    gh api "repos/swipswaps/local-ops-hub/actions/runs/$RUN_ID" 2>&1
    echo ""
    echo "--- All jobs JSON (paginated) ---"
    gh api "repos/swipswaps/local-ops-hub/actions/runs/$RUN_ID/jobs" --paginate 2>&1
    echo ""
    echo "--- Complete workflow logs (raw) ---"
    gh run view "$RUN_ID" --log 2>&1
} >> "$DIAG_FILE"

echo "Diagnostic file written: $DIAG_FILE" | tee -a "$DIAG_FILE"

# Force push and validate raw link
git add -f "$DIAG_FILE" 2>&1 | tee -a "$DIAG_FILE"
git commit --no-verify -m "Diagnostic: raw data $(date -u +%Y%m%d%H%M%S)" 2>&1 | tee -a "$DIAG_FILE"
git push origin master --force 2>&1 | tee -a "$DIAG_FILE"

RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${DIAG_FILE}"

# Validate raw link with retry
echo "Validating raw link..." | tee -a "$DIAG_FILE"
HTTP_STATUS="000"
for attempt in {1..5}; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$RAW_LINK" 2>/dev/null || echo "000")
    echo "Attempt $attempt: HTTP $HTTP_STATUS" | tee -a "$DIAG_FILE"
    if [ "$HTTP_STATUS" = "200" ]; then
        break
    fi
    sleep 5
done

# Output only the raw link (or fallback)
if [ "$HTTP_STATUS" = "200" ]; then
    echo ""
    echo "$RAW_LINK"
else
    echo ""
    echo "⚠️ Raw link not reachable (HTTP $HTTP_STATUS). Fallback evidence:"
    echo "--- BEGIN DIAGNOSTIC ---"
    cat "$DIAG_FILE"
    echo "--- END DIAGNOSTIC ---"
fi
