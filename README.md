# AI quality loop demo: GitOps PR → test → remediate

A PR exposes a Prometheus metrics port. Agents write a test for what the PR *intends*, deploy it to a preview
namespace via Argo CD, run the test in Testkube, find the bug, get the fix reviewed, and re-run until green.
A human merges.

```
PR opened ─▶ test-author ─▶ push to `preview` ─▶ Argo CD sync (MCP) ─▶ Testkube run (MCP)
                                   ▲                                         │
                                   │ approved fix                     red ◀──┤──▶ green ─▶ PR comment
                                   └──── reviewer ◀── remediator ◀───────────┘
```

| Role | Where | Can do |
|---|---|---|
| Orchestrator | `.claude/skills/quality-loop` | git, Argo CD sync of **preview only**, Testkube runs, PR comment |
| test-author | `.claude/agents/test-author.md` | write `tests/pr-<N>.yaml`, register it in Testkube |
| remediator | `.claude/agents/remediator.md` | read Testkube + Argo CD, edit files (no commit) |
| reviewer | `.claude/agents/reviewer.md` | read-only, `VERDICT: APPROVE / REJECT` |

The seeded bug is in the PR's Service: the new `metrics` port has `targetPort: 9779` while the container
listens on 9797. Argo CD is Synced/Healthy (probes use the `http` port, a ClusterIP Service is always
Healthy), the smoke test passes on 9898, and only the behavioural check fails with connection refused.
The PR also adds a ServiceMonitor (`release: kps`), so the cluster's kube-prometheus-stack shows the podinfo
target **down** until the fix lands. `tests/ql-demo-selftest.yaml` proves the podinfo side of this on your cluster.

## Prerequisites
- minikube running, with the Testkube runner `default-runner-agent` already installed
- `kubectl`, `jq`, `curl`, `gh` (logged in), Node 18+ (`npx`), Claude Code

## One-time setup
```bash
# 1. Create the repo on GitHub (public, so Argo CD needs no credentials) and push this folder
gh repo create olensmar/ql-demo-gitops --public --source . --push

# 2. Create the preview branch
./bootstrap/create-preview-branch.sh

# 3. Install Argo CD and the agent account, register the apps, mint a token into .env.local
REPO_URL=https://github.com/olensmar/ql-demo-gitops.git ./bootstrap/install-argocd.sh

# 4. Keep Argo CD reachable (separate terminal, leave running)
./bootstrap/port-forward.sh
```

Wait until both apps are Synced/Healthy at http://localhost:8080, then run
`ql-demo-preflight` in Testkube. All three steps should be green.

### Argo CD MCP
`.mcp.json` launches argocd-mcp through `bootstrap/argocd-mcp.sh`, which reads `ARGOCD_BASE_URL` /
`ARGOCD_API_TOKEN` from the environment, `.env.local`, or the `env` block of `.claude/settings.local.json`
(also from the main checkout when running in a worktree). Nothing needs to be exported first, so it works
in Claude Desktop too.

### Testkube MCP
`.mcp.json` points at the hosted endpoint for your environment
(`tkcorg_9deb42dda2197657` / `tkcenv_a0058057f924cc8d`). The URL assumes the control plane for
`app.testkube.dev` is `api.testkube.dev`. If it isn't, export `TESTKUBE_MCP_URL`. On first use, run
`/mcp` in Claude Code to complete OAuth.

If you'd rather use the **"Testkube Ole Minikube" claude.ai connector** that Claude Code already picks up,
delete the `testkube` entry from `.mcp.json`. In the three agent files, replace `mcp__testkube` with the
connector's prefix as shown in `/mcp`.

## Run the demo
```bash
# once: the state every demo starts from (reset.sh restores main to it after an on-stage merge)
git tag demo-baseline origin/main && git push origin demo-baseline

# separate terminal: Prometheus UI on http://localhost:9090/targets
kubectl -n monitoring port-forward svc/kps-kube-prometheus-stack-prometheus 9090

./demo/make-pr.sh                   # opens the PR, note its number
claude
> /quality-loop <pr-number>
```

What the audience sees, with four windows open (PR, Argo CD, Testkube, Prometheus):
1. test-author lists the behaviours it will assert (metrics on 9797 via the Service, app still on 9898, taken from the PR body).
2. The agent pushes to `preview` and syncs via MCP. Argo CD goes **green**.
3. Testkube: smoke ✅, acceptance ❌. Logs show `:9797/metrics` → `connection refused`. Prometheus shows the
   `ql-demo-preview` podinfo target **down**.
4. remediator: **config-bug**. The live Service targets 9779 but the container port is 9797. The fix is one line: `targetPort: metrics`.
5. reviewer: **APPROVE**. It is a config fix, the test is unchanged, and it is within scope.
6. Re-deploy, re-run: both ✅, and the preview target turns **up** in Prometheus. A PR comment lists both
   attempts with Testkube links.
7. A human merges the PR on stage. `ql-demo-prod` auto-syncs from `main` (press **Refresh** in Argo CD), and
   the prod podinfo target appears **up** in Prometheus.

**Variation:** to show the reviewer earning its keep, tell the remediator in-session that "the test is
probably wrong". The reviewer should reject a fix that drops the metrics check or points the test at port 9898.

Reset between runs: `./demo/reset.sh <pr-number>`. It points `preview` back at `main` and syncs
`ql-demo-preview` through the Argo CD API with prune, so the PR's ServiceMonitor is removed and Prometheus stops
scraping preview. If the PR was merged, it also restores `apps/podinfo` on `main` to the `demo-baseline` tag,
so prod rolls back and the next run starts from the same manifests.

## Guardrails
- Argo CD RBAC: `ql-agent` can **get** everything but **sync only `ql-demo-preview`**.
- `.claude/settings.json` denies pushes to main (including `HEAD:main` refspecs), `gh pr merge`, `kubectl`,
  and edits to the prod overlay.
- Fixes need reviewer approval. The loop stops after 3 attempts.

## Next steps
- Trigger on `pull_request` from a self-hosted runner: `claude -p "/quality-loop $PR"`.
- Run the orchestrator itself as a Testkube Workflow in the cluster.
