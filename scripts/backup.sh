#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/scripts/lib-paths.sh"
LOG_FILE="${LOG_FILE:-/home/npburney/.local/state/homelab/backup.log}"
mkdir -p "$(dirname "$LOG_FILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "Starting homelab repo backup"

if ! mountpoint -q "$NAS_ROOT"; then
  log "ERROR: NAS not mounted at $NAS_ROOT. Backup aborted."
  exit 1
fi

# The canonical repo already lives on the NAS (REPO_MIRROR == REPO_DIR when run
# from the NAS mount). In that case there is nothing to mirror; the off-site
# copy is the GitHub remote. Only mirror when the working copy is elsewhere.
if [[ "$(readlink -f "$REPO_DIR")" == "$(readlink -f "$REPO_MIRROR")" ]]; then
  log "Repo is canonical on the NAS ($REPO_MIRROR); off-site copy is GitHub. Nothing to mirror."
  log "Repo backup complete (skipped self-mirror)"
  exit 0
fi

mkdir -p "$REPO_MIRROR"

rsync -aHAX --no-owner --no-group --delete --exclude="/docker/*/data/" --exclude="/docker/*/*/data/" --exclude="/docker/*/db/" --exclude="/docker/*/pgdata/" --exclude="/docker/*/meili_data/" --info=progress2 \
  "$REPO_DIR/" "$REPO_MIRROR/"

log "Backup complete"
