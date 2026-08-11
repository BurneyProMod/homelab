#!/usr/bin/env bash
set -euo pipefail

# Config-only backup of the burndev host to the Synology.
# Covers: crontabs, /opt/docker compose configs, selected /etc files,
# ~/.ssh, ~/.config/opencode, and scripts under ~/dev.
# Requires /mnt/syn to be mounted.

DEST="/mnt/syn/backups/hosts/burndev"
LOG="/home/npburney/.local/state/homelab/backup-burndev-host.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

log "Starting burndev host config backup"

if ! mountpoint -q /mnt/syn; then
  log "ERROR: /mnt/syn is not mounted. Backup aborted."
  exit 1
fi

mkdir -p "$DEST"

# ── Crontabs ────────────────────────────────────────────────────────────────
log "Backing up crontabs"
mkdir -p "$DEST/crontabs"
crontab -l > "$DEST/crontabs/npburney.cron" 2>/dev/null || true
rsync -a --no-owner --no-group /etc/crontab /etc/cron.d/ "$DEST/crontabs/system/" 2>/dev/null || true

# ── /opt/docker compose configs (exclude live data) ─────────────────────────
log "Backing up /opt/docker configs"
mkdir -p "$DEST/opt-docker"
rsync -a --no-owner --no-group \
  --exclude="*/data/" --exclude="*/db/" --exclude="*/pgdata/" \
  --exclude="*/meili_data/" --exclude="*/config/cache/" \
  /opt/docker/ "$DEST/opt-docker/" 2>/dev/null || true

# ── Selected /etc files ─────────────────────────────────────────────────────
log "Backing up selected /etc files"
mkdir -p "$DEST/etc"
for f in fstab hosts hostname hosts.allow hosts.deny nsswitch.conf resolv.conf; do
  [ -f "/etc/$f" ] && cp "/etc/$f" "$DEST/etc/" 2>/dev/null || true
done
rsync -a --no-owner --no-group /etc/ssh/sshd_config* "$DEST/etc/ssh/" 2>/dev/null || true

# ── ~/.ssh ──────────────────────────────────────────────────────────────────
log "Backing up ~/.ssh"
mkdir -p "$DEST/ssh"
rsync -a --no-owner --no-group ~/.ssh/ "$DEST/ssh/" 2>/dev/null || true

# ── ~/.config/opencode ──────────────────────────────────────────────────────
log "Backing up ~/.config/opencode"
mkdir -p "$DEST/opencode"
rsync -a --no-owner --no-group \
  --exclude="node_modules/" --exclude="agent-backup-*/" --exclude="backup-*/" \
  ~/.config/opencode/ "$DEST/opencode/" 2>/dev/null || true

# ── ~/dev scripts (config-ish) ──────────────────────────────────────────────
log "Backing up ~/dev scripts"
mkdir -p "$DEST/dev-scripts"
rsync -a --no-owner --no-group ~/dev/scripts/ "$DEST/dev-scripts/" 2>/dev/null || true
rsync -a --no-owner --no-group ~/dev/dotfiles/ "$DEST/dev-dotfiles/" 2>/dev/null || true

log "burndev host config backup complete"
