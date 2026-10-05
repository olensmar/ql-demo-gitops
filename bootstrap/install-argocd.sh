#!/usr/bin/env bash
# One-shot setup of Argo CD on minikube for the quality-loop demo.
#
#   REPO_URL=https://github.com/olensmar/ql-demo-gitops.git ./bootstrap/install-argocd.sh
#
# What it does:
#   1. Installs Argo CD (stable) into the `argocd` namespace
#   2. Serves the API over plain HTTP (local demo only) so argocd-mcp needs no TLS workarounds
#   3. Creates a local API account `ql-agent` that may READ everything but SYNC only ql-demo-preview
#   4. Registers the ql-demo-prod and ql-demo-preview Applications
#   5. Mints an API token for ql-agent and writes ARGOCD_BASE_URL / ARGOCD_API_TOKEN to .env.local
set -euo pipefail

REPO_URL="${REPO_URL:?set REPO_URL to the https URL of your ql-demo-gitops repo}"
ARGOCD_PORT="${ARGOCD_PORT:-8080}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

ctx="$(kubectl config current-context)"
if [[ "$ctx" != "minikube" && "${FORCE:-}" != "1" ]]; then
  echo "kubectl context is '$ctx', not 'minikube'. Re-run with FORCE=1 if that's intended." >&2
  exit 1
fi
for bin in kubectl curl jq; do command -v "$bin" >/dev/null || { echo "missing: $bin" >&2; exit 1; }; done

echo "==> Installing Argo CD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "==> Configuring insecure (HTTP) API, ql-agent account and RBAC"
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge \
  -p '{"data":{"server.insecure":"true"}}'
kubectl -n argocd patch configmap argocd-cm --type merge \
  -p '{"data":{"accounts.ql-agent":"apiKey","timeout.reconciliation":"60s"}}'
kubectl -n argocd patch configmap argocd-rbac-cm --type merge -p "$(jq -n --arg csv \
'p, role:ql-agent, applications, get, default/*, allow
p, role:ql-agent, applications, sync, default/ql-demo-preview, allow
p, role:ql-agent, logs, get, default/*, allow
p, role:ql-agent, projects, get, default, allow
p, role:ql-agent, clusters, get, *, allow
g, ql-agent, role:ql-agent' '{data: {"policy.csv": $csv}}')"

kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout status deployment argocd-server --timeout=300s
kubectl -n argocd rollout status statefulset argocd-application-controller --timeout=300s
kubectl -n argocd rollout status deployment argocd-repo-server --timeout=300s

echo "==> Registering Applications for $REPO_URL"
sed "s#REPO_URL#${REPO_URL}#g" "$ROOT/argocd/applications.yaml" | kubectl apply -f -

echo "==> Minting ql-agent API token"
kubectl -n argocd port-forward svc/argocd-server "${ARGOCD_PORT}:80" >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do curl -sf "http://localhost:${ARGOCD_PORT}/healthz" >/dev/null && break; sleep 1; done

ADMIN_PW="$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
ADMIN_TOKEN="$(curl -sf "http://localhost:${ARGOCD_PORT}/api/v1/session" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n --arg p "$ADMIN_PW" '{username:"admin",password:$p}')" | jq -r .token)"
AGENT_TOKEN="$(curl -sf -X POST "http://localhost:${ARGOCD_PORT}/api/v1/account/ql-agent/token" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" -H 'Content-Type: application/json' \
  -d '{"id":"ql-demo","name":"ql-demo"}' | jq -r .token)"
[[ -n "$AGENT_TOKEN" && "$AGENT_TOKEN" != "null" ]] || { echo "token mint failed" >&2; exit 1; }

umask 077
cat > "$ROOT/.env.local" <<EOF
ARGOCD_BASE_URL=http://localhost:${ARGOCD_PORT}
ARGOCD_API_TOKEN=${AGENT_TOKEN}
EOF

cat <<EOF

Done.
  - Argo CD admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  - Agent credentials written to .env.local (gitignored)
  - Keep this running in a separate terminal during the demo:
      ./bootstrap/port-forward.sh
  - UI: http://localhost:${ARGOCD_PORT}  (user: admin)
EOF
