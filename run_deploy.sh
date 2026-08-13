#!/usr/bin/env bash
export GITHUB_OWNER="swipswaps"
export GITHUB_REPO="local-ops-hub"
export DB_PASSWORD=""   # empty = auto-generate

# Ensure the script is executable
chmod +x deploy_local_ops_hub_v7.py

# Run it
python3 deploy_local_ops_hub_v7.py
