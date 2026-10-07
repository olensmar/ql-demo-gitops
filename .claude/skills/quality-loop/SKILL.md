---
name: quality-loop
description: Run the AI quality loop on a GitOps PR — author a test, deploy the PR to preview via Argo CD, run it in Testkube, and remediate failures with a reviewed fix (max 3 attempts).
argument-hint: <pr-number>
disable-model-invocation: true
---

# Quality loop for PR #$ARGUMENTS

You are the **orchestrator**. You own git, Argo CD sync and Testkube runs. You delegate thinking work to
three subagents: `test-author`, `remediator` and `reviewer`. Narrate each phase in one short line
before you start it (the audience is watching), e.g. `▶ Phase 2 — deploying PR head to preview`.

## Constants
- Argo CD preview app: `ql-demo-preview` (tracks branch `preview`). **Never** sync or touch `ql-demo-prod`.
- Testkube runner target: `{"name": "default-runner-agent"}`
- Workflows per iteration: `ql-demo-smoke` and `ql-demo-pr-$ARGUMENTS`
- Max remediation attempts: **3**

## Guardrails
- Push only to the PR head branch and to `preview`. Never push to `main`, never merge, never force-push the PR branch.
- Every remediation must get `VERDICT: APPROVE` from `reviewer` before it is committed.
- If anything looks like an environment problem (port-forward down, runner offline), stop and tell the human.

## Phase 0 — Preflight
1. `gh pr view $ARGUMENTS --json number,title,body,headRefName,url` and `gh pr diff $ARGUMENTS`.
2. `gh pr checkout $ARGUMENTS` and `git fetch origin`.
3. Argo CD MCP `get_application` on `ql-demo-preview` (proves the MCP and port-forward work).
4. Testkube MCP `list_agents` (proves the runner is online).

## Phase 1 — Author the test
Delegate to **test-author**, passing the PR title, body and diff. When it returns:
- `git add tests/pr-$ARGUMENTS.yaml && git commit -m "test: AI-authored acceptance test for #$ARGUMENTS"`
- `git push origin HEAD`
Show the asserted behaviours in one short list.

## Phase 2 — Deploy PR head to preview
1. `git push --force origin HEAD:preview` and remember `SHA=$(git rev-parse HEAD)`.
2. Argo CD MCP `sync_application` on `ql-demo-preview` with prune enabled.
3. Poll `get_application` every ~5s (up to 3 min) until `status.sync.revision == SHA`,
   `status.sync.status == Synced`, `status.health.status == Healthy`, and the last operation succeeded.
   If it becomes Degraded or times out, treat it as a failed run and go to Phase 4 with the Argo CD state as evidence.

## Phase 3 — Run tests
1. `run_workflow` for `ql-demo-smoke` and `ql-demo-pr-$ARGUMENTS`, both with the runner target above.
2. `wait_for_executions` on both IDs. If it returns no status, poll `get_execution_info` until finished.
3. For each execution, get a link with `build_dashboard_url` (resourceType `execution`).
4. Record the attempt: number, SHA, statuses, execution links, and for a failure the one-line reason
   (e.g. `connection refused on :9797/metrics`).
5. Both passed → Phase 5. Otherwise → Phase 4.

## Phase 4 — Remediate (attempts 1..3)
1. Delegate to **remediator** with the PR intent, failing execution IDs, and any previous reviewer feedback.
2. If it classifies the failure as `env-issue` → stop, report to the human.
3. Delegate to **reviewer** with the PR intent and the remediator's report. It inspects the working tree itself.
4. On `VERDICT: REJECT` → `git checkout -- .` to discard, pass the feedback back to remediator (this counts as an attempt).
5. On `VERDICT: APPROVE` → commit with
   `fix(<config|test>): <root cause> (AI remediation, reviewer-approved)`, `git push origin HEAD`, then go back to Phase 2.
6. After 3 attempts without green → Phase 5 with status FAILED.

## Phase 5 — Report
Post one PR comment with `gh pr comment $ARGUMENTS --body-file -` containing:
- Result: ✅ PASSED after N attempt(s), or ❌ needs human attention
- What was tested (behaviours from Phase 1)
- An attempts table: `# | commit | smoke | acceptance | Testkube links`
- For each remediation: classification, root cause, reviewer verdict
- Footer: "Merge decision stays with a human."

Keep the comment URL that `gh pr comment` prints.

## Final output
End the run with this summary and nothing after it. Print it as **normal markdown, never inside a code
block**: Claude Code turns markdown links into clickable terminal hyperlinks, but prints code blocks as plain
text, where long URLs wrap and can't be clicked. Use short labelled links `[label](url)`, never bare URLs.
Get workflow links with `build_dashboard_url` (resourceType `workflow`).

Template (shown in a code block here only so you can see the markdown; do not print the fence):

```markdown
**Quality loop for PR #<N>: ✅ PASSED after <n> attempt(s)**   (or ❌ needs human attention)

- **PR:** [#<N> <title>](<PR url>) · [report comment](<PR comment url>)
- **Workflows:** [ql-demo-smoke](<workflow url>) · [ql-demo-pr-<N>](<workflow url>)

**Attempt 1** · `<short SHA>` · smoke ✅ · acceptance ❌ <one-line reason>
- [smoke run](<execution url>) · [acceptance run](<execution url>)
- fix: <classification>, <one-line root cause> → reviewer APPROVE, commit `<short SHA>`

**Attempt 2** · `<short SHA>` · smoke ✅ · acceptance ✅
- [smoke run](<execution url>) · [acceptance run](<execution url>)

Merge decision stays with a human.
```
