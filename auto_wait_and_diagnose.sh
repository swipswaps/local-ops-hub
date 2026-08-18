#!/usr/bin/env bash
# Trigger workflow, wait, capture full logs, push diagnostic report

set -u

# Set credential helper
git config --global credential.helper '!gh auth git-credential' 2>/dev/null || true
git config --local credential.helper '!gh auth git-credential' 2>/dev/null || true

echo "=== Triggering workflow 'Deploy to GitHub Pages' ==="
gh workflow run "Deploy to GitHub Pages" --ref master

# Wait for the run to start and capture the run ID
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
echo "Waiting for workflow to finish..."

# Poll until completion
while true; do
    STATUS=$(gh run view "$RUN_ID" --json status -q '.status' 2>/dev/null)
    CONCLUSION=$(gh run view "$RUN_ID" --json conclusion -q '.conclusion' 2>/dev/null)
    echo "Status: $STATUS, Conclusion: $CONCLUSION"
    if [ "$STATUS" = "completed" ]; then
        break
    fi
    sleep 10
done

# Capture logs
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
DIAG_FILE="notes/diagnostic_workflow_${TIMESTAMP}.txt"
mkdir -p notes

{
    echo "=== Workflow Diagnostic Report ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Run ID: $RUN_ID"
    echo "Status: $STATUS"
    echo "Conclusion: $CONCLUSION"
    echo ""
    echo "--- Full logs (all steps) ---"
    gh run view "$RUN_ID" --log 2>&1
} > "$DIAG_FILE"

# Commit and push
git add -f "$DIAG_FILE"
git commit --no-verify -m "Diagnostic: workflow $RUN_ID $CONCLUSION $TIMESTAMP"
git push origin master

RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${DIAG_FILE}"
echo ""
echo "📄 Diagnostic raw link:"
echo "$RAW_LINK"

# Also check Pages if successful
if [ "$CONCLUSION" = "success" ]; then
    PAGES_URL="https://swipswaps.github.io/local-ops-hub/"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL")
    echo ""
    echo "Pages URL: $PAGES_URL"
    echo "HTTP Status: $HTTP_CODE"
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Pages is live."
    else
        echo "⚠️ Pages returned $HTTP_CODE – check the logs."
    fi
else
    echo ""
    echo "❌ Workflow failed. Review the diagnostic link above for details."
fi
