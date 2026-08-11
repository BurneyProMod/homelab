#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="/mnt/syn/backups/homelab"
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
  echo "ERROR: Backup directory not found: $BACKUP_DIR" >&2
  exit 1
fi

RSYNC_ARGS=(-aHAX --delete --exclude '.git/' --info=progress2)
if [[ "$MODE" == "dry-run" ]]; then
  RSYNC_ARGS+=(--dry-run)
fi

echo "Sync mode: $MODE"
echo "Source: $BACKUP_DIR/"
echo "Target: $REPO_DIR/"

rsync "${RSYNC_ARGS[@]}" "$BACKUP_DIR/" "$REPO_DIR/"

echo "Sync complete"
if [[ "$MODE" == "dry-run" ]]; then
  echo "Re-run with --apply to pull from NAS backup"
fi
