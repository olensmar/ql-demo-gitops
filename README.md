# AI quality loop demo: GitOps PR → test → remediate

A PR changes one line of config. Agents write a test for what the PR *intends*, deploy it to a preview
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

The seeded bug is in the PR's config: the message key is spelled `PODINFO_UI_MESAGE`. Argo CD is
Synced/Healthy, the colour check passes, and only the behavioural check fails.
`tests/ql-demo-selftest.yaml` proves this behaviour on your cluster.

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
./demo/make-pr.sh                   # opens the PR, note its number
claude
> /quality-loop <pr-number>
```

What the audience sees, with three windows open (PR, Argo CD, Testkube):
1. test-author lists the behaviours it will assert (message + colour, taken from the PR body).
2. The agent pushes to `preview` and syncs via MCP. Argo CD goes **green**.
3. Testkube: smoke ✅, acceptance ❌. Logs show `message: "greetings from podinfo v6.7.1"`.
4. remediator: **config-bug**, typo `PODINFO_UI_MESAGE`. The fix is a one-character diff.
5. reviewer: **APPROVE**. It is a config fix, the test is unchanged, and it is within scope.
6. Re-deploy, re-run: both ✅. A PR comment lists both attempts with Testkube links.

**Variation:** to show the reviewer earning its keep, tell the remediator in-session that "the test is
probably wrong". The reviewer should reject a fix that changes the expected message to the default greeting.

Reset between runs: `./demo/reset.sh <pr-number>`.

## Guardrails
- Argo CD RBAC: `ql-agent` can **get** everything but **sync only `ql-demo-preview`**.
- `.claude/settings.json` denies pushes to main, `gh pr merge`, `kubectl`, and edits to the prod overlay.
- Fixes need reviewer approval. The loop stops after 3 attempts.

## Next steps
- Trigger on `pull_request` from a self-hosted runner: `claude -p "/quality-loop $PR"`.
- Run the orchestrator itself as a Testkube Workflow in the cluster.
