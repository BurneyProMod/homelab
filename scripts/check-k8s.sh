#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="${SERVER_IP:-192.168.1.71}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

rollout() {
  local namespace="$1"
  local deployment="$2"
  log "Waiting for $namespace/$deployment rollout..."
  kubectl -n "$namespace" rollout status deploy/"$deployment" --timeout=180s
}

rollout default changedetection
rollout default homarr
rollout default homebox
rollout default manyfold
rollout tools code-server
rollout tools kanboard
rollout tools omni-tools
rollout tools trilium

log "Checking for non-running pods..."
FAILING=$(kubectl get pods -A --field-selector=status.phase!=Running --no-headers 2>/dev/null || true)
if [[ -n "$FAILING" ]]; then
  echo ""
  echo "Non-running pods:"
  echo "$FAILING"
else
  log "All pods are Running."
fi

echo ""
echo "============================================"
echo "  Services (k3s NodePorts)"
echo "============================================"
echo ""
echo "  Trilium:        http://${SERVER_IP}:30081"
echo "  Code-server:    http://${SERVER_IP}:30082"
echo "  Kanboard:       http://${SERVER_IP}:30083"
echo "  Omni Tools:     http://${SERVER_IP}:30084"
echo "  Homarr:         http://${SERVER_IP}:30085"
echo "  Homebox:        http://${SERVER_IP}:30086"
echo "  Manyfold:       http://${SERVER_IP}:30087"
echo "  Changedetection: http://${SERVER_IP}:30088"
echo ""
