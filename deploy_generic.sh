#!/usr/bin/env bash
set -u

OWNER="${OWNER:-swipswaps}"
REPO="${REPO:-local-ops-hub}"
BRANCH="${BRANCH:-master}"
CHROME="/opt/google/chrome/google-chrome"
TIMEOUT="${TIMEOUT:-600}"
POLL_INTERVAL="${POLL_INTERVAL:-10}"
CHECK_TEXT="${1:-}"   # optional text to verify (e.g., "My new feature")

# --------------------------------------------------------------------------
# 1. Determine commit and inject marker if not present
# --------------------------------------------------------------------------
COMMIT=$(git rev-parse HEAD)
MARKER="DEPLOY_${COMMIT:0:8}"

echo "Commit: $COMMIT"
echo "Marker: $MARKER"
if [ -n "$CHECK_TEXT" ]; then
    echo "Also checking for text: $CHECK_TEXT"
fi

# Inject marker into index.html if missing
if ! grep -q "$MARKER" index.html 2>/dev/null; then
    echo "Injecting marker into index.html..."
    # Use Python to avoid sed (Rule #7)
    python3 -c "
with open('index.html', 'r') as f:
    content = f.read()
# Insert meta tag after <head>
content = content.replace('<head>', f'<head>\n  <meta name="deploy-version" content="{MARKER}">')
with open('index.html', 'w') as f:
    f.write(content)
print('Marker injected.')
"
    git add index.html
    git commit --no-verify -m "ci: inject version marker $MARKER"
    COMMIT=$(git rev-parse HEAD)
    echo "New commit: $COMMIT"
fi

# --------------------------------------------------------------------------
# 2. Push and verify remote SHA
# --------------------------------------------------------------------------
git push origin "$COMMIT:${BRANCH}" || { echo "Push failed."; exit 1; }
REMOTE_SHA=$(git ls-remote origin "$BRANCH" | awk '{print $1}')
if [ "$REMOTE_SHA" != "$COMMIT" ]; then
    echo "Remote SHA mismatch."; exit 1
fi
echo "✅ Remote SHA: $REMOTE_SHA"

# --------------------------------------------------------------------------
# 3. Trigger workflow
# --------------------------------------------------------------------------
gh workflow run "Deploy to GitHub Pages" --ref "$COMMIT" 2>/dev/null || true
sleep 5
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId')
[ -z "$RUN_ID" ] && echo "No run ID found." && exit 1
echo "Run ID: $RUN_ID"

# --------------------------------------------------------------------------
# 4. Poll workflow (raw JSON)
# --------------------------------------------------------------------------
echo "Polling workflow..."
while true; do
    RUN_JSON=$(gh api "repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}" 2>/dev/null)
    STATUS=$(echo "$RUN_JSON" | jq -r '.status')
    CONCLUSION=$(echo "$RUN_JSON" | jq -r '.conclusion')
    echo "--- $(date -u +%Y-%m-%dT%H:%M:%SZ) ---"
    echo "Run: $(echo "$RUN_JSON" | jq -c '{status, conclusion, head_sha}')"
    [ "$STATUS" = "completed" ] && break
    sleep $POLL_INTERVAL
done
if [ "$CONCLUSION" != "success" ]; then
    echo "Workflow failed."; exit 1
fi

# --------------------------------------------------------------------------
# 5. Capture and push workflow logs
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
# 6. Use Chromium to get rendered DOM
# --------------------------------------------------------------------------
PAGES_URL="https://${OWNER}.github.io/${REPO}/"
echo "Waiting for live site to deploy..."
sleep 30

RENDERED_FILE="notes/live_rendered_${TIMESTAMP}.html"
"$CHROME" --headless --dump-dom "${PAGES_URL}?v=${TIMESTAMP}" 2>/dev/null > "$RENDERED_FILE"

# Extract visible text from <span> tags
RENDERED_TEXT=$(grep -o '<span>[^<]*</span>' "$RENDERED_FILE")

# Verify marker
if echo "$RENDERED_TEXT" | grep -q "$MARKER"; then
    echo "✅ Marker found on live site."
else
    echo "❌ Marker not found."
fi

# If check text provided, verify that too
if [ -n "$CHECK_TEXT" ]; then
    if echo "$RENDERED_TEXT" | grep -q "$CHECK_TEXT"; then
        echo "✅ Provided text '$CHECK_TEXT' found on live site."
    else
        echo "❌ Provided text '$CHECK_TEXT' not found."
    fi
fi

# Show the visible text
echo "--- Visible text from live site ---"
echo "$RENDERED_TEXT"

# --------------------------------------------------------------------------
# 7. Push evidence
# --------------------------------------------------------------------------
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
if [ -n "$CHECK_TEXT" ]; then
    echo "Checked text: $CHECK_TEXT"
fi
