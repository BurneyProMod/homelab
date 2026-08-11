#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="/mnt/syn/repo"
LOG_FILE="/home/npburney/.local/state/homelab/backup.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "Starting homelab backup"

if ! mountpoint -q /mnt/syn; then
  log "ERROR: /mnt/syn is not mounted. Backup aborted."
  exit 1
fi

mkdir -p "$BACKUP_DIR"

rsync -aHAX --no-owner --no-group --delete --exclude="/docker/*/data/" --exclude="/docker/*/*/data/" --exclude="/docker/*/db/" --exclude="/docker/*/pgdata/" --exclude="/docker/*/meili_data/" --exclude="/docker/servarr/*/config/" --info=progress2 \
  "$REPO_DIR/" "$BACKUP_DIR/"

log "Backup complete"