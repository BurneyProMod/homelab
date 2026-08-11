#!/usr/bin/env bash
set -euo pipefail

# Backs up Docker volume data, Postgres databases, Caddy certs, and K8s PVCs
# to /mnt/syn/backups/homelab/. Requires /mnt/syn to be mounted.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_ROOT="/mnt/syn/backups/homelab"
LOG_FILE="$REPO_DIR/scripts/backup-app-data.log"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "Starting app-data backup"

if ! mountpoint -q /mnt/syn; then
  log "ERROR: /mnt/syn is not mounted. Backup aborted."
  exit 1
fi

# ── Docker volume directories ────────────────────────────────────────────────

DOCKER_VOLUMES=(
  "/opt/docker/immich"
  "/opt/docker/jellyfin/data"
  "/opt/docker/servarr"
  "/opt/docker/vikunja/files"
  "/opt/docker/vikunja/db"
  "/opt/docker/cannery/cannery/data"
  "/opt/docker/scanopy/data"
  "/opt/docker/actual-budget/data"
  "/opt/docker/rackpeek/data"
)

log "Backing up Docker volumes"
for src in "${DOCKER_VOLUMES[@]}"; do
  if [ -d "$src" ]; then
    dest="$BACKUP_ROOT/docker-volumes${src}"
    mkdir -p "$(dirname "$dest")"
    rsync -aHAX --no-owner --no-group --delete --info=progress2 "$src/" "$dest/"
    log "  OK: $src"
  else
    log "  SKIP: $src (not found)"
  fi
done

# ── Postgres databases ───────────────────────────────────────────────────────

PG_BACKUP_DIR="$BACKUP_ROOT/postgres-dumps"
mkdir -p "$PG_BACKUP_DIR"

# Helper: pg_dump via docker exec if container is running
dump_pg() {
  local container="$1" db="$2" user="${3:-postgres}"
  if docker inspect "$container" --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    local outfile="$PG_BACKUP_DIR/${db}_${TIMESTAMP}.sql"
    docker exec "$container" pg_dump -U "$user" -d "$db" > "$outfile"
    if [[ -s "$outfile" ]] && ! grep -q 'pg_dump: error' "$outfile"; then
      log "  OK: $db (from $container)"
    else
      log "  FAIL: $db dump is empty or contains errors"
      rm -f "$outfile"
    fi
  else
    log "  SKIP: $container not running, cannot dump $db"
  fi
}

log "Dumping Postgres databases"
dump_pg "immich_postgres"      "immich"   "postgres"
dump_pg "vikunja-db-1"         "vikunja"  "vikunja"
dump_pg "cannery-db"           "cannery"  "postgres"
dump_pg "scanopy-postgres-1"   "scanopy"  "postgres"

# Rotate old dumps: keep last 7 per database
for db in immich vikunja cannery scanopy; do
  ls -1t "$PG_BACKUP_DIR/${db}_"*.sql 2>/dev/null | tail -n +8 | xargs -r rm -f
done

# ── Caddy certs and data ─────────────────────────────────────────────────────

CADDY_SRC="/opt/docker/caddy"
CADDY_DEST="$BACKUP_ROOT/caddy"
if [ -d "$CADDY_SRC" ]; then
  log "Backing up Caddy certs and data"
  mkdir -p "$CADDY_DEST"
  rsync -aHAX --no-owner --no-group --delete --info=progress2 \
    "$CADDY_SRC/certs/" "$CADDY_DEST/certs/"
  rsync -aHAX --no-owner --no-group --delete --info=progress2 \
    "$CADDY_SRC/data/" "$CADDY_DEST/data/"
  log "  OK: Caddy"
else
  log "  SKIP: /opt/docker/caddy not found"
fi

# ── K8s PVCs ─────────────────────────────────────────────────────────────────
# PVC data for stateful apps lives on the node's filesystem.
# For local-path StorageClass, PVCs are in /var/lib/rancher/k3s/storage/

PVC_SRC="/var/lib/rancher/k3s/storage"
PVC_DEST="$BACKUP_ROOT/k8s-pvcs"

if [ -d "$PVC_SRC" ]; then
  log "Backing up K8s PVCs (local-path)"
  mkdir -p "$PVC_DEST"
  rsync -aHAX --no-owner --no-group --delete --info=progress2 \
    "$PVC_SRC/" "$PVC_DEST/"
  log "  OK: K8s PVCs"
else
  log "  SKIP: $PVC_SRC not found"
fi

# ── Summary ───────────────────────────────────────────────────────────────────

BACKUP_SIZE="$(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1)"
log "App-data backup complete ($BACKUP_SIZE on disk)"
