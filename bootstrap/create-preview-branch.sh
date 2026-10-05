#!/usr/bin/env bash
# Creates (or resets) the `preview` branch from main so ql-demo-preview has something to track.
set -euo pipefail
git fetch origin main
git push --force origin origin/main:refs/heads/preview
echo "preview branch now points at origin/main"
