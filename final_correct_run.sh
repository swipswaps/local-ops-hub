#!/usr/bin/env bash
# Set the correct credential helper for gh (OAuth token)
git config --global credential.helper '!gh auth git-credential'
git config --local credential.helper '!gh auth git-credential'

echo "credential.helper = $(git config --get credential.helper)"

# Export environment variables to avoid prompts
export GITHUB_OWNER="swipswaps"
export GITHUB_REPO="local-ops-hub"
export DB_PASSWORD=""   # empty = auto-generate

# Run the patched deployment script
python3 deploy_local_ops_hub_v7.py
