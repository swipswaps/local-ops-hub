#!/usr/bin/env bash
# Trigger workflow, poll with raw JSON, capture logs, push, print raw link

set -u

# Helper: log to stderr only
log() { echo "$*" >&2; }

# Set credential helper
git config --global credential.helper '!gh auth git-credential' 2>/dev/null
git config --local credential.helper '!gh auth git-credential' 2>/dev/null

TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
DIAG_FILE="notes/diagnostic_raw_${TIMESTAMP}.txt"
mkdir -p notes

log "=== Triggering workflow 'Deploy to GitHub Pages' ==="
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
    log "ERROR: No run ID found. Capturing recent runs list."
    echo "=== No active run found ===" >> "$DIAG_FILE"
    gh run list --workflow="deploy.yml" --limit 5 --json databaseId,status,conclusion,displayTitle >> "$DIAG_FILE" 2>&1
else
    log "Run ID: $RUN_ID"
    echo "=== Run ID: $RUN_ID ===" >> "$DIAG_FILE"
    log "Waiting for workflow to complete (polling every 10s)..."

    poll_count=0
    while true; do
        # Capture the full raw JSON using gh api
        RAW_JSON=$(gh api "repos/swipswaps/local-ops-hub/actions/runs/$RUN_ID" 2>/dev/null)
        STATUS=$(echo "$RAW_JSON" | jq -r '.status // "unknown"')
        CONCLUSION=$(echo "$RAW_JSON" | jq -r '.conclusion // "null"')
        # Append the raw JSON to the diagnostic file with a marker
        echo "--- Poll $poll_count: $(date -u +%Y-%m-%dT%H:%M:%SZ) ---" >> "$DIAG_FILE"
        echo "$RAW_JSON" >> "$DIAG_FILE"
        echo "" >> "$DIAG_FILE"
        log "Poll $poll_count: status=$STATUS conclusion=$CONCLUSION"
        if [ "$STATUS" = "completed" ]; then
            break
        fi
        poll_count=$((poll_count + 1))
        sleep 10
    done
fi

# Capture all raw data (logs, etc.)
{
    echo "=== Diagnostic Raw Data ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Run ID: ${RUN_ID:-none}"
    echo ""
    if [ -n "$RUN_ID" ]; then
        echo "--- Full run JSON (final) ---"
        gh api "repos/swipswaps/local-ops-hub/actions/runs/$RUN_ID" 2>&1
        echo ""
        echo "--- All jobs JSON (paginated) ---"
        gh api "repos/swipswaps/local-ops-hub/actions/runs/$RUN_ID/jobs" --paginate 2>&1
        echo ""
        echo "--- Complete workflow logs (raw) ---"
        gh run view "$RUN_ID" --log 2>&1
    else
        echo "--- No run found – showing recent runs ---"
        gh run list --workflow="deploy.yml" --limit 10 --json databaseId,status,conclusion,displayTitle,createdAt 2>&1
    fi
} >> "$DIAG_FILE"

log "Diagnostic file written: $DIAG_FILE"

# Force add, commit, and push
git add -f "$DIAG_FILE" 2>&1 | tee -a "$DIAG_FILE"
git commit --no-verify -m "Diagnostic: raw JSON $(date -u +%Y%m%d%H%M%S)" 2>&1 | tee -a "$DIAG_FILE"
git push origin master --force 2>&1 | tee -a "$DIAG_FILE"

# Build raw link
RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${DIAG_FILE}"

# Validate raw link with retry
log "Validating raw link..."
HTTP_STATUS="000"
for attempt in {1..5}; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$RAW_LINK" 2>/dev/null || echo "000")
    if [ "$HTTP_STATUS" = "200" ]; then
        log "Raw link validated (HTTP 200) on attempt $attempt"
        break
    fi
    log "Attempt $attempt: HTTP $HTTP_STATUS – waiting 5s..."
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
