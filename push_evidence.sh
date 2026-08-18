#!/usr/bin/env bash
# Check Pages, write evidence, push, print raw link

PAGES_URL="https://swipswaps.github.io/local-ops-hub/"
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
EVIDENCE_FILE="notes/deploy_${TIMESTAMP}.txt"
mkdir -p notes

# Check if Pages is live
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL")
if [ "$HTTP_STATUS" = "200" ]; then
    PAGES_LIVE="YES"
else
    PAGES_LIVE="NO (HTTP $HTTP_STATUS)"
fi

# Write evidence
{
    echo "=== Deployment Evidence ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "Owner: swipswaps"
    echo "Repo: local-ops-hub"
    echo "Pages URL: $PAGES_URL"
    echo "Pages live: $PAGES_LIVE"
    echo "Workflow run: $1"
} > "$EVIDENCE_FILE"

# Commit and push
git add -f "$EVIDENCE_FILE"
git commit --no-verify -m "Evidence: deployment $TIMESTAMP"
git push origin master

# Print raw link
RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${EVIDENCE_FILE}"
echo ""
echo "📄 Deployment evidence raw link:"
echo "$RAW_LINK"
