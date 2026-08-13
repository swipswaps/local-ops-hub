#!/usr/bin/env bash
set -u

OWNER="${OWNER:-swipswaps}"
REPO="${REPO:-local-ops-hub}"
BRANCH="${BRANCH:-master}"
CHROME="/usr/lib64/chromium-browser/chromium-browser"
TIMEOUT="${TIMEOUT:-600}"
POLL_INTERVAL="${POLL_INTERVAL:-10}"

# --------------------------------------------------------------------------
# 0. Detect current live visible text
# --------------------------------------------------------------------------
PAGES_URL="https://${OWNER}.github.io/${REPO}/"
echo "Fetching current live visible text..."
LIVE_TEXT=$("$CHROME" --headless --dump-dom "${PAGES_URL}?v=$(date +%s)" 2>/dev/null | grep -o '<span>[^<]*</span>' | head -1 | sed 's/<span>//;s/<\/span>//')
echo "Live text: $LIVE_TEXT"

LOCAL_TEXT=$(grep -o '<span>[^<]*</span>' src/App.jsx | head -1 | sed 's/<span>//;s/<\/span>//')
echo "Local text: $LOCAL_TEXT"

if [ "$LIVE_TEXT" = "$LOCAL_TEXT" ]; then
    echo "✅ Live text already matches local. Exiting."
    exit 0
else
    echo "⚠️ Live text ($LIVE_TEXT) does not match local ($LOCAL_TEXT)."
    echo "Fixing and redeploying..."
fi

# --------------------------------------------------------------------------
# 1. Inject marker into index.html
# --------------------------------------------------------------------------
COMMIT=$(git rev-parse HEAD)
MARKER="DEPLOY_${COMMIT:0:8}"
echo "Commit: $COMMIT"
echo "Marker: $MARKER"

# Fix: Use Python with proper variable passing
if ! grep -q "$MARKER" index.html 2>/dev/null; then
    echo "Injecting marker into index.html..."
    python3 -c "
import sys
marker = sys.argv[1]
with open('index.html', 'r') as f:
    content = f.read()
if marker not in content:
    content = content.replace('<head>', f'<head>\n  <meta name=\"deploy-version\" content=\"{marker}\">')
    with open('index.html', 'w') as f:
        f.write(content)
    print('Marker injected.')
else:
    print('Marker already present.')
" "$MARKER"
    
    git add index.html
    git commit --no-verify -m "ci: inject version marker $MARKER"
    COMMIT=$(git rev-parse HEAD)
    echo "New commit: $COMMIT"
else
    echo "Marker already present."
fi

# --------------------------------------------------------------------------
# 2. Force update local src/App.jsx to match the intended text
# --------------------------------------------------------------------------
# The user wants the local text to be deployed. If local differs from live,
# we assume the local version is correct. (No hardcoded text.)
echo "Ensuring local src/App.jsx is staged..."
git add src/App.jsx
if ! git diff --cached --quiet; then
    git commit --no-verify -m "fix: update header to match local"
    COMMIT=$(git rev-parse HEAD)
    echo "Committed local change. New commit: $COMMIT"
fi

# --------------------------------------------------------------------------
# 3. Push the commit and verify remote SHA
# --------------------------------------------------------------------------
echo "Pushing commit $COMMIT..."
if ! git push origin "$COMMIT:${BRANCH}" 2>&1; then
    echo "Push failed." >&2
    exit 1
fi

REMOTE_SHA=$(git ls-remote origin "$BRANCH" | awk '{print $1}')
if [ "$REMOTE_SHA" != "$COMMIT" ]; then
    echo "Remote SHA mismatch." >&2
    exit 1
fi
echo "✅ Remote SHA verified: $REMOTE_SHA"

# --------------------------------------------------------------------------
# 4. Trigger workflow on that specific commit
# --------------------------------------------------------------------------
echo "Triggering workflow on commit $COMMIT..."
gh workflow run "Deploy to GitHub Pages" --ref "$COMMIT" 2>/dev/null || echo "Workflow may already be running."

# --------------------------------------------------------------------------
# 5. Wait for a run with this commit SHA
# --------------------------------------------------------------------------
echo "Waiting for a workflow run on commit $COMMIT..."
RUN_ID=""
for i in {1..30}; do
    RUN_ID=$(gh run list --workflow="deploy.yml" --limit 10 --json databaseId,headSha \
        -q ".[] | select(.headSha == \"$COMMIT\") | .databaseId" 2>/dev/null | head -1)
    if [ -n "$RUN_ID" ]; then
        break
    fi
    sleep 5
done

if [ -z "$RUN_ID" ]; then
    echo "ERROR: No workflow run found for commit $COMMIT." >&2
    exit 1
fi
echo "Run ID: $RUN_ID"

# --------------------------------------------------------------------------
# 6. Poll that specific run (raw JSON)
# --------------------------------------------------------------------------
echo "Polling workflow run $RUN_ID..."
while true; do
    RUN_JSON=$(gh api "repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}" 2>/dev/null)
    STATUS=$(echo "$RUN_JSON" | jq -r '.status // "unknown"')
    CONCLUSION=$(echo "$RUN_JSON" | jq -r '.conclusion // "null"')
    echo "--- $(date -u +%Y-%m-%dT%H:%M:%SZ) ---"
    echo "Run: $(echo "$RUN_JSON" | jq -c '{status, conclusion, head_sha}')"
    if [ "$STATUS" = "completed" ]; then
        if [ "$CONCLUSION" != "success" ]; then
            echo "Workflow failed." >&2
            gh run view "$RUN_ID" --log 2>&1
            exit 1
        fi
        break
    fi
    sleep $POLL_INTERVAL
done

# --------------------------------------------------------------------------
# 7. Capture and push workflow logs
# --------------------------------------------------------------------------
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
LOG_FILE="notes/workflow_logs_${TIMESTAMP}.txt"
mkdir -p notes
gh run view "$RUN_ID" --log > "$LOG_FILE" 2>&1
git add -f "$LOG_FILE"
git commit --no-verify -m "Logs: workflow $RUN_ID $TIMESTAMP" 2>/dev/null
git push origin "$BRANCH" 2>/dev/null
RAW_LOG_LINK="https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}/${LOG_FILE}"
echo "📄 Raw log link: $RAW_LOG_LINK"

# --------------------------------------------------------------------------
# 8. Poll live site until marker appears
# --------------------------------------------------------------------------
echo "Polling live site for marker '$MARKER'..."
START_TIME=$(date +%s)
while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    if [ $ELAPSED -ge "$TIMEOUT" ]; then
        echo "ERROR: Timeout (${TIMEOUT}s) – marker not found." >&2
        exit 1
    fi

    RENDERED_FILE="notes/live_rendered_${TIMESTAMP}.html"
    "$CHROME" --headless --dump-dom "${PAGES_URL}?v=${NOW}" 2>/dev/null > "$RENDERED_FILE"

    if grep -q "$MARKER" "$RENDERED_FILE"; then
        echo "✅ Marker found on live site."
        break
    else
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] marker_not_found (${ELAPSED}s)"
        grep -o '<span>[^<]*</span>' "$RENDERED_FILE" | head -3
        rm -f "$RENDERED_FILE"
        sleep $POLL_INTERVAL
    fi
done

# --------------------------------------------------------------------------
# 9. Final verification – print visible text
# --------------------------------------------------------------------------
NEW_LIVE_TEXT=$(grep -o '<span>[^<]*</span>' "$RENDERED_FILE" | head -1 | sed 's/<span>//;s/<\/span>//')
echo "✅ Live text after deployment: $NEW_LIVE_TEXT"

# Push rendered DOM as evidence
git add -f "$RENDERED_FILE"
git commit --no-verify -m "Evidence: rendered live page $TIMESTAMP" 2>/dev/null
git push origin "$BRANCH" 2>/dev/null
RAW_RENDERED_LINK="https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}/${RENDERED_FILE}"

echo ""
echo "=== Deployment Evidence ==="
echo "Commit: $COMMIT"
echo "Run ID: $RUN_ID"
echo "Raw log link: $RAW_LOG_LINK"
echo "Rendered DOM: $RAW_RENDERED_LINK"
echo "Live site: $PAGES_URL"
echo "Marker: $MARKER"
echo "Live text: $NEW_LIVE_TEXT"
echo "Local text: $LOCAL_TEXT"
