#!/usr/bin/env bash
set -euo pipefail

# Installs kube-prometheus-stack (Prometheus + Alertmanager) in the monitoring namespace.
# Grafana is disabled in values — we deploy our own via kubernetes/monitoring/grafana.yml.
#
# Prerequisites: cert-manager, namespaces, NFS provisioner (for PVCs)

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALUES_FILE="$REPO_DIR/kubernetes/monitoring/kube-prometheus-stack-values.yml"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required but not found in PATH" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH" >&2
  exit 1
fi

# Ensure monitoring namespace exists
kubectl get namespace monitoring >/dev/null 2>&1 || \
  kubectl create namespace monitoring

# Create the additional scrape config Secret from prometheus-additional-scrape.yml
kubectl -n monitoring create secret generic prometheus-additional-scrape \
  --from-file=scrape.yml="$REPO_DIR/kubernetes/monitoring/prometheus-additional-scrape.yml" \
  --dry-run=client -o yaml | kubectl apply -f -

helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --version 85.0.2 \
  --namespace monitoring \
  --values "$VALUES_FILE" \
  --atomic --wait

echo "kube-prometheus-stack installed."
echo "Prometheus:   http://prometheus.homelab.lan (via Caddy NodePort)"
echo "Alertmanager: http://alertmanager.homelab.lan (via Caddy NodePort)"
