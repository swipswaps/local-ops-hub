#!/usr/bin/env bash
# Force a Pages deployment and wait for it to be live

# Step 1: Ensure credential helper is correct
git config --global credential.helper '!gh auth git-credential'
git config --local credential.helper '!gh auth git-credential'

# Step 2: Trigger the workflow manually (if not already running)
echo "Triggering workflow 'Deploy to GitHub Pages'..."
gh workflow run "Deploy to GitHub Pages" --ref master

# Step 3: Wait for the workflow to complete
echo "Waiting for workflow to complete..."
while true; do
  STATUS=$(gh api repos/swipswaps/local-ops-hub/actions/runs --paginate -q '.workflow_runs[0].status')
  CONCLUSION=$(gh api repos/swipswaps/local-ops-hub/actions/runs --paginate -q '.workflow_runs[0].conclusion')
  echo "Status: $STATUS, Conclusion: $CONCLUSION"
  if [ "$STATUS" = "completed" ]; then
    if [ "$CONCLUSION" = "success" ]; then
      echo "Workflow completed successfully."
      break
    else
      echo "Workflow failed with conclusion: $CONCLUSION. Check logs."
      exit 1
    fi
  fi
  sleep 10
done

# Step 4: Wait for Pages to become live (max 10 minutes)
PAGES_URL="https://swipswaps.github.io/local-ops-hub/"
echo "Waiting for Pages to become live at $PAGES_URL"
for i in {1..60}; do
  if curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL" | grep -q 200; then
    echo "Pages is live!"
    break
  fi
  echo "Attempt $i: still 404..."
  sleep 10
done

# Step 5: Write evidence
TIMESTAMP=$(date -u +%Y%m%d%H%M%S)
EVIDENCE_FILE="notes/deploy_${TIMESTAMP}.txt"
mkdir -p notes
{
  echo "=== Deployment Evidence ==="
  echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Owner: swipswaps"
  echo "Repo: local-ops-hub"
  echo "Pages URL: $PAGES_URL"
  echo "Pages live: $(curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL" | grep -q 200 && echo "YES" || echo "NO")"
  echo "Workflow conclusion: $CONCLUSION"
} > "$EVIDENCE_FILE"

# Step 6: Push evidence
git add -f "$EVIDENCE_FILE"
git commit --no-verify -m "Evidence: deployment $TIMESTAMP"
git push origin master

# Step 7: Print raw link
RAW_LINK="https://raw.githubusercontent.com/swipswaps/local-ops-hub/master/${EVIDENCE_FILE}"
echo ""
echo "📄 Deployment evidence raw link:"
echo "$RAW_LINK"
