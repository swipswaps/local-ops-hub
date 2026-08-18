#!/usr/bin/env bash
set -u

# Find the commit that changed src/App.jsx to README.md
COMMIT_SHA=$(git log -S "README.md" --oneline -n 1 --format="%H" 2>/dev/null)

if [ -z "$COMMIT_SHA" ]; then
    echo "ERROR: Could not find commit with README.md change."
    echo "Try: git log --oneline | grep -i readme"
    exit 1
fi

echo "Found commit: $COMMIT_SHA"

# Trigger workflow on that exact commit
echo "Triggering workflow on commit $COMMIT_SHA..."
gh workflow run "Deploy to GitHub Pages" --ref "$COMMIT_SHA"

# Wait 5 seconds for the run to start
sleep 5

# Get the latest run ID
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId')
echo "Run ID: $RUN_ID"

# Poll for completion – print raw JSON status only
echo "Polling for completion (raw JSON)..."
while true; do
    RAW_JSON=$(gh api "repos/swipswaps/local-ops-hub/actions/runs/$RUN_ID" 2>/dev/null)
    STATUS=$(echo "$RAW_JSON" | jq -r '.status // "unknown"')
    CONCLUSION=$(echo "$RAW_JSON" | jq -r '.conclusion // "null"')
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] status=$STATUS conclusion=$CONCLUSION"
    if [ "$STATUS" = "completed" ]; then
        echo ""
        echo "=== Final Raw JSON ==="
        echo "$RAW_JSON" | jq '.'
        break
    fi
    sleep 10
done

# Check the live site
echo ""
echo "Checking live site..."
PAGES_URL="https://swipswaps.github.io/local-ops-hub/"
HTML=$(curl -s "$PAGES_URL")
BUNDLE_URL=$(echo "$HTML" | grep -o 'src="/assets/index-[^"]*\.js"' | head -1 | sed 's/src="//' | sed 's/"//')
if [ -n "$BUNDLE_URL" ]; then
    FULL_BUNDLE_URL="https://swipswaps.github.io${BUNDLE_URL}"
    BUNDLE_CONTENT=$(curl -s "$FULL_BUNDLE_URL")
    if echo "$BUNDLE_CONTENT" | grep -q 'README\.md'; then
        echo "✅ Site updated: README.md found in bundle."
    else
        echo "⚠️ Site still shows old text. Check workflow logs."
    fi
else
    echo "Could not find bundle URL."
fi
