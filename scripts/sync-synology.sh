#!/usr/bin/env bash
set -euo pipefail

# Mirror the authoritative homelab working tree on openbench to the Synology
# backup share. ONE-DIRECTIONAL: openbench is always the source.
#
# The Synology copy at /volume1/homelab/repo is a complete backup — it includes
# secrets/.env and .git so the repo can be fully recovered. It is NOT a Git
# working tree: never run git operations on the mirror.
#
# Exclusions are limited to live/runtime data (the same dirs .gitignore treats
# as runtime): docker container data, databases, and caches.
#
# Runs from openbench weekly cron (Sun 03:30) and manually after material
# changes:   bash ~/dev/homelab/scripts/sync-synology.sh

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${DEST:-synology:/volume1/homelab/repo}"
LOG_FILE="${LOG_FILE:-$HOME/.local/state/homelab/sync-synology.log}"
mkdir -p "$(dirname "$LOG_FILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "Starting homelab -> Synology mirror (source: $REPO_DIR)"
if ! rsync -a --delete \
  --exclude='/docker/servarr/*/config/' \
  --exclude='/docker/*/data/' \
  --exclude='/docker/*/db/' \
  --exclude='__pycache__/' \
  "$REPO_DIR/" "$DEST/" 2>>"$LOG_FILE"; then
  log "ERROR: mirror failed"
  exit 1
fi
log "Mirror complete"
