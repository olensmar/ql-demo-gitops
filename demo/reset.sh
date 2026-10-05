#!/usr/bin/env bash
# Resets the demo so it can run again: closes the PR, deletes its branch, points preview back at main.
#   ./demo/reset.sh <pr-number>
set -euo pipefail
PR="${1:?usage: reset.sh <pr-number>}"
cd "$(dirname "$0")/.."

BRANCH="$(gh pr view "$PR" --json headRefName -q .headRefName)"
gh pr close "$PR" --delete-branch --comment "Demo reset." || true
git checkout main && git pull --ff-only
git push --force origin origin/main:refs/heads/preview
git branch -D "$BRANCH" 2>/dev/null || true

echo "Preview branch reset to main. Sync ql-demo-preview in the Argo CD UI (or let the next loop do it)."
echo "Optional: remove the generated workflow ->  testkube delete testworkflow ql-demo-pr-$PR"
