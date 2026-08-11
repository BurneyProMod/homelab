#!/usr/bin/env bash
set -euo pipefail

# Backs up Grafana (SQLite db + provisioning config) from kwsdisplay to the Synology.
# Runs on burndev; pulls over SSH.

DEST="/mnt/syn/backups/services/grafana"
LOG="/home/npburney/.local/state/homelab/backup-grafana.log"
VOL="/home/npburney/.local/share/docker/volumes/monitoring_grafana-data/_data"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "Starting grafana backup"

if ! mountpoint -q /mnt/syn; then
  log "ERROR: /mnt/syn is not mounted. Backup aborted."
  exit 1
fi

mkdir -p "$DEST"

log "Pulling grafana.db"
rsync -a --no-owner --no-group -e ssh kwsdisplay:$VOL/grafana.db "$DEST/grafana.db"

log "Pulling provisioning"
rsync -a --no-owner --no-group -e ssh kwsdisplay:/opt/docker/monitoring/grafana/provisioning/ "$DEST/provisioning/"

log "grafana backup complete"
