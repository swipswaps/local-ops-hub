#!/usr/bin/env bash
set -u

TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
LOG_FILE="notes/workflow_logs_${TIMESTAMP}.txt"
mkdir -p notes

# Get the latest run ID (any status)
RUN_ID=$(gh run list --workflow="deploy.yml" --limit 1 --json databaseId -q '.[0].databaseId')
if [ -z "$RUN_ID" ]; then
    echo "No workflow runs found."
    exit 1
fi

echo "=== Workflow Logs ==="
echo "Run ID: $RUN_ID"
echo "Fetching logs..."

# Fetch and display the full logs
gh run view "$RUN_ID" --log 2>&1 | tee "$LOG_FILE"

# Also show the run status
echo ""
echo "=== Run Status ==="
gh run view "$RUN_ID" --json status,conclusion,displayTitle

# Push the log file
git add -f "$LOG_FILE"
git commit --no-verify -m "Logs: workflow $RUN_ID $TIMESTAMP"
git push origin master

RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${LOG_FILE}"
echo ""
echo "📄 Logs saved to: $RAW_LINK"
