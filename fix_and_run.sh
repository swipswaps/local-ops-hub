#!/usr/bin/env bash
# Fix credential helper – ensures git push uses gh token (no password)
git config --global credential.helper github-cli
git config --local credential.helper github-cli

echo "Credential helper is now: $(git config --get credential.helper)"

# Set environment variables to avoid prompts
export GITHUB_OWNER="swipswaps"
export GITHUB_REPO="local-ops-hub"
export DB_PASSWORD=""   # empty = auto‑generate

# Run the deployment script
python3 deploy_local_ops_hub_v7.py
