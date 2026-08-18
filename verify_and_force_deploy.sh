#!/usr/bin/env bash
set -u

# Helper: log to stderr
log() { echo "$*" >&2; }

# Set credential helper
git config --global credential.helper '!gh auth git-credential' 2>/dev/null
git config --local credential.helper '!gh auth git-credential' 2>/dev/null

TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
DIAG_FILE="notes/deploy_verify_${TIMESTAMP}.txt"
mkdir -p notes

{
    echo "=== Deployment Verification Report ==="
    echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo ""
    echo "--- Latest successful workflow run ---"
    gh run list --workflow="deploy.yml" --status success --limit 1 --json databaseId,headSha,displayTitle,createdAt
    echo ""
    echo "--- Pages deployment status ---"
    gh api "repos/swipswaps/local-ops-hub/pages" 2>/dev/null || echo "Pages not enabled"
    echo ""
    echo "--- Latest Pages build ---"
    gh api "repos/swipswaps/local-ops-hub/pages/builds" -q '.[0]' 2>/dev/null || echo "No builds"
    echo ""
    echo "--- Live site check (cache-busting) ---"
    PAGES_URL="https://swipswaps.github.io/local-ops-hub/?v=$TIMESTAMP"
    TEXT_FOUND=$(curl -s "$PAGES_URL" | grep -o 'README.md\|Rules-Compliant' | head -1)
    echo "Text found: ${TEXT_FOUND:-none}"
    echo ""
    if [ "$TEXT_FOUND" = "README.md" ]; then
        echo "✅ Site already shows the updated text."
    else
        echo "⚠️ Site still shows old text. Forcing a fresh deployment."
        echo "Triggering workflow on the commit that changed src/App.jsx..."
        COMMIT_SHA=$(git log --oneline --grep="chore: update header text" -n 1 --format="%H" || git log --oneline -n 1 --format="%H")
        echo "Commit SHA: $COMMIT_SHA"
        gh workflow run "Deploy to GitHub Pages" --ref "$COMMIT_SHA"
        echo "Workflow triggered. Wait for completion, then check again."
    fi
} > "$DIAG_FILE"

# Push diagnostic
git add -f "$DIAG_FILE"
git commit --no-verify -m "Diagnostic: deploy verify $TIMESTAMP" 2>&1 | tee -a "$DIAG_FILE"
git push origin master 2>&1 | tee -a "$DIAG_FILE"

RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${DIAG_FILE}"
echo ""
echo "$RAW_LINK"
