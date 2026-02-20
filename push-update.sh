#!/bin/bash
# push-update.sh
# Run this script to push Claude's changes to GitHub as a preview branch.
# GitHub Actions will automatically create a PR and deploy a Vercel preview.
# You review the preview URL, then merge the PR to go live.
#
# Usage:
#   bash push-update.sh "description of what changed"
#
# Requirements:
#   - Git installed and configured (git config --global user.email / user.name)
#   - GitHub CLI installed: https://cli.github.com  (or use Personal Access Token)
#   - Run once: gh auth login

set -e

DESCRIPTION="${1:-website-update}"
BRANCH_NAME="claude-update/$(echo "$DESCRIPTION" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-' | cut -c1-50)-$(date +%Y%m%d-%H%M)"

echo ""
echo "🤖 Pushing Claude update to GitHub..."
echo "   Branch: $BRANCH_NAME"
echo "   Description: $DESCRIPTION"
echo ""

# Make sure we're on a clean state
git fetch origin main
git checkout main
git pull origin main

# Create new branch for this update
git checkout -b "$BRANCH_NAME"

# Stage all changed HTML, CSS, JS files
git add *.html js/*.js css/*.css 2>/dev/null || git add *.html

# Write the update message (used by GitHub Actions for PR body)
echo "$DESCRIPTION" > .claude-update-message.txt
git add .claude-update-message.txt

# Commit
git commit -m "🤖 Claude update: $DESCRIPTION"

# Push branch to GitHub
git push -u origin "$BRANCH_NAME"

echo ""
echo "✅ Pushed! GitHub Actions is now:"
echo "   1. Creating a Pull Request"
echo "   2. Deploying a preview to Vercel"
echo ""
echo "   Check your GitHub repo in ~60 seconds for the preview URL."
echo "   Merge the PR when you're happy with the preview."
echo ""

# Return to main
git checkout main
