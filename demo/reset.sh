#!/usr/bin/env bash
# Resets the demo so it can run again: closes (or un-merges) the PR, deletes its branch,
# points preview back at main, and syncs ql-demo-preview through the Argo CD API.
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

# ql-demo-preview has no auto-sync, so sync it to main here (prune removes the PR's ServiceMonitor);
# otherwise the PR's manifests keep running and Prometheus keeps scraping preview.
. bootstrap/argocd-env.sh
argocd_api() { curl -sf -H "Authorization: Bearer $ARGOCD_API_TOKEN" "$@"; }
MAIN_SHA="$(git rev-parse main)"
APP_URL="$ARGOCD_BASE_URL/api/v1/applications/ql-demo-preview"

if [[ -z "$ARGOCD_API_TOKEN" ]] || ! argocd_api -o /dev/null "$APP_URL"; then
  echo "Argo CD not reachable at $ARGOCD_BASE_URL (port-forward down?): sync ql-demo-preview in the UI, with Prune." >&2
else
  argocd_api -o /dev/null -X POST -H 'Content-Type: application/json' \
    -d "{\"revision\":\"$MAIN_SHA\",\"prune\":true}" "$APP_URL/sync" \
    || echo "Sync request rejected (another operation running?); waiting for the app state anyway." >&2
  want="${MAIN_SHA} Synced Healthy Succeeded" state=""
  for _ in $(seq 1 36); do   # up to 3 minutes
    state="$(argocd_api "$APP_URL" | jq -r '"\(.status.sync.revision) \(.status.sync.status) \(.status.health.status) \(.status.operationState.phase)"' || true)"
    [[ "$state" == "$want" ]] && break
    sleep 5
  done
  if [[ "$state" == "$want" ]]; then
    echo "ql-demo-preview synced to main (${MAIN_SHA:0:7}), Synced / Healthy."
  else
    echo "ql-demo-preview not settled after 3 minutes (state: $state); check it in the Argo CD UI." >&2
  fi
  if [[ "$STATE" == "MERGED" ]]; then
    argocd_api -o /dev/null "$ARGOCD_BASE_URL/api/v1/applications/ql-demo-prod?refresh=normal" \
      && echo "ql-demo-prod refreshed; auto-sync rolls it back to main."
  fi
fi

echo "Optional: remove the generated workflow ->  testkube delete testworkflow ql-demo-pr-$PR"
