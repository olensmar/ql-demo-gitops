#!/usr/bin/env bash
# Launches argocd-mcp (stdio) for .mcp.json with real Argo CD credentials.
#
# Hosts such as Claude Desktop pass ${VAR} placeholders through unexpanded, so credentials are
# resolved here instead, first match wins per variable:
#   1. the inherited environment (ignored if it is still an unexpanded ${...} placeholder)
#   2. .env.local                    (written by install-argocd.sh)
#   3. .claude/settings.local.json   (its "env" block)
# Steps 2 and 3 check this checkout first, then the main checkout, so git worktrees work too.
# stdout is the MCP channel: diagnostics go to stderr only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMON="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
MAIN="${COMMON:+$(dirname "$COMMON")}"
MAIN="${MAIN:-$ROOT}"

resolve() {
  local name="$1" val="${!1:-}" dir line
  [[ -n "$val" && "$val" != '${'* ]] && { printf '%s' "$val"; return; }
  for dir in "$ROOT" "$MAIN"; do
    if [[ -f "$dir/.env.local" ]]; then
      line="$(grep -E "^${name}=" "$dir/.env.local" | tail -n1 || true)"
      [[ -n "$line" ]] && { printf '%s' "${line#*=}"; return; }
    fi
    if [[ -f "$dir/.claude/settings.local.json" ]]; then
      val="$(jq -r --arg k "$name" '.env[$k] // empty' "$dir/.claude/settings.local.json" 2>/dev/null || true)"
      [[ -n "$val" ]] && { printf '%s' "$val"; return; }
    fi
  done
  return 0
}

ARGOCD_BASE_URL="$(resolve ARGOCD_BASE_URL)"
ARGOCD_API_TOKEN="$(resolve ARGOCD_API_TOKEN)"
export ARGOCD_BASE_URL="${ARGOCD_BASE_URL:-http://localhost:8080}" ARGOCD_API_TOKEN

[[ -n "$ARGOCD_API_TOKEN" ]] || echo "argocd-mcp.sh: ARGOCD_API_TOKEN not found (env, .env.local, .claude/settings.local.json)" >&2

exec npx -y argocd-mcp@latest stdio
