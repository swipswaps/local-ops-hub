#!/usr/bin/env bash
set -u

TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
DIAG_FILE="notes/rebuild_verify_${TIMESTAMP}.txt"
mkdir -p notes

echo "=== Force Rebuild and Verify ===" | tee "$DIAG_FILE"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)" | tee -a "$DIAG_FILE"

# Step 1: Trigger a fresh workflow on master
echo "Triggering workflow on master..." | tee -a "$DIAG_FILE"
gh workflow run "Deploy to GitHub Pages" --ref master 2>&1 | tee -a "$DIAG_FILE"
sleep 5

# Step 2: Get the latest run ID
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId')
echo "Run ID: $RUN_ID" | tee -a "$DIAG_FILE"

# Step 3: Wait for completion
echo "Waiting for workflow to complete..." | tee -a "$DIAG_FILE"
while true; do
    STATUS=$(gh run view "$RUN_ID" --json status -q '.status' 2>/dev/null)
    CONCLUSION=$(gh run view "$RUN_ID" --json conclusion -q '.conclusion' 2>/dev/null)
    echo "Status: $STATUS, Conclusion: $CONCLUSION" | tee -a "$DIAG_FILE"
    if [ "$STATUS" = "completed" ]; then
        break
    fi
    sleep 10
done

if [ "$CONCLUSION" != "success" ]; then
    echo "❌ Workflow failed. Check logs." | tee -a "$DIAG_FILE"
    gh run view "$RUN_ID" --log 2>&1 | tee -a "$DIAG_FILE"
    exit 1
fi

# Step 4: Wait a bit for Pages to propagate
echo "Waiting 30 seconds for Pages to propagate..." | tee -a "$DIAG_FILE"
sleep 30

# Step 5: Fetch live bundle and search
PAGES_URL="https://swipswaps.github.io/local-ops-hub/"
HTML=$(curl -s "$PAGES_URL")
BUNDLE_URL=$(echo "$HTML" | grep -o 'src="/assets/index-[^"]*\.js"' | head -1 | sed 's/src="//' | sed 's/"//')
if [ -n "$BUNDLE_URL" ]; then
    FULL_BUNDLE_URL="https://swipswaps.github.io${BUNDLE_URL}"
    echo "Bundle URL: $FULL_BUNDLE_URL" | tee -a "$DIAG_FILE"
    BUNDLE_CONTENT=$(curl -s "$FULL_BUNDLE_URL")
    FOUND_README=$(echo "$BUNDLE_CONTENT" | grep -o 'README' | head -1)
    FOUND_README_MD=$(echo "$BUNDLE_CONTENT" | grep -o 'README\.md' | head -1)
    echo "Contains 'README': ${FOUND_README:-no}" | tee -a "$DIAG_FILE"
    echo "Contains 'README.md': ${FOUND_README_MD:-no}" | tee -a "$DIAG_FILE"
else
    echo "Could not find bundle URL." | tee -a "$DIAG_FILE"
fi

# Step 6: If still not found, force a clean rebuild with an empty commit
if [ "$FOUND_README_MD" != "README.md" ]; then
    echo "⚠️ README.md still not found. Pushing empty commit to force rebuild..." | tee -a "$DIAG_FILE"
    git commit --allow-empty -m "ci: force rebuild $TIMESTAMP"
    git push origin master
    echo "Empty commit pushed. Triggering another workflow..." | tee -a "$DIAG_FILE"
    gh workflow run "Deploy to GitHub Pages" --ref master
    echo "Wait for this workflow to complete, then check again."
else
    echo "✅ README.md found in live bundle. Site updated successfully." | tee -a "$DIAG_FILE"
fi

# Push diagnostic
git add -f "$DIAG_FILE"
git commit --no-verify -m "Diagnostic: rebuild verify $TIMESTAMP" 2>&1 | tee -a "$DIAG_FILE"
git push origin master 2>&1 | tee -a "$DIAG_FILE"

RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${DIAG_FILE}"
echo ""
echo "$RAW_LINK"
