#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_DIR/secrets/homelab.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing secrets/homelab.env" >&2
  echo "Copy secrets/homelab.env.example to secrets/homelab.env and fill in real values." >&2
  exit 1
fi

# Safely read env file without sourcing (avoids arbitrary code execution)
# Supports KEY=value and KEY="value" lines; skips comments and blank lines
get_env() {
  local key="$1"
  local val
  val=$(grep -E "^${key}=" "$ENV_FILE" | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
  echo "$val"
}

# Validate required variables exist and are non-empty
for var in CODE_SERVER_PASSWORD CODE_SERVER_SUDO_PASSWORD; do
  val=$(get_env "$var")
  if [[ -z "$val" ]]; then
    echo "ERROR: $var is empty or missing in $ENV_FILE" >&2
    exit 1
  fi
done

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

for ns in default tools; do
  kubectl get namespace "$ns" >/dev/null 2>&1 || kubectl create namespace "$ns"
done

log "Creating tools/code-server-secret"
kubectl -n tools create secret generic code-server-secret \
  --from-literal=PASSWORD="$(get_env CODE_SERVER_PASSWORD)" \
  --from-literal=SUDO_PASSWORD="$(get_env CODE_SERVER_SUDO_PASSWORD)" \
  --dry-run=client -o yaml | kubectl apply -f -


log "Secrets created."
