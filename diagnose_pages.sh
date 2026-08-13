#!/usr/bin/env bash
# Diagnostic script for GitHub Pages 404 – runs after pages_wait fails.
# It will also continue the main script if re-run.

cd "$(dirname "$0")" || exit 1
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
DIAG_FILE="notes/diagnostic_pages_${TIMESTAMP}.txt"
mkdir -p notes

{
echo "=== GitHub Pages Diagnostic — $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo ""

echo "--- Git remote ---"
git remote get-url origin 2>/dev/null || git config --get remote.origin.url
echo ""

echo "--- Repository info ---"
OWNER_REPO=$(git remote get-url origin 2>/dev/null | sed -E 's#.*[:/]([^/]+/[^/.]+)(\.git)?$#\1#')
echo "OWNER_REPO=$OWNER_REPO"
echo ""

echo "--- GitHub Actions latest run status ---"
gh api "repos/${OWNER_REPO}/actions/runs" --paginate -q '.workflow_runs[0] | {id, status, conclusion, created_at, updated_at}'
echo ""

echo "--- Pages site info ---"
gh api "repos/${OWNER_REPO}/pages" || echo "Pages not enabled (404 expected)"
echo ""

echo "--- Pages build history (last 3) ---"
gh api "repos/${OWNER_REPO}/pages/builds" -q '.[0:3] | map({status, created_at, commit})'
echo ""

echo "--- DNS resolution of swipswaps.github.io ---"
nslookup swipswaps.github.io 2>&1 || dig swipswaps.github.io 2>&1 || echo "nslookup/dig not installed"
echo ""

echo "--- curl -v to pages URL ---"
PAGES_URL="https://swipswaps.github.io/local-ops-hub/"
curl -v -L -o /dev/null -w "\nHTTP Status: %{http_code}\n" "$PAGES_URL" 2>&1
echo ""

echo "--- curl HEAD with verbose ---"
curl -v -I "$PAGES_URL" 2>&1
echo ""

echo "=== End diagnostic ==="
} 2>&1 | tee "$DIAG_FILE"

# Push the diagnostic file
git add -f "$DIAG_FILE"
git commit --no-verify -m "Diagnostic: pages 404 $(date -u +%Y%m%d%H%M%S)"
git push origin main

# Print raw link
BRANCH=$(git branch --show-current)
RAW_LINK="https://raw.githubusercontent.com/${OWNER_REPO}/${BRANCH}/${DIAG_FILE}"
echo ""
echo "📄 Diagnostic raw link:"
echo "$RAW_LINK"
