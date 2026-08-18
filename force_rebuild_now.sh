#!/usr/bin/env bash
set -u

TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
DIAG_FILE="notes/rebuild_final_${TIMESTAMP}.txt"
mkdir -p notes

echo "=== Forcing a rebuild ===" | tee "$DIAG_FILE"

# Step 1: Push an empty commit to force the workflow
git commit --allow-empty -m "ci: force rebuild $TIMESTAMP"
git push origin master 2>&1 | tee -a "$DIAG_FILE"

# Step 2: Trigger the workflow
gh workflow run "Deploy to GitHub Pages" --ref master 2>&1 | tee -a "$DIAG_FILE"

# Step 3: Wait for the new run
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId')
echo "Run ID: $RUN_ID" | tee -a "$DIAG_FILE"
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
    echo "❌ Workflow failed." | tee -a "$DIAG_FILE"
    gh run view "$RUN_ID" --log 2>&1 | tee -a "$DIAG_FILE"
    exit 1
fi

# Step 4: Check live bundle
sleep 30
PAGES_URL="https://swipswaps.github.io/local-ops-hub/"
HTML=$(curl -s "$PAGES_URL")
BUNDLE_URL=$(echo "$HTML" | grep -o 'src="/assets/index-[^"]*\.js"' | head -1 | sed 's/src="//' | sed 's/"//')
if [ -n "$BUNDLE_URL" ]; then
    FULL_BUNDLE_URL="https://swipswaps.github.io${BUNDLE_URL}"
    BUNDLE_CONTENT=$(curl -s "$FULL_BUNDLE_URL")
    FOUND=$(echo "$BUNDLE_CONTENT" | grep -o 'README\.md' | head -1)
    echo "Bundle contains 'README.md': ${FOUND:-no}" | tee -a "$DIAG_FILE"
else
    echo "Could not find bundle." | tee -a "$DIAG_FILE"
fi

# Push diagnostic
git add -f "$DIAG_FILE"
git commit --no-verify -m "Diagnostic: rebuild final $TIMESTAMP"
git push origin master

RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${DIAG_FILE}"
echo ""
echo "$RAW_LINK"
