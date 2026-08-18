#!/usr/bin/env bash
set -u

TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
DIAG_FILE="notes/trigger_correct_${TIMESTAMP}.txt"
mkdir -p notes

{
    echo "=== Trigger workflow on correct commit ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
} > "$DIAG_FILE"

# Find the commit that changed src/App.jsx to README.md
COMMIT_SHA=$(git log --oneline --grep="chore: update header text" -n 1 --format="%H" 2>/dev/null)
if [ -z "$COMMIT_SHA" ]; then
    # Fallback: find the commit that changed the line with README.md
    COMMIT_SHA=$(git log -S "README.md" --oneline -n 1 --format="%H" 2>/dev/null)
fi
if [ -z "$COMMIT_SHA" ]; then
    echo "ERROR: Could not find commit with README.md change." | tee -a "$DIAG_FILE"
    exit 1
fi

echo "Found commit: $COMMIT_SHA" | tee -a "$DIAG_FILE"

# Trigger workflow on that commit
echo "Triggering workflow on commit $COMMIT_SHA..." | tee -a "$DIAG_FILE"
gh workflow run "Deploy to GitHub Pages" --ref "$COMMIT_SHA" 2>&1 | tee -a "$DIAG_FILE"

# Wait for the run to start
sleep 5
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
echo "Run ID: $RUN_ID" | tee -a "$DIAG_FILE"

# Poll with raw JSON only
echo "Polling for completion (raw JSON)..." | tee -a "$DIAG_FILE"
while true; do
    RAW_JSON=$(gh api "repos/swipswaps/local-ops-hub/actions/runs/$RUN_ID" 2>/dev/null)
    STATUS=$(echo "$RAW_JSON" | jq -r '.status // "unknown"')
    CONCLUSION=$(echo "$RAW_JSON" | jq -r '.conclusion // "null"')
    echo "--- Poll $(date -u +%Y-%m-%dT%H:%M:%SZ) ---" | tee -a "$DIAG_FILE"
    echo "$RAW_JSON" | tee -a "$DIAG_FILE"
    echo "" | tee -a "$DIAG_FILE"
    if [ "$STATUS" = "completed" ]; then
        break
    fi
    sleep 10
done

# Check live bundle
sleep 30
PAGES_URL="https://swipswaps.github.io/local-ops-hub/"
HTML=$(curl -s "$PAGES_URL")
BUNDLE_URL=$(echo "$HTML" | grep -o 'src="/assets/index-[^"]*\.js"' | head -1 | sed 's/src="//' | sed 's/"//')
if [ -n "$BUNDLE_URL" ]; then
    FULL_BUNDLE_URL="https://swipswaps.github.io${BUNDLE_URL}"
    BUNDLE_CONTENT=$(curl -s "$FULL_BUNDLE_URL")
    FOUND=$(echo "$BUNDLE_CONTENT" | grep -o 'README\.md' | head -1)
    echo "Bundle contains 'README.md': ${FOUND:-no}" | tee -a "$DIAG_FILE"
fi

# Push diagnostic
git add -f "$DIAG_FILE"
git commit --no-verify -m "Diagnostic: trigger correct commit $TIMESTAMP" 2>&1 | tee -a "$DIAG_FILE"
git push origin master 2>&1 | tee -a "$DIAG_FILE"

RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${DIAG_FILE}"
echo ""
echo "$RAW_LINK"
