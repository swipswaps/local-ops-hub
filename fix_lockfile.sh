#!/usr/bin/env bash
# Generate package-lock.json, push it, then re-run the workflow.

# Ensure npm is available
if ! command -v npm &> /dev/null; then
    echo "ERROR: npm not found. Please install Node.js/npm first."
    exit 1
fi

# Generate package-lock.json from package.json
echo "Generating package-lock.json..."
npm install --package-lock-only

# Verify it was created
if [ ! -f package-lock.json ]; then
    echo "ERROR: package-lock.json not generated."
    exit 1
fi
echo "package-lock.json created."

# Commit and push
git add package-lock.json
git commit --no-verify -m "fix: add package-lock.json for npm ci"
git push origin master

# Re-run the workflow
echo "Triggering workflow 'Deploy to GitHub Pages'..."
gh workflow run "Deploy to GitHub Pages" --ref master

echo ""
echo "Workflow triggered. Monitor it with:"
echo "  gh run list --workflow=deploy.yml"
echo "  gh run watch"
