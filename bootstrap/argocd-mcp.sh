#!/usr/bin/env bash
# Launches argocd-mcp (stdio) for .mcp.json with real Argo CD credentials, resolved by argocd-env.sh
# because hosts such as Claude Desktop pass ${VAR} placeholders through unexpanded.
# stdout is the MCP channel: diagnostics go to stderr only.
set -euo pipefail

. "$(dirname "$0")/argocd-env.sh"

[[ -n "$ARGOCD_API_TOKEN" ]] || echo "argocd-mcp.sh: ARGOCD_API_TOKEN not found (env, .env.local, .claude/settings.local.json)" >&2

exec npx -y argocd-mcp@latest stdio
