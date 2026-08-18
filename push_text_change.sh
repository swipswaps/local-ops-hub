#!/usr/bin/env bash
set -u

echo "=== Pushing the text change to master ==="

# Check if the commit with README.md exists locally
COMMIT_SHA=$(git log -S "README.md" --oneline -n 1 --format="%H" 2>/dev/null)

if [ -n "$COMMIT_SHA" ]; then
    echo "Found commit: $COMMIT_SHA"
    echo "Pushing it to master..."
    if git push origin "$COMMIT_SHA:master" 2>&1; then
        echo "✅ Commit pushed to master."
    else
        echo "⚠️ Push failed. The commit may already be on master or may be outdated."
        echo "Re‑creating the change..."
        sed -i 's/README/README.md/g' src/App.jsx
        git add src/App.jsx
        git commit -m "fix: update header to README.md"
        git push origin master
    fi
else
    echo "No commit with README.md found. Re‑creating the change..."
    sed -i 's/README/README.md/g' src/App.jsx
    git add src/App.jsx
    git commit -m "fix: update header to README.md"
    git push origin master
fi

echo ""
echo "Triggering workflow on master..."
gh workflow run "Deploy to GitHub Pages" --ref master

echo ""
echo "✅ Done. Check status with: gh run list --workflow=deploy.yml --limit 1"
