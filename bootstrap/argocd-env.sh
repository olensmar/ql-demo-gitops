# Sourced (not executed) by bootstrap/argocd-mcp.sh and demo/reset.sh. Exports ARGOCD_BASE_URL and
# ARGOCD_API_TOKEN, first match wins per variable:
#   1. the inherited environment (ignored if it is still an unexpanded ${...} placeholder, which hosts
#      such as Claude Desktop pass through from .mcp.json)
#   2. .env.local                    (written by install-argocd.sh)
#   3. .claude/settings.local.json   (its "env" block)
# Steps 2 and 3 check this checkout first, then the main checkout, so git worktrees work too.
# ARGOCD_BASE_URL falls back to http://localhost:8080. Prints nothing.

_argocd_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_argocd_common="$(git -C "$_argocd_root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
_argocd_main="${_argocd_common:+$(dirname "$_argocd_common")}"
_argocd_main="${_argocd_main:-$_argocd_root}"

_argocd_resolve() {
  local name="$1" val="${!1:-}" dir line
  [[ -n "$val" && "$val" != '${'* ]] && { printf '%s' "$val"; return; }
  for dir in "$_argocd_root" "$_argocd_main"; do
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

ARGOCD_BASE_URL="$(_argocd_resolve ARGOCD_BASE_URL)"
ARGOCD_API_TOKEN="$(_argocd_resolve ARGOCD_API_TOKEN)"
export ARGOCD_BASE_URL="${ARGOCD_BASE_URL:-http://localhost:8080}" ARGOCD_API_TOKEN
