#!/usr/bin/env bash
set -euo pipefail

# Off-site repo backup: push the authoritative homelab working tree on openbench
# to the GitHub remote.
#
# openbench is the authoritative dev machine (~/dev/homelab). GitHub is the
# version-controlled remote (no secrets). The Synology copy is a separate
# complete mirror (incl. secrets) via scripts/sync-synology.sh — never run git
# on it.
#
# Runs from openbench weekly cron (Sun 03:00) and `make backup`.
# Warn-don't-fail: a push error must never block the app-data backup that
# `make backup` runs next.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${LOG_FILE:-/home/npburney/.local/state/homelab/backup.log}"
mkdir -p "$(dirname "$LOG_FILE")"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "Starting homelab repo backup (off-site push)"

if ! GIT_TERMINAL_PROMPT=0 git -C "$REPO_DIR" push origin main 2>>"$LOG_FILE"; then
  log "WARN: push to origin failed (repo still safe on openbench)"
else
  log "Repo backup complete (pushed to origin)"
fi
