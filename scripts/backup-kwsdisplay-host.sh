#!/usr/bin/env bash
set -euo pipefail

# Backs up the kwsdisplay host (monitoring stack + uptime-kuma) to the Synology.
# Runs on burndev, which mounts /mnt/syn; pulls from kwsdisplay over SSH.

DEST="/mnt/syn/backups/hosts/kwsdisplay"
LOG="/home/npburney/.local/state/homelab/backup-kwsdisplay-host.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "Starting kwsdisplay host backup"

if ! mountpoint -q /mnt/syn; then
  log "ERROR: /mnt/syn is not mounted. Backup aborted."
  exit 1
fi

mkdir -p "$DEST"

log "Pulling /opt/docker/monitoring"
rsync -a --no-owner --no-group -e ssh \
  --exclude="*/data/grafana/grafana.db" \
  kwsdisplay:/opt/docker/monitoring/ "$DEST/monitoring/"

log "Pulling /opt/docker/uptime-kuma"
rsync -a --no-owner --no-group -e ssh \
  --exclude="*/data/" \
  kwsdisplay:/opt/docker/uptime-kuma/ "$DEST/uptime-kuma/"

log "kwsdisplay host backup complete"
