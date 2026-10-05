#!/usr/bin/env bash
# Opens the demo PR: expose podinfo's Prometheus metrics on a dedicated port, with a seeded
# Service targetPort typo (9779 instead of 9797). Argo CD will be green and the probes pass;
# only a behavioural test that scrapes the promised port catches it.
set -euo pipefail
BRANCH="${BRANCH:-feat/expose-metrics-port}"
cd "$(dirname "$0")/.."

git fetch origin main
git checkout -B "$BRANCH" origin/main

cat > apps/podinfo/base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: podinfo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: podinfo
  template:
    metadata:
      labels:
        app: podinfo
    spec:
      containers:
        - name: podinfo
          image: ghcr.io/stefanprodan/podinfo:6.7.1
          command: ["./podinfo", "--port=9898", "--port-metrics=9797", "--level=info"]
          ports:
            - name: http
              containerPort: 9898
            - name: metrics
              containerPort: 9797
          envFrom:
            - configMapRef:
                name: podinfo-config
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
            periodSeconds: 3
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              memory: 128Mi
EOF

cat > apps/podinfo/base/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: podinfo
spec:
  selector:
    app: podinfo
  ports:
    - name: http
      port: 9898
      targetPort: http
    - name: metrics
      port: 9797
      targetPort: 9779
EOF

git add apps/podinfo/base/deployment.yaml apps/podinfo/base/service.yaml
git commit -m "Expose Prometheus metrics on dedicated port 9797"
git push -u --force origin "$BRANCH"

gh pr create --base main --head "$BRANCH" \
  --title "Expose Prometheus metrics on dedicated port 9797" \
  --body "$(cat <<'EOF'
Our Prometheus scrapes every workload on a dedicated `metrics` port, kept separate from app traffic.
This exposes the podinfo metrics there.

**Intended behaviour**
- `http://podinfo.<namespace>.svc.cluster.local:9797/metrics` serves Prometheus metrics (HTTP 200)
- App traffic is unchanged on port 9898

Manifests only (Deployment + Service), no code.
EOF
)"
