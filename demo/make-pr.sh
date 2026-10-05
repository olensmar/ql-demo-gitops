#!/usr/bin/env bash
# Opens the demo PR: expose podinfo's Prometheus metrics on a dedicated port, with a seeded
# Service targetPort typo (9779 instead of 9797). Argo CD will be green and the probes pass;
# only a behavioural test that scrapes the promised port catches it (and Prometheus shows the
# podinfo target as down).
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

# The platform Prometheus (kube-prometheus-stack release `kps`) picks up ServiceMonitors labelled release=kps.
cat > apps/podinfo/base/servicemonitor.yaml <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: podinfo
  labels:
    release: kps
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: podinfo
  endpoints:
    - port: metrics
      path: /metrics
      interval: 15s
EOF

cat > apps/podinfo/base/kustomization.yaml <<'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
labels:
  - pairs:
      app.kubernetes.io/name: podinfo
      app.kubernetes.io/part-of: ql-demo
    includeSelectors: true
resources:
  - deployment.yaml
  - service.yaml
  - servicemonitor.yaml
# Edit config.env to change app behaviour. The generated ConfigMap name gets a
# content hash, so any change rolls the Deployment automatically.
configMapGenerator:
  - name: podinfo-config
    envs:
      - config.env
EOF

git add apps/podinfo/base/
git commit -m "Expose Prometheus metrics on dedicated port 9797"
git push -u --force origin "$BRANCH"

gh pr create --base main --head "$BRANCH" \
  --title "Expose Prometheus metrics on dedicated port 9797" \
  --body "$(cat <<'EOF'
Our Prometheus scrapes every workload on a dedicated `metrics` port, kept separate from app traffic.
This exposes the podinfo metrics there and adds a ServiceMonitor so the platform Prometheus picks it up.

**Intended behaviour**
- `http://podinfo.<namespace>.svc.cluster.local:9797/metrics` serves Prometheus metrics (HTTP 200)
- App traffic is unchanged on port 9898

Manifests only (Deployment, Service, ServiceMonitor), no code.
EOF
)"
