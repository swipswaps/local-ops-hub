#!/usr/bin/env bash
# Update workflow to trigger on master as well

cat > .github/workflows/deploy.yml << 'YML'
name: Deploy to GitHub Pages

on:
  push:
    branches: [main, master]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: "pages"
  cancel-in-progress: false

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: "20"
          cache: "npm"
      - name: Install dependencies
        run: npm ci
      - name: Build
        run: npm run build
      - name: Setup Pages
        uses: actions/configure-pages@v4
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: "./dist"
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
YML

git add .github/workflows/deploy.yml
git commit --no-verify -m "fix: trigger workflow on master branch"
git push origin master

echo "✅ Workflow updated. Pushing to master will now trigger deployment."
echo "Triggering a fresh workflow run..."
gh workflow run "Deploy to GitHub Pages" --ref master
