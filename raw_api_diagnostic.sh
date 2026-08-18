#!/usr/bin/env bash
set -u

echo "=== Raw GitHub API Diagnostic ==="
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# 1. Latest workflow run (raw JSON)
echo "--- Latest workflow run ---"
gh api repos/swipswaps/local-ops-hub/actions/runs --paginate -q '.workflow_runs[0]'
echo ""

# 2. All artifacts (raw JSON)
echo "--- Artifacts from latest run ---"
gh api repos/swipswaps/local-ops-hub/actions/artifacts --paginate -q '.artifacts[0:3]'
echo ""

# 3. Pages site info (raw JSON)
echo "--- Pages site info ---"
gh api repos/swipswaps/local-ops-hub/pages
echo ""

# 4. Capture and push workflow logs
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId')
if [ -n "$RUN_ID" ]; then
    TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
    LOG_FILE="notes/workflow_logs_${TIMESTAMP}.txt"
    mkdir -p notes
    gh run view "$RUN_ID" --log > "$LOG_FILE" 2>&1
    git add -f "$LOG_FILE"
    git commit --no-verify -m "Logs: workflow $RUN_ID $TIMESTAMP" 2>/dev/null
    git push origin master 2>/dev/null
    RAW_LOG_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${LOG_FILE}"
    echo "📄 Raw workflow log link:"
    echo "$RAW_LOG_LINK"
else
    echo "⚠️ No workflow run found."
fi

# 5. Check the actual live site (raw HTML snippet)
echo ""
echo "--- Live site snippet (cache-busting) ---"
curl -s "https://swipswaps.github.io/local-ops-hub/?v=$(date +%s)" | grep -o 'README.md\|Rules-Compliant' | head -1
