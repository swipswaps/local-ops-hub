#!/usr/bin/env bash
set -u

# ============================================================================
# deploy_and_verify.sh – Push, deploy, verify, and output raw GitHub evidence.
# Usage: ./deploy_and_verify.sh [COMMIT_SHA]
#   COMMIT_SHA: optional, defaults to HEAD.
# ============================================================================

# --------------------------------------------------------------------------
# Configuration (override via environment variables if needed)
# --------------------------------------------------------------------------
OWNER="${OWNER:-swipswaps}"
REPO="${REPO:-local-ops-hub}"
BRANCH="${BRANCH:-master}"
TIMEOUT="${TIMEOUT:-600}"         # seconds (10 min)
POLL_INTERVAL="${POLL_INTERVAL:-10}" # seconds
EXPECTED_TEXT="${EXPECTED_TEXT:-}" # optional; if empty, extracted from src/App.jsx

# --------------------------------------------------------------------------
# Helper: log to stderr without polluting stdout
# --------------------------------------------------------------------------
log() { echo "$*" >&2; }

# --------------------------------------------------------------------------
# 1. Determine commit to deploy
# --------------------------------------------------------------------------
COMMIT="${1:-$(git rev-parse HEAD)}"
log "Deploying commit: $COMMIT"

# Ensure the commit exists locally and is pushed to remote
if ! git cat-file -e "$COMMIT" 2>/dev/null; then
    log "ERROR: Commit $COMMIT does not exist locally."
    exit 1
fi

# Push the commit to the remote branch if not already there
if ! git branch -r --contains "$COMMIT" | grep -q "origin/${BRANCH}"; then
    log "Pushing commit $COMMIT to origin/${BRANCH}..."
    git push origin "$COMMIT:${BRANCH}" || {
        log "ERROR: Failed to push commit."
        exit 1
    }
fi

# --------------------------------------------------------------------------
# 2. Extract expected text from src/App.jsx (if not provided)
# --------------------------------------------------------------------------
if [ -z "$EXPECTED_TEXT" ]; then
    if [ -f src/App.jsx ]; then
        # Extract the text inside the span on line ~62 (the header)
        EXPECTED_TEXT=$(awk '/<span>.*<\/span>/ { if (match($0, /<span>([^<]*)<\/span>/, a)) print a[1]; }' src/App.jsx | head -1)
        # Fallback: if still empty, use a default
        if [ -z "$EXPECTED_TEXT" ]; then
            EXPECTED_TEXT="Local Ops & Architecture Hub"
        fi
        log "Expected text from src/App.jsx: $EXPECTED_TEXT"
    else
        log "WARNING: src/App.jsx not found. Expected text not set."
        EXPECTED_TEXT=""
    fi
fi

# --------------------------------------------------------------------------
# 3. Trigger workflow on the commit
# --------------------------------------------------------------------------
log "Triggering workflow on commit $COMMIT..."
gh workflow run "Deploy to GitHub Pages" --ref "$COMMIT" 2>/dev/null || {
    log "Workflow may already be running; continuing."
}

# Wait a moment for the run to appear
sleep 3

# Get the latest run ID for this workflow
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
if [ -z "$RUN_ID" ]; then
    log "ERROR: Could not retrieve workflow run ID."
    exit 1
fi
log "Run ID: $RUN_ID"

# --------------------------------------------------------------------------
# 4. Poll workflow status using raw JSON from the API
# --------------------------------------------------------------------------
log "Polling workflow status..."
START_TIME=$(date +%s)
while true; do
    NOW=$(date +%s)
    if [ $((NOW - START_TIME)) -ge "$TIMEOUT" ]; then
        log "ERROR: Timeout waiting for workflow to complete."
        # Output the last known JSON as error evidence
        echo "=== Last known workflow JSON ==="
        gh api "repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}" 2>/dev/null
        exit 1
    fi

    # Fetch raw JSON
    RAW_JSON=$(gh api "repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}" 2>/dev/null)
    STATUS=$(echo "$RAW_JSON" | jq -r '.status // "unknown"')
    CONCLUSION=$(echo "$RAW_JSON" | jq -r '.conclusion // "null"')
    # Output raw JSON (this is the "prose-free" diagnostic data)
    echo "--- Poll at $(date -u +%Y-%m-%dT%H:%M:%SZ) ---"
    echo "$RAW_JSON" | jq -c '{id, status, conclusion, head_sha, created_at, updated_at}'

    if [ "$STATUS" = "completed" ]; then
        if [ "$CONCLUSION" != "success" ]; then
            log "ERROR: Workflow completed with conclusion: $CONCLUSION"
            # Dump the logs to help debug
            gh run view "$RUN_ID" --log 2>&1
            exit 1
        fi
        break
    fi
    sleep "$POLL_INTERVAL"
done

# --------------------------------------------------------------------------
# 5. Capture workflow logs and push them (to obtain a raw link)
# --------------------------------------------------------------------------
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
LOG_FILE="notes/workflow_logs_${TIMESTAMP}.txt"
mkdir -p notes

log "Capturing workflow logs to $LOG_FILE..."
gh run view "$RUN_ID" --log > "$LOG_FILE" 2>&1

git add -f "$LOG_FILE"
git commit --no-verify -m "Logs: workflow $RUN_ID $TIMESTAMP" 2>/dev/null
git push origin "$BRANCH" 2>/dev/null

RAW_LOG_LINK="https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}/${LOG_FILE}"
echo "📄 Raw workflow log link:"
echo "$RAW_LOG_LINK"

# --------------------------------------------------------------------------
# 6. Poll the live site until the expected text appears
# --------------------------------------------------------------------------
PAGES_URL="https://${OWNER}.github.io/${REPO}/"
log "Polling live site at $PAGES_URL for expected text: '$EXPECTED_TEXT'"

START_TIME=$(date +%s)
while true; do
    NOW=$(date +%s)
    if [ $((NOW - START_TIME)) -ge "$TIMEOUT" ]; then
        log "ERROR: Timeout waiting for live site to update."
        echo "=== Last live site snippet ==="
        curl -s -m 5 "${PAGES_URL}?v=${NOW}" 2>/dev/null | grep -i 'README\|Rules' | head -5
        exit 1
    fi

    # Fetch page with cache-busting
    LIVE_HTML=$(curl -s -m 5 "${PAGES_URL}?v=${NOW}" 2>/dev/null)
    if echo "$LIVE_HTML" | grep -q "$EXPECTED_TEXT"; then
        log "✅ Live site contains expected text."
        echo "Live site URL: $PAGES_URL"
        echo "Expected text found: $EXPECTED_TEXT"
        break
    else
        # Output the current HTTP status and a snippet for diagnostics
        HTTP_STATUS=$(echo "$LIVE_HTML" | head -n 1 | grep -o 'HTTP/2 200\|404' || echo "unknown")
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] live_status=$HTTP_STATUS text_not_found"
        sleep "$POLL_INTERVAL"
    fi
done

# --------------------------------------------------------------------------
# 7. Final summary (raw links and status)
# --------------------------------------------------------------------------
echo ""
echo "=== Deployment Evidence ==="
echo "Commit: $COMMIT"
echo "Run ID: $RUN_ID"
echo "Raw log link: $RAW_LOG_LINK"
echo "Live site: $PAGES_URL"
echo "Expected text found: $EXPECTED_TEXT"
