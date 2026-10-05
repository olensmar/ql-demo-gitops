#!/usr/bin/env bash
# Keeps the Argo CD API/UI reachable on localhost for argocd-mcp and the browser.
set -euo pipefail
PORT="${ARGOCD_PORT:-8080}"
echo "Argo CD on http://localhost:${PORT} (Ctrl-C to stop)"
while true; do
  kubectl -n argocd port-forward svc/argocd-server "${PORT}:80" || true
  echo "port-forward dropped, restarting in 2s..."; sleep 2
done
