#!/usr/bin/env bash
set -euo pipefail

# Pulls the newest Home Assistant backup snapshot to the Synology and keeps last 14.
# Runs on burndev; pulls over SSH from homeassistant (core-ssh addon).

DEST="/mnt/syn/backups/services/home-assistant/data"
LOG="/home/npburney/.local/state/homelab/backup-home-assistant.log"
KEEP=14

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "Starting home-assistant backup"

if ! mountpoint -q /mnt/syn; then
  log "ERROR: /mnt/syn is not mounted. Backup aborted."
  exit 1
fi

mkdir -p "$DEST"

NEWEST=$(ssh homeassistant "ls -t /backup/*.tar | head -1" 2>/dev/null)
if [ -z "$NEWEST" ]; then
  log "ERROR: no backups found on homeassistant"
  exit 1
fi

BASENAME=$(basename "$NEWEST")
if [ -f "$DEST/$BASENAME" ]; then
  log "SKIP: $BASENAME already backed up"
else
  log "Pulling $BASENAME"
  scp -p homeassistant:$NEWEST "$DEST/"
  log "  pulled $(du -h "$DEST/$BASENAME" | cut -f1)"
fi

# Rotate: keep last $KEEP on the Synology
mapfile -t OLD < <(ls -t "$DEST"/*.tar 2>/dev/null | tail -n +$((KEEP+1)))
for f in "${OLD[@]:-}"; do
  log "  prune $f"
  rm -f "$f"
done

log "home-assistant backup complete"
