#!/usr/bin/env bash
set -u

# ============================================================================
# deploy_and_verify_realtime.sh – Real‑time deployment with live evidence.
# Usage: ./deploy_and_verify_realtime.sh [COMMIT_SHA]
# ============================================================================

OWNER="${OWNER:-swipswaps}"
REPO="${REPO:-local-ops-hub}"
BRANCH="${BRANCH:-master}"
TIMEOUT="${TIMEOUT:-600}"
POLL_INTERVAL="${POLL_INTERVAL:-10}"

log() { echo "$*" >&2; }

# --------------------------------------------------------------------------
# 1. Determine commit and inject a version marker into index.html
# --------------------------------------------------------------------------
COMMIT="${1:-$(git rev-parse HEAD)}"
VERSION_MARKER="DEPLOY_${COMMIT:0:8}"
log "Commit: $COMMIT"
log "Marker: $VERSION_MARKER"

# Inject marker if not already present
if ! grep -q "$VERSION_MARKER" index.html 2>/dev/null; then
    log "Injecting marker into index.html..."
    sed -i "s|<head>|<head>\n  <meta name=\"deploy-version\" content=\"$VERSION_MARKER\">|" index.html
    git add index.html
    git commit --no-verify -m "ci: inject version marker $VERSION_MARKER"
    COMMIT=$(git rev-parse HEAD)
    log "New commit: $COMMIT"
fi

# Push the commit
if ! git branch -r --contains "$COMMIT" | grep -q "origin/${BRANCH}"; then
    log "Pushing commit..."
    git push origin "$COMMIT:${BRANCH}" || { log "ERROR: Push failed."; exit 1; }
fi

# --------------------------------------------------------------------------
# 2. Trigger the workflow on that commit
# --------------------------------------------------------------------------
log "Triggering workflow on commit $COMMIT..."
gh workflow run "Deploy to GitHub Pages" --ref "$COMMIT" 2>/dev/null || log "Workflow may already be running."

# Wait for a run to appear
sleep 3
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
if [ -z "$RUN_ID" ]; then
    log "ERROR: No run ID found."
    exit 1
fi
log "Run ID: $RUN_ID"

# --------------------------------------------------------------------------
# 3. Poll and display real‑time status
# --------------------------------------------------------------------------
START_TIME=$(date +%s)
LAST_UPDATE=""
PAGES_URL="https://${OWNER}.github.io/${REPO}/"

echo "--- Real‑time deployment monitor ---"
echo "Run ID: $RUN_ID"
echo "Marker: $VERSION_MARKER"
echo ""

while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    if [ $ELAPSED -ge "$TIMEOUT" ]; then
        echo "ERROR: Timeout (${TIMEOUT}s) reached." >&2
        exit 1
    fi

    # 3a. Fetch workflow run status (raw JSON)
    RUN_JSON=$(gh api "repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}" 2>/dev/null)
    STATUS=$(echo "$RUN_JSON" | jq -r '.status // "unknown"')
    CONCLUSION=$(echo "$RUN_JSON" | jq -r '.conclusion // "null"')
    UPDATED_AT=$(echo "$RUN_JSON" | jq -r '.updated_at // "unknown"')
    LOGS_URL=$(echo "$RUN_JSON" | jq -r '.logs_url // ""')

    # 3b. Fetch jobs (to see step‑by‑step progress)
    JOBS_JSON=$(gh api "repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}/jobs" 2>/dev/null)

    # 3c. Print status and jobs (raw JSON, compact)
    echo "--- Poll at $(date -u +%Y-%m-%dT%H:%M:%SZ) (elapsed ${ELAPSED}s) ---"
    echo "Run: $(echo "$RUN_JSON" | jq -c '{id, status, conclusion, head_sha, created_at, updated_at}')"
    echo "Jobs: $(echo "$JOBS_JSON" | jq -c '.jobs[] | {name, status, conclusion, steps: [.steps[] | {name, status}]}')"

    # 3d. Show last few log lines (tail) – this proves the server is working
    if [ -n "$LOGS_URL" ]; then
        LOG_TAIL=$(curl -s "$LOGS_URL" 2>/dev/null | tail -n 5 | sed 's/^/  log: /')
        if [ -n "$LOG_TAIL" ]; then
            echo "--- Log tail (last 5 lines) ---"
            echo "$LOG_TAIL"
        fi
    fi

    # 3e. Check if the workflow is completed
    if [ "$STATUS" = "completed" ]; then
        if [ "$CONCLUSION" != "success" ]; then
            echo "ERROR: Workflow failed with conclusion: $CONCLUSION" >&2
            # Dump full logs
            gh run view "$RUN_ID" --log 2>&1
            exit 1
        fi
        break
    fi

    sleep "$POLL_INTERVAL"
done

# --------------------------------------------------------------------------
# 4. Capture full logs, push, print raw link
# --------------------------------------------------------------------------
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
LOG_FILE="notes/workflow_logs_${TIMESTAMP}.txt"
mkdir -p notes
gh run view "$RUN_ID" --log > "$LOG_FILE" 2>&1

git add -f "$LOG_FILE"
git commit --no-verify -m "Logs: workflow $RUN_ID $TIMESTAMP" 2>/dev/null
git push origin "$BRANCH" 2>/dev/null

RAW_LOG_LINK="https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}/${LOG_FILE}"
echo ""
echo "📄 Raw workflow log link:"
echo "$RAW_LOG_LINK"

# --------------------------------------------------------------------------
# 5. Poll the live site for the version marker
# --------------------------------------------------------------------------
echo ""
echo "Waiting for live site to deploy..."
START_TIME=$(date +%s)
while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    if [ $ELAPSED -ge 120 ]; then  # 2 minutes extra for CDN propagation
        echo "ERROR: Live site did not update within 2 minutes after workflow." >&2
        echo "Last live snippet:"
        curl -s -m 5 "${PAGES_URL}?v=${NOW}" 2>/dev/null | grep -i 'DEPLOY_' | head -3
        exit 1
    fi

    LIVE_HTML=$(curl -s -m 5 "${PAGES_URL}?v=${NOW}" 2>/dev/null)
    if echo "$LIVE_HTML" | grep -q "$VERSION_MARKER"; then
        echo "✅ Live site contains version marker."
        echo "Site URL: $PAGES_URL"
        echo "Marker: $VERSION_MARKER"
        break
    else
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] marker_not_found (${ELAPSED}s)"
        sleep 5
    fi
done

# --------------------------------------------------------------------------
# 6. Final evidence summary
# --------------------------------------------------------------------------
echo ""
echo "=== Deployment Evidence ==="
echo "Commit: $COMMIT"
echo "Run ID: $RUN_ID"
echo "Raw log link: $RAW_LOG_LINK"
echo "Live site: $PAGES_URL"
echo "Version marker: $VERSION_MARKER"
