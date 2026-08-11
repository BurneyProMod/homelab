#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/scripts/lib-context.sh"
require_k3s_context
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run)
      DRY_RUN=true
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--dry-run]" >&2
      exit 1
      ;;
  esac
done

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not found in PATH" >&2
  exit 1
fi

KUBECTL_APPLY=(kubectl apply)
if [[ "$DRY_RUN" == "true" ]]; then
  KUBECTL_APPLY+=(--dry-run=client)
fi

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

rollout() {
  local namespace="$1"
  local deployment="$2"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "Would wait for $namespace/$deployment rollout"
    return
  fi
  log "Waiting for $namespace/$deployment rollout..."
  kubectl -n "$namespace" rollout status deploy/"$deployment" --timeout=180s
}

apply_file() {
  local file="$1"
  log "Applying $file"
  "${KUBECTL_APPLY[@]}" -f "$file"
}

log "Applying namespaces"
"${KUBECTL_APPLY[@]}" -f "$REPO_DIR/kubernetes/namespaces/"

log "Applying network policies recursively"
"${KUBECTL_APPLY[@]}" -f "$REPO_DIR/kubernetes/policies/" -R

log "Applying application manifests (excluding *.example.yml)"
while IFS= read -r manifest; do
  apply_file "$manifest"
done < <(find "$REPO_DIR/kubernetes/apps" -maxdepth 1 -type f -name "*.yml" ! -name "*.example.yml" | sort)


if [[ "$DRY_RUN" != "true" ]]; then
  log "Rollout checks"
  rollout tools trilium
  rollout tools code-server
  rollout tools kanboard
  rollout tools omni-tools
  rollout default changedetection
  rollout default homarr
  rollout default homebox
  rollout default manyfold

  FAILING=$(kubectl get pods -A --field-selector=status.phase!=Running --no-headers 2>/dev/null || true)
  if [[ -n "$FAILING" ]]; then
    echo ""
    echo "Non-running pods:"
    echo "$FAILING"
  else
    log "All pods are Running."
  fi
fi

log "Done"
if [[ "$DRY_RUN" == "true" ]]; then
  log "Dry run completed successfully"
fi
