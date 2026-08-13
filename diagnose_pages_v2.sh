#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
DIAG_FILE="notes/diagnostic_pages_${TIMESTAMP}.txt"
mkdir -p notes

{
echo "=== GitHub Pages Diagnostic — $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo ""
echo "--- Git branch ---"
BRANCH=$(git branch --show-current)
echo "BRANCH=$BRANCH"
echo ""

echo "--- Git remote ---"
REMOTE=$(git remote get-url origin)
echo "REMOTE=$REMOTE"
echo ""

echo "--- Owner/Repo ---"
# Parse from remote URL
OWNER_REPO=$(echo "$REMOTE" | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')
echo "OWNER_REPO=$OWNER_REPO"
echo ""

echo "--- GitHub Actions latest run ---"
gh api "repos/${OWNER_REPO}/actions/runs" --paginate -q '.workflow_runs[0] | {id, status, conclusion, created_at, updated_at}'
echo ""

echo "--- Pages build history (last 5) ---"
gh api "repos/${OWNER_REPO}/pages/builds" -q '.[0:5] | map({status, created_at, commit})'
echo ""

echo "--- Pages site info ---"
gh api "repos/${OWNER_REPO}/pages"
echo ""

echo "--- List artifacts (latest workflow) ---"
gh api "repos/${OWNER_REPO}/actions/artifacts" --paginate -q '.artifacts[0:3] | map({name, created_at, size_in_bytes})'
echo ""

echo "--- curl -v to pages URL ---"
PAGES_URL="https://swipswaps.github.io/local-ops-hub/"
curl -v -L -o /dev/null -w "\nHTTP Status: %{http_code}\n" "$PAGES_URL" 2>&1
echo ""

} 2>&1 | tee "$DIAG_FILE"

# Push to the correct branch
git add -f "$DIAG_FILE"
git commit --no-verify -m "Diagnostic: pages 404 $(date -u +%Y%m%d%H%M%S)"
git push origin "$BRANCH"

# Build raw link
RAW_LINK="https://raw.githubusercontent.com/${OWNER_REPO}/${BRANCH}/${DIAG_FILE}"
echo ""
echo "📄 Diagnostic raw link:"
echo "$RAW_LINK"
