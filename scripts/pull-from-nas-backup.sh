#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Repo mirror written by scripts/backup.sh (rsync of $REPO_DIR -> /mnt/syn/repo).
# WARNING: do NOT point this at /mnt/syn/backups/homelab. That path is the
# APP-DATA backup root (scripts/backup-app-data.sh: postgres dumps + PVC dirs).
# Restoring it over the repo with --delete would replace the repository with
# application data.
BACKUP_DIR="/mnt/syn/repo"
MODE="dry-run"

for arg in "$@"; do
  case "$arg" in
    --apply)
      MODE="apply"
      ;;
    --dry-run)
      MODE="dry-run"
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--dry-run|--apply]" >&2
      exit 1
      ;;
  esac
done

if ! mountpoint -q /mnt/syn; then
  echo "ERROR: /mnt/syn is not mounted." >&2
  exit 1
fi

if [[ ! -d "$BACKUP_DIR" ]]; then
  echo "ERROR: Repo backup directory not found: $BACKUP_DIR (run scripts/backup.sh first)" >&2
  exit 1
fi

# Safety guard 1: refuse to --delete over the repo unless the source is a git
# checkout. This prevents restoring app data or arbitrary files into the repo.
if [[ ! -f "$BACKUP_DIR/.git/HEAD" ]]; then
  echo "ERROR: $BACKUP_DIR is not a git repository (.git/HEAD missing)." >&2
  echo "Refusing to rsync --delete over the repo. Aborting." >&2
  exit 1
fi

# Safety guard 2: refuse if source and target are the same directory.
if [[ "$(readlink -f "$BACKUP_DIR")" == "$(readlink -f "$REPO_DIR")" ]]; then
  echo "ERROR: Source and target are the same directory ($BACKUP_DIR). Aborting." >&2
  exit 1
fi

RSYNC_ARGS=(-aHAX --delete --info=progress2)
if [[ "$MODE" == "dry-run" ]]; then
  RSYNC_ARGS+=(--dry-run)
fi

echo "Sync mode: $MODE"
echo "Source: $BACKUP_DIR/"
echo "Target: $REPO_DIR/"

rsync "${RSYNC_ARGS[@]}" "$BACKUP_DIR/" "$REPO_DIR/"

echo "Sync complete"
