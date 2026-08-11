#!/usr/bin/env bash
set -euo pipefail

# Restores app data from /mnt/syn/backups/homelab/.
# Defaults to --dry-run (reports what would happen, makes no changes).

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="/mnt/syn/backups/homelab"
LOG_FILE="$REPO_DIR/scripts/restore-app-data.log"
DRY_RUN=true

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

for arg in "$@"; do
  case "$arg" in
    --force) DRY_RUN=false ;;
    --dry-run) DRY_RUN=true ;;
    --help|-h)
      echo "Usage: $0 [--dry-run|--force]"
      echo "  --dry-run   Show what would be restored (default)"
      echo "  --force     Actually perform the restore"
      exit 0
      ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

if $DRY_RUN; then
  log "DRY RUN -- no changes will be made"
fi

if ! mountpoint -q /mnt/syn; then
  log "ERROR: /mnt/syn is not mounted."
  exit 1
fi

# Guard: kubectl must point at the homelab k3s cluster.
source "$REPO_DIR/scripts/lib-context.sh"
require_k3s_context

# Namespaces with PVC-backed workloads. NOTE: monitoring no longer exists on
# the live cluster; default (homarr, homebox, manyfold, changedetection) and
# tools (code-server, kanboard, omni-tools, trilium) must both be scaled down
# before PVC data is overwritten.
K8S_NAMESPACES="default tools"

# ── Pre-flight checks ────────────────────────────────────────────────────────

log "Checking backup availability"

check_dir() {
  if [ -d "$1" ]; then
    log "  FOUND: $1 ($(du -sh "$1" 2>/dev/null | cut -f1))"
    return 0
  else
    log "  MISSING: $1"
    return 1
  fi
}

check_dir "$BACKUP_ROOT/docker-volumes"
check_dir "$BACKUP_ROOT/postgres-dumps"
check_dir "$BACKUP_ROOT/caddy"
check_dir "$BACKUP_ROOT/k8s-pvcs"

echo ""
echo "WARNING: Restore will OVERWRITE live data with backup snapshots."
echo "Stop the affected services first."
echo ""

if $DRY_RUN; then
  log "Dry run complete. Run with --force to restore."
  exit 0
fi

# ── Confirmation ──────────────────────────────────────────────────────────────

read -rp "Type 'yes' to confirm full restore: " confirm
if [ "$confirm" != "yes" ]; then
  log "Restore cancelled by user."
  exit 0
fi

# ── Restore Docker volumes ───────────────────────────────────────────────────

log "Restoring Docker volumes"
for src in "$BACKUP_ROOT/docker-volumes/opt/docker/"*; do
  [ -d "$src" ] || continue
  name="$(basename "$src")"
  dest="/opt/docker/$name"
  log "  Restoring: $dest"
  mkdir -p "$dest"
  rsync -aHAX --no-owner --no-group --info=progress2 "$src/" "$dest/"
done

# ── Restore Caddy certs and data ─────────────────────────────────────────────

log "Restoring Caddy certs and data"
if [ -d "$BACKUP_ROOT/caddy/certs" ]; then
  mkdir -p /opt/docker/caddy/certs
  rsync -aHAX --no-owner --no-group --info=progress2 \
    "$BACKUP_ROOT/caddy/certs/" /opt/docker/caddy/certs/
fi
if [ -d "$BACKUP_ROOT/caddy/data" ]; then
  mkdir -p /opt/docker/caddy/data
  rsync -aHAX --no-owner --no-group --info=progress2 \
    "$BACKUP_ROOT/caddy/data/" /opt/docker/caddy/data/
fi

# ── Restore Postgres databases ───────────────────────────────────────────────

log "Restoring Postgres databases"
log "  Postgres restores require manual steps:"
log "  1. Ensure the target container is running"
log "  2. Drop and recreate the database if needed"
log "  3. Run: docker exec -i <container> psql -U <user> -d <db> < dump.sql"
log "  Dumps are in: $BACKUP_ROOT/postgres-dumps/"

# ── Restore K8s PVCs ─────────────────────────────────────────────────────────

log "Restoring K8s PVCs"
if [ -d "$BACKUP_ROOT/k8s-pvcs" ]; then
  log "  Scaling down K8s workloads (deployments AND statefulsets) in: $K8S_NAMESPACES"
  declare -A ORIG_REPLICAS
  for ns in $K8S_NAMESPACES; do
    for kind in deploy statefulset; do
      for name in $(kubectl -n "$ns" get "$kind" -o name 2>/dev/null | cut -d/ -f2); do
        rep=$(kubectl -n "$ns" get "$kind" "$name" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
        ORIG_REPLICAS["${ns}/${kind}/${name}"]=$rep
        log "    recording ${ns}/${kind}/${name} replicas=$rep"
      done
    done
    kubectl -n "$ns" scale deployment --all --replicas=0 2>/dev/null || true
    kubectl -n "$ns" scale statefulset --all --replicas=0 2>/dev/null || true
  done
  log "  Waiting for pods to terminate..."
  for ns in $K8S_NAMESPACES; do
    kubectl -n "$ns" wait --for=delete pod --all --timeout=120s 2>/dev/null || true
  done
  log "  Copying PVC data..."
  mkdir -p /var/lib/rancher/k3s/storage
  rsync -aHAX --no-owner --no-group --info=progress2 \
    "$BACKUP_ROOT/k8s-pvcs/" /var/lib/rancher/k3s/storage/
  log "  Scaling workloads back up (deployments AND statefulsets)..."
  for ns in $K8S_NAMESPACES; do
    for kind in deploy statefulset; do
      for name in $(kubectl -n "$ns" get "$kind" -o name 2>/dev/null | cut -d/ -f2); do
        rep="${ORIG_REPLICAS[${ns}/${kind}/${name}]:-1}"
        log "    restoring ${ns}/${kind}/${name} replicas=$rep"
        kubectl -n "$ns" scale "$kind" "$name" --replicas="$rep" 2>/dev/null || true
      done
    done
  done
fi

log "Restore complete. Verify each service before considering it done."
