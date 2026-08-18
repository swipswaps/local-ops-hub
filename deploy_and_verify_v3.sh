#!/usr/bin/env bash
set -u

# ============================================================================
# deploy_and_verify_v3.sh – Push, verify, deploy, and output raw evidence.
# Usage: ./deploy_and_verify_v3.sh [COMMIT_SHA]
# ============================================================================

OWNER="${OWNER:-swipswaps}"
REPO="${REPO:-local-ops-hub}"
BRANCH="${BRANCH:-master}"
TIMEOUT="${TIMEOUT:-600}"
POLL_INTERVAL="${POLL_INTERVAL:-10}"

log() { echo "$*" >&2; }

# --------------------------------------------------------------------------
# 1. Determine commit and inject version marker
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

# --------------------------------------------------------------------------
# 2. Push the commit AND VERIFY IT
# --------------------------------------------------------------------------
log "Pushing commit $COMMIT to origin/${BRANCH}..."

# Capture push output
PUSH_OUTPUT=$(git push origin "$COMMIT:${BRANCH}" 2>&1)
PUSH_EXIT=$?

# Record the push output as evidence
echo "--- git push output (exit code: $PUSH_EXIT) ---"
echo "$PUSH_OUTPUT"

if [ $PUSH_EXIT -ne 0 ]; then
    log "ERROR: git push failed with exit code $PUSH_EXIT"
    echo "Push output was:"
    echo "$PUSH_OUTPUT"
    exit 1
fi

# Verify the remote branch now contains the commit
REMOTE_SHA=$(git ls-remote origin "$BRANCH" | awk '{print $1}')
if [ -z "$REMOTE_SHA" ]; then
    log "ERROR: Could not get remote SHA for $BRANCH"
    exit 1
fi

if [ "$REMOTE_SHA" != "$COMMIT" ]; then
    log "ERROR: Remote branch $BRANCH is at $REMOTE_SHA, not $COMMIT"
    echo "Remote SHA: $REMOTE_SHA"
    echo "Expected:   $COMMIT"
    exit 1
fi

log "✅ Push verified: remote $BRANCH now at $COMMIT"

# --------------------------------------------------------------------------
# 3. Trigger workflow (ignore errors – may already be running)
# --------------------------------------------------------------------------
log "Triggering workflow on commit $COMMIT..."
gh workflow run "Deploy to GitHub Pages" --ref "$COMMIT" 2>/dev/null || log "Workflow may already be running."

sleep 3
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
if [ -z "$RUN_ID" ]; then
    log "ERROR: No run ID found."
    exit 1
fi
log "Run ID: $RUN_ID"

# --------------------------------------------------------------------------
# 4. Poll workflow status (raw JSON)
# --------------------------------------------------------------------------
PAGES_URL="https://${OWNER}.github.io/${REPO}/"
echo "--- Real‑time deployment monitor ---"
echo "Run ID: $RUN_ID"
echo "Marker: $VERSION_MARKER"
echo ""

START_TIME=$(date +%s)
while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    if [ $ELAPSED -ge "$TIMEOUT" ]; then
        echo "ERROR: Timeout (${TIMEOUT}s) reached." >&2
        exit 1
    fi

    RUN_JSON=$(gh api "repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}" 2>/dev/null)
    STATUS=$(echo "$RUN_JSON" | jq -r '.status // "unknown"')
    CONCLUSION=$(echo "$RUN_JSON" | jq -r '.conclusion // "null"')
    LOGS_URL=$(echo "$RUN_JSON" | jq -r '.logs_url // ""')

    JOBS_JSON=$(gh api "repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}/jobs" 2>/dev/null)

    echo "--- Poll at $(date -u +%Y-%m-%dT%H:%M:%SZ) (elapsed ${ELAPSED}s) ---"
    echo "Run: $(echo "$RUN_JSON" | jq -c '{id, status, conclusion, head_sha, created_at, updated_at}')"
    echo "Jobs: $(echo "$JOBS_JSON" | jq -c '.jobs[] | {name, status, conclusion, steps: [.steps[] | {name, status}]}')"

    if [ -n "$LOGS_URL" ]; then
        LOG_TAIL=$(curl -s "$LOGS_URL" 2>/dev/null | tail -n 5 | sed 's/^/  log: /')
        if [ -n "$LOG_TAIL" ]; then
            echo "--- Log tail (last 5 lines) ---"
            echo "$LOG_TAIL"
        fi
    fi

    if [ "$STATUS" = "completed" ]; then
        if [ "$CONCLUSION" != "success" ]; then
            echo "ERROR: Workflow failed with conclusion: $CONCLUSION" >&2
            gh run view "$RUN_ID" --log 2>&1
            exit 1
        fi
        break
    fi
    sleep "$POLL_INTERVAL"
done

# --------------------------------------------------------------------------
# 5. Capture and push logs
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
# 6. Poll live site for version marker
# --------------------------------------------------------------------------
echo ""
echo "Waiting for live site to deploy..."
START_TIME=$(date +%s)
while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    if [ $ELAPSED -ge 120 ]; then
        echo "ERROR: Live site did not update within 2 minutes." >&2
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
# 7. Final evidence summary
# --------------------------------------------------------------------------
echo ""
echo "=== Deployment Evidence ==="
echo "Commit: $COMMIT"
echo "Remote SHA verified: $REMOTE_SHA"
echo "Run ID: $RUN_ID"
echo "Raw log link: $RAW_LOG_LINK"
echo "Live site: $PAGES_URL"
echo "Version marker: $VERSION_MARKER"
