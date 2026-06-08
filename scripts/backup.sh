#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="/mnt/syn/backups/homelab"
LOG_FILE="$REPO_DIR/scripts/backup.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "Starting homelab backup"

if ! mountpoint -q /mnt/syn; then
  log "ERROR: /mnt/syn is not mounted. Backup aborted."
  exit 1
fi

mkdir -p "$BACKUP_DIR"

rsync -aHAX --no-owner --no-group --delete --info=progress2 \
  "$REPO_DIR/" "$BACKUP_DIR/"

log "Backup complete"