#!/usr/bin/env bash
# Opens the demo PR: a one-line config change with a seeded typo in the message key.
# Argo CD will be green; only a behavioural test catches it.
set -euo pipefail
BRANCH="${BRANCH:-feat/demo-welcome-message}"
cd "$(dirname "$0")/.."

git fetch origin main
git checkout -B "$BRANCH" origin/main

cat > apps/podinfo/base/config.env <<'EOF'
PODINFO_UI_MESAGE=Welcome to the Cloud Native Testing demo
PODINFO_UI_COLOR=#34577c
EOF

git add apps/podinfo/base/config.env
git commit -m "Update podinfo welcome message and brand colour"
git push -u --force origin "$BRANCH"

gh pr create --base main --head "$BRANCH" \
  --title "Update podinfo welcome message and brand colour" \
  --body "$(cat <<'EOF'
For the Cloud Native Testing demo, podinfo should greet visitors with our own message and use the brand colour.

**Intended behaviour**
- UI message: `Welcome to the Cloud Native Testing demo`
- UI colour: `#34577c`

Config-only change, no code.
EOF
)"
