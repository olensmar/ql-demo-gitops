#!/usr/bin/env bash
# Resets the demo so it can run again: closes (or un-merges) the PR, deletes its branch,
# and points preview back at main.
#   ./demo/reset.sh <pr-number>
#
# If the PR was merged on stage, main (and so ql-demo-prod) is restored to the `demo-baseline`
# tag: apps/podinfo goes back to its baseline content and AI-authored tests/pr-*.yaml are removed.
# Create the tag once, on a main you want every demo to start from:
#   git tag demo-baseline origin/main && git push origin demo-baseline
set -euo pipefail
PR="${1:?usage: reset.sh <pr-number>}"
cd "$(dirname "$0")/.."

read -r STATE BRANCH < <(gh pr view "$PR" --json state,headRefName -q '"\(.state) \(.headRefName)"')

git fetch origin --tags
git checkout main && git pull --ff-only

if [[ "$STATE" == "MERGED" ]]; then
  git rev-parse -q --verify demo-baseline >/dev/null \
    || { echo "PR #$PR was merged but tag demo-baseline is missing; see the header of this script." >&2; exit 1; }
  git restore --source=demo-baseline --staged --worktree -- apps/podinfo
  git rm -q --ignore-unmatch 'tests/pr-*.yaml'
  if git diff --cached --quiet; then
    echo "main already matches demo-baseline."
  else
    git commit -m "demo: reset after PR #$PR (restore apps/podinfo to demo-baseline)"
    git push origin main
    echo "main restored; ql-demo-prod auto-syncs back (press Refresh in Argo CD to speed it up)."
  fi
  git push origin --delete "$BRANCH" 2>/dev/null || true
else
  gh pr close "$PR" --delete-branch --comment "Demo reset." || true
fi

git push --force origin main:refs/heads/preview
git branch -D "$BRANCH" 2>/dev/null || true

echo "Preview branch reset to main. Sync ql-demo-preview in the Argo CD UI (or let the next loop do it)."
echo "Optional: remove the generated workflow ->  testkube delete testworkflow ql-demo-pr-$PR"
