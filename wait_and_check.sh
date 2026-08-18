#!/usr/bin/env bash
set -u

TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
DIAG_FILE="notes/wait_check_${TIMESTAMP}.txt"
mkdir -p notes

echo "Waiting for the latest workflow to complete..." | tee "$DIAG_FILE"

# Get the latest run ID (any status)
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId')
echo "Run ID: $RUN_ID" | tee -a "$DIAG_FILE"

# Poll until completed – print only status line, not full JSON
while true; do
    STATUS=$(gh run view "$RUN_ID" --json status -q '.status' 2>/dev/null)
    CONCLUSION=$(gh run view "$RUN_ID" --json conclusion -q '.conclusion' 2>/dev/null)
    echo "Status: $STATUS, Conclusion: $CONCLUSION" | tee -a "$DIAG_FILE"
    if [ "$STATUS" = "completed" ]; then
        break
    fi
    sleep 10
done

# Check live site
PAGES_URL="https://swipswaps.github.io/local-ops-hub/?v=$TIMESTAMP"
TEXT_FOUND=$(curl -s "$PAGES_URL" | grep -o 'README.md\|Rules-Compliant' | head -1)
echo "Text found on live site: ${TEXT_FOUND:-none}" | tee -a "$DIAG_FILE"

if [ "$TEXT_FOUND" = "README.md" ]; then
    echo "✅ Site updated successfully." | tee -a "$DIAG_FILE"
else
    echo "⚠️ Site still shows old text. Check workflow logs." | tee -a "$DIAG_FILE"
fi

# Push diagnostic
git add -f "$DIAG_FILE"
git commit --no-verify -m "Diagnostic: wait check $TIMESTAMP"
git push origin master

RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${DIAG_FILE}"
echo ""
echo "$RAW_LINK"
