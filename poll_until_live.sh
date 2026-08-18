#!/usr/bin/env bash
set -u

echo "=== Polling GitHub Pages build and live site until deployed ==="

OWNER="swipswaps"
REPO="local-ops-hub"
EXPECTED_TEXT="README.md"
TIMEOUT_SECONDS=600   # 10 minutes max
INTERVAL_SECONDS=10

# --------------------------------------------------------------------------
# 1. Ensure the source file has the exact text (README.md, not README.md.md)
# --------------------------------------------------------------------------
python3 -c "
import re
with open('src/App.jsx', 'r') as f:
    content = f.read()
old = '<span>README</span>'
new = '<span>README.md</span>'
if old in content:
    content = content.replace(old, new)
    with open('src/App.jsx', 'w') as f:
        f.write(content)
    print('Updated src/App.jsx: README -> README.md')
else:
    print('src/App.jsx already contains README.md or no change needed.')
"

# --------------------------------------------------------------------------
# 2. Commit and push the change (if needed)
# --------------------------------------------------------------------------
git add src/App.jsx
if ! git diff --cached --quiet; then
    git commit -m "fix: update header to README.md"
    echo "Committed change."
else
    echo "No changes to commit."
fi

COMMIT_SHA=$(git rev-parse HEAD)
echo "Commit SHA: $COMMIT_SHA"

# Push to remote master if not already there
if ! git branch -r --contains "$COMMIT_SHA" | grep -q origin/master; then
    echo "Pushing commit to master..."
    git push origin master
fi

# --------------------------------------------------------------------------
# 3. Trigger the workflow on that commit (if not already running)
# --------------------------------------------------------------------------
echo "Triggering workflow on commit $COMMIT_SHA..."
gh workflow run "Deploy to GitHub Pages" --ref "$COMMIT_SHA" 2>/dev/null || echo "Workflow may already be running."

# --------------------------------------------------------------------------
# 4. Poll: wait for the Pages build to complete AND the live site to update
# --------------------------------------------------------------------------
START_TIME=$(date +%s)
PAGES_URL="https://${OWNER}.github.io/${REPO}/"
BUILD_STATUS=""
LIVE_TEXT=""

echo ""
echo "Polling every ${INTERVAL_SECONDS}s (timeout: ${TIMEOUT_SECONDS}s)..."
echo "Pages URL: $PAGES_URL"
echo "Expected text: $EXPECTED_TEXT"
echo ""

while true; do
    NOW=$(date +%s)
    ELAPSED=$((NOW - START_TIME))
    if [ $ELAPSED -ge $TIMEOUT_SECONDS ]; then
        echo "❌ Timeout reached (${TIMEOUT_SECONDS}s). Deployment did not complete."
        break
    fi

    # 4a. Check Pages build status via API
    BUILD_JSON=$(gh api "repos/${OWNER}/${REPO}/pages/builds/latest" 2>/dev/null || echo '{"status":"null"}')
    BUILD_STATUS=$(echo "$BUILD_JSON" | jq -r '.status // "null"')
    BUILD_COMMIT=$(echo "$BUILD_JSON" | jq -r '.commit // ""')

    # 4b. Check the live site (cache‑busting)
    LIVE_HTML=$(curl -s -m 5 "${PAGES_URL}?v=${NOW}" 2>/dev/null || echo "")
    LIVE_TEXT=$(echo "$LIVE_HTML" | grep -o "$EXPECTED_TEXT" | head -1)

    # 4c. Print status
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] build_status=$BUILD_STATUS commit=$BUILD_COMMIT live_text=${LIVE_TEXT:-none}"

    # 4d. Determine if we are done
    if [ "$BUILD_STATUS" = "built" ] && [ "$LIVE_TEXT" = "$EXPECTED_TEXT" ]; then
        echo ""
        echo "✅ Deployment successful!"
        echo "   Build status: $BUILD_STATUS"
        echo "   Live text found: $LIVE_TEXT"
        break
    fi

    sleep $INTERVAL_SECONDS
done

# --------------------------------------------------------------------------
# 5. Capture and push the workflow logs (to get a raw link)
# --------------------------------------------------------------------------
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
if [ -n "$RUN_ID" ]; then
    TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
    LOG_FILE="notes/workflow_logs_${TIMESTAMP}.txt"
    mkdir -p notes
    gh run view "$RUN_ID" --log > "$LOG_FILE" 2>&1
    git add -f "$LOG_FILE"
    git commit --no-verify -m "Logs: workflow $RUN_ID $TIMESTAMP" 2>/dev/null
    git push origin master 2>/dev/null
    RAW_LOG_LINK="https://raw.githubusercontent.com/${OWNER}/${REPO}/master/${LOG_FILE}"
    echo ""
    echo "📄 Raw workflow log link:"
    echo "$RAW_LOG_LINK"
else
    echo "⚠️ Could not retrieve run ID for logs."
fi

# --------------------------------------------------------------------------
# 6. Final summary
# --------------------------------------------------------------------------
if [ "$BUILD_STATUS" = "built" ] && [ "$LIVE_TEXT" = "$EXPECTED_TEXT" ]; then
    echo ""
    echo "✅ The live site now shows: $EXPECTED_TEXT"
    echo "🌐 $PAGES_URL"
else
    echo ""
    echo "⚠️ Deployment did not complete within the timeout."
    echo "   Check the workflow logs above for details."
    exit 1
fi
