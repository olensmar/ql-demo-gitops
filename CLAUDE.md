# ql-demo-gitops

GitOps repo for the AI quality-loop demo. Argo CD on minikube deploys `apps/podinfo`:
`ql-demo-prod` tracks `main` (auto-sync), `ql-demo-preview` tracks the `preview` branch (synced by the agent).
Tests are Testkube TestWorkflows in `tests/` and run on runner `default-runner-agent` inside the cluster.

- The app is defined in `apps/podinfo/base/`: `config.env` for app settings (podinfo reads `PODINFO_*` env vars), `deployment.yaml` / `service.yaml` for ports and runtime.
- Never modify `apps/podinfo/overlays/prod`, never push to `main`, never merge PRs.
- The loop is `/quality-loop <pr>`; roles are in `.claude/agents/`.
