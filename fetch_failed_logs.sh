#!/usr/bin/env bash
# Fetch logs from the latest failed workflow run and push as evidence

# Set correct credential helper
git config --global credential.helper '!gh auth git-credential'
git config --local credential.helper '!gh auth git-credential'

echo "credential.helper = $(git config --get credential.helper)"

# Get the latest failed run ID
RUN_ID=$(gh run list --status failure --limit 1 --json databaseId -q '.[0].databaseId')
if [ -z "$RUN_ID" ]; then
    echo "No failed workflow runs found."
    exit 1
fi
echo "Latest failed run ID: $RUN_ID"

# Fetch the failed logs
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
LOG_FILE="notes/workflow_logs_${TIMESTAMP}.txt"
mkdir -p notes

{
    echo "=== Workflow Failure Logs ==="
    echo "Run ID: $RUN_ID"
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "--- Full failed logs ---"
    gh run view "$RUN_ID" --log-failed 2>&1
} > "$LOG_FILE"

echo "Logs saved to $LOG_FILE"

# Push the log file
git add -f "$LOG_FILE"
git commit --no-verify -m "Diagnostic: workflow failure logs $TIMESTAMP"
git push origin master

# Print raw link
RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${LOG_FILE}"
echo ""
echo "📄 Raw workflow log link:"
echo "$RAW_LINK"
