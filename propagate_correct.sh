#!/usr/bin/env bash
set -u

echo "=== Propagating exact text change to live site ==="

# --------------------------------------------------------------------------
# 1. Ensure the source file has the correct text: README.md (not README.md.md)
# --------------------------------------------------------------------------
python3 -c "
import re
with open('src/App.jsx', 'r') as f:
    content = f.read()
# Replace only the exact span: <span>README</span> -> <span>README.md</span>
# This avoids double .md
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
# 2. Commit and push the change
# --------------------------------------------------------------------------
git add src/App.jsx
if git diff --cached --quiet; then
    echo "No changes to commit."
else
    git commit -m "fix: update header to README.md"
    echo "Committed change."
fi

# Get the commit SHA (latest on master)
COMMIT_SHA=$(git rev-parse HEAD)
echo "Commit SHA: $COMMIT_SHA"

# Push to remote master (if not already)
if git branch -r --contains "$COMMIT_SHA" | grep -q origin/master; then
    echo "Commit already on remote master."
else
    echo "Pushing commit to master..."
    git push origin master
fi

# --------------------------------------------------------------------------
# 3. Trigger workflow on that commit
# --------------------------------------------------------------------------
echo "Triggering workflow on commit $COMMIT_SHA..."
gh workflow run "Deploy to GitHub Pages" --ref "$COMMIT_SHA"

# Wait for run to start
sleep 5
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
if [ -z "$RUN_ID" ]; then
    echo "ERROR: Could not get run ID."
    exit 1
fi
echo "Run ID: $RUN_ID"

# --------------------------------------------------------------------------
# 4. Poll for completion (raw status only)
# --------------------------------------------------------------------------
echo "Polling for completion..."
while true; do
    RAW_JSON=$(gh api "repos/swipswaps/local-ops-hub/actions/runs/$RUN_ID" 2>/dev/null)
    STATUS=$(echo "$RAW_JSON" | jq -r '.status // "unknown"')
    CONCLUSION=$(echo "$RAW_JSON" | jq -r '.conclusion // "null"')
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] status=$STATUS conclusion=$CONCLUSION"
    if [ "$STATUS" = "completed" ]; then
        break
    fi
    sleep 10
done

# --------------------------------------------------------------------------
# 5. Capture logs and push them (to get raw link)
# --------------------------------------------------------------------------
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
LOG_FILE="notes/workflow_logs_${TIMESTAMP}.txt"
mkdir -p notes

echo "Capturing workflow logs to $LOG_FILE..."
gh run view "$RUN_ID" --log > "$LOG_FILE" 2>&1

# Push the log file
git add -f "$LOG_FILE"
git commit --no-verify -m "Logs: workflow $RUN_ID $TIMESTAMP"
git push origin master

RAW_LOG_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${LOG_FILE}"
echo ""
echo "📄 Raw workflow log link:"
echo "$RAW_LOG_LINK"

# --------------------------------------------------------------------------
# 6. Verify live site with cache-busting
# --------------------------------------------------------------------------
echo ""
echo "Verifying live site (cache-busting)..."
PAGES_URL="https://swipswaps.github.io/local-ops-hub/?v=$TIMESTAMP"
HTML=$(curl -s "$PAGES_URL")
BUNDLE_URL=$(echo "$HTML" | grep -o 'src="/assets/index-[^"]*\.js"' | head -1 | sed 's/src="//' | sed 's/"//')
if [ -n "$BUNDLE_URL" ]; then
    FULL_BUNDLE_URL="https://swipswaps.github.io${BUNDLE_URL}"
    BUNDLE_CONTENT=$(curl -s "$FULL_BUNDLE_URL")
    if echo "$BUNDLE_CONTENT" | grep -q 'README\.md'; then
        echo "✅ Site updated: README.md found in bundle."
    else
        echo "⚠️ Site still shows old text. Check the workflow logs above."
    fi
else
    echo "Could not find bundle URL."
fi

echo ""
echo "If the site still shows old text, wait 2–3 minutes and refresh with:"
echo "  $PAGES_URL"
