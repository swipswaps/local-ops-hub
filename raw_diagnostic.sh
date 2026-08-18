#!/usr/bin/env bash
# Fetch raw API data and logs, save, push, print raw link

set -u

# Set credential helper
git config --global credential.helper '!gh auth git-credential' 2>/dev/null || true
git config --local credential.helper '!gh auth git-credential' 2>/dev/null || true

echo "=== Triggering workflow 'Deploy to GitHub Pages' ==="
gh workflow run "Deploy to GitHub Pages" --ref master

sleep 5
RUN_ID=""
for i in {1..10}; do
    RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
    if [ -n "$RUN_ID" ]; then
        break
    fi
    sleep 5
done

if [ -z "$RUN_ID" ]; then
    echo "ERROR: Could not retrieve run ID." >&2
    exit 1
fi

echo "Run ID: $RUN_ID"
echo "Waiting for workflow to finish (polling every 10s)..."

# Poll until completed, capturing full JSON status each time
while true; do
    # Get full raw JSON status
    RAW_STATUS=$(gh api "repos/swipswaps/local-ops-hub/actions/runs/$RUN_ID" 2>/dev/null)
    STATUS=$(echo "$RAW_STATUS" | jq -r '.status // "unknown"')
    CONCLUSION=$(echo "$RAW_STATUS" | jq -r '.conclusion // "null"')
    echo "Raw status: $RAW_STATUS" | head -c 200
    if [ "$STATUS" = "completed" ]; then
        break
    fi
    sleep 10
done

# Timestamp
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
DIAG_FILE="notes/diagnostic_raw_${TIMESTAMP}.txt"
mkdir -p notes

{
    echo "=== Raw Diagnostic Data ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Run ID: $RUN_ID"
    echo ""
    echo "--- Full raw run JSON (gh api) ---"
    gh api "repos/swipswaps/local-ops-hub/actions/runs/$RUN_ID" 2>&1
    echo ""
    echo "--- All workflow jobs (raw JSON) ---"
    gh api "repos/swipswaps/local-ops-hub/actions/runs/$RUN_ID/jobs" --paginate 2>&1
    echo ""
    echo "--- Complete workflow logs (raw text) ---"
    gh run view "$RUN_ID" --log 2>&1
} > "$DIAG_FILE"

# Commit and push
git add -f "$DIAG_FILE"
git commit --no-verify -m "Diagnostic: raw data run $RUN_ID $TIMESTAMP"
git push origin master

RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${DIAG_FILE}"
echo ""
echo "📄 Raw diagnostic link:"
echo "$RAW_LINK"
