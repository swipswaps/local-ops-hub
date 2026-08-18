#!/usr/bin/env bash
# Check the last workflow run status on master
echo "=== Latest workflow run on master ==="
gh run list --branch master --limit 1 --json status,conclusion,displayTitle

# If the workflow hasn't run yet (or failed), trigger a new one
echo ""
echo "Triggering a fresh workflow run..."
gh workflow run "Deploy to GitHub Pages" --ref master

echo ""
echo "⏳ Waiting 60 seconds for the workflow to start..."
sleep 60

echo ""
echo "=== Current workflow run status ==="
gh run list --branch master --limit 1 --json status,conclusion,displayTitle

echo ""
echo "✅ After the workflow completes (green checkmark), visit:"
echo "   https://swipswaps.github.io/local-ops-hub/?v=$(date +%s)"
echo ""
echo "The query parameter ?v=... forces the browser to fetch fresh assets."
