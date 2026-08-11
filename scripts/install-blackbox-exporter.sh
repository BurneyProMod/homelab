#!/usr/bin/env bash
set -euo pipefail

# Installs prometheus-blackbox-exporter in the monitoring namespace.
# Config is loaded from kubernetes/monitoring/blackbox-values.yml
# Endpoint targets are defined in kubernetes/monitoring/prometheus-additional-scrape.yml

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required but not found in PATH" >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH" >&2
  exit 1
fi

kubectl get namespace monitoring >/dev/null 2>&1 || \
  kubectl create namespace monitoring

helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install blackbox-exporter \
  prometheus-community/prometheus-blackbox-exporter \
  --version 11.10.0 \
  --namespace monitoring \
  --values "$REPO_DIR/kubernetes/monitoring/blackbox-values.yml" \
  --set fullnameOverride=blackbox-exporter \
  --set serviceMonitor.enabled=true \
  --set serviceMonitor.defaults.labels.release=kube-prometheus-stack \
  --atomic --wait

echo "blackbox-exporter installed. Targets are scraped by Prometheus via prometheus-additional-scrape.yml."
