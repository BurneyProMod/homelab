#!/usr/bin/env bash
set -euo pipefail

# Host-aware app-data RESTORE for the current homelab. MANUAL OPERATION ONLY.
# Never scheduled/cron'd. Requires an interactive 'yes' confirmation and is
# default-dry-run. It writes data back to the LIVE guests, so:
#   1. Stop the affected services first (docker compose down on the guest,
#      scale k8s workloads to 0 -- see the k8s section which does this).
#   2. Run with --force and confirm.
#
# Usage: bash scripts/restore-app-data.sh [--dry-run|--force] [--only LABEL]

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/scripts/lib-paths.sh"
LOG_FILE="/var/log/restore-app-data.log"
DRY_RUN=true
ONLY=""

for arg in "$@"; do
  case "$arg" in
    --force) DRY_RUN=false ;;
    --dry-run) DRY_RUN=true ;;
    --only=*) ONLY="${arg#--only=}" ;;
    --help|-h)
      echo "Usage: $0 [--dry-run|--force] [--only LABEL]"
      echo "  --only LABEL   restore a single guest (e.g. immich)"
      exit 0 ;;
    *) echo "Unknown flag: $arg"; exit 1 ;;
  esac
done

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8)
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

if ! mountpoint -q "$NAS_ROOT"; then
  log "ERROR: NAS not mounted at $NAS_ROOT. Aborting."
  exit 1
fi

# Same manifest as backup-app-data.sh (keep in sync).
GUESTS=(
  "caddy-core|root@192.168.1.42|-|native|/etc/caddy /var/lib/caddy"
  "identity|root@192.168.1.60|-|docker|/home/npburney/docker/lldap /home/npburney/docker/openbao"
  "files|root@192.168.1.64|-|docker|/opt/filebrowser"
  "authentik|root@192.168.1.66|-|docker|/opt/authentik"
  "immich|root@192.168.1.61|-|docker|/home/npburney/immich"
  "apps|root@192.168.1.62|-|docker|/home/npburney/docker/vikunja /home/npburney/docker/rackpeek /home/npburney/docker/actual-budget /home/npburney/docker/tasks-md"
  "archives|root@192.168.1.63|-|docker|/home/npburney/docker/karakeep"
  "paperless|root@192.168.1.67|-|docker|/home/npburney/docker/paperless"
  "stash|root@192.168.1.68|-|docker|/home/npburney/docker/stash"
  "scrutiny|root@192.168.1.69|-|docker|/home/npburney/docker/scrutiny"
  "jellyfin|root@192.168.1.187|-|native|/var/lib/jellyfin"
  "caddy-gpu|root@192.168.1.40|-|native|/etc/caddy /var/lib/caddy"
  "sonarr|root@10.30.0.11|root@192.168.1.40|native|/var/lib/sonarr"
  "radarr|root@10.30.0.12|root@192.168.1.40|native|/var/lib/radarr"
  "lidarr|root@10.30.0.13|root@192.168.1.40|native|/var/lib/lidarr"
  "prowlarr|root@10.30.0.14|root@192.168.1.40|native|/var/lib/prowlarr"
  "qbit|root@10.30.0.15|root@192.168.1.40|docker|/opt/qbit-vpn"
)

K3S_NODES=(
  "k3s-core|npburney@192.168.1.70"
  "k3s-exu|npburney@192.168.1.71"
  "k3s-gpu|npburney@192.168.1.72"
)

ssh_run() {
  local target="$1" jump="$2"; shift 2
  if [ "$jump" != "-" ]; then
    ssh "${SSH_OPTS[@]}" -J "$jump" "$target" "$@"
  else
    ssh "${SSH_OPTS[@]}" "$target" "$@"
  fi
}

rsync_to() { # target jump src dest
  local target="$1" jump="$2" src="$3" dest="$4"
  if [ "$jump" != "-" ]; then
    rsync -aHAX --no-owner --no-group -e "ssh ${SSH_OPTS[*]} -J $jump" "$src/" "$target:$dest/"
  else
    rsync -aHAX --no-owner --no-group -e "ssh ${SSH_OPTS[*]}" "$src/" "$target:$dest/"
  fi
}

log "DRY RUN: $DRY_RUN  (only=$ONLY)"

if ! $DRY_RUN; then
  echo ""
  echo "WARNING: This OVERWRITES live service data with backup snapshots."
  echo "Stop the affected services FIRST (docker compose down on the guest;"
  echo "k8s workloads are scaled down by this script)."
  read -rp "Type 'yes' to continue: " confirm
  if [ "$confirm" != "yes" ]; then
    log "Restore cancelled by user."
    exit 0
  fi
fi

# ── Docker / native guests ────────────────────────────────────────────────────

for entry in "${GUESTS[@]}"; do
  IFS='|' read -r label target jump type sources <<< "$entry"
  if [ -n "$ONLY" ] && [ "$label" != "$ONLY" ]; then continue; fi
  base="$BACKUP_ROOT/$type/$label"
  if [ ! -d "$base" ]; then
    log "== $label: no backup at $base, skipping =="
    continue
  fi
  log "== $label ($target) =="
  for src in $sources; do
    bdir="$(basename "$src")"
    [ -d "$base/$bdir" ] || { log "  SKIP: $base/$bdir not present"; continue; }
    log "  restoring -> $src"
    $DRY_RUN || rsync_to "$target" "$jump" "$base/$bdir" "$src" 2>>"$LOG_FILE" \
      || log "  WARN: restore failed for $src"
  done
  if [ "$type" = "docker" ] && ! $DRY_RUN && [ -d "$base/volumes" ]; then
    log "  restoring named volumes"
    for vdir in "$base"/volumes/*/; do
      [ -d "$vdir" ] || continue
      v="$(basename "$vdir")"
      ssh_run "$target" "$jump" "mkdir -p /var/lib/docker/volumes/$v/_data" || true
      rsync_to "$target" "$jump" "$vdir" "/var/lib/docker/volumes/$v/_data" 2>>"$LOG_FILE" \
        || log "  WARN: volume restore failed for $v"
    done
  fi
done

# ── k3s PVCs ──────────────────────────────────────────────────────────────────
# Scale down workloads in default + tools (and any statefulsets), restore the
# PVC storage onto the correct node, then scale back up.

for entry in "${K3S_NODES[@]}"; do
  IFS='|' read -r label target <<< "$entry"
  if [ -n "$ONLY" ] && [ "$label" != "$ONLY" ]; then continue; fi
  src="$BACKUP_ROOT/k8s/$label"
  [ -d "$src" ] || { log "== $label: no backup, skipping =="; continue; }
  log "== k3s PVCs: $label ($target) =="
  if ! $DRY_RUN; then
    # Context guard: kubectl must target the homelab k3s cluster.
    if ! command -v kubectl >/dev/null 2>&1; then
      log "ERROR: kubectl not available for k3s PVC restore. Aborting k3s section."
      continue
    fi
    for ns in default tools; do
      ssh_run "$target" "$jump" "kubectl -n $ns scale deployment --all --replicas=0 2>/dev/null || true; kubectl -n $ns scale statefulset --all --replicas=0 2>/dev/null || true" \
        || log "  WARN: could not scale down $ns on $label"
    done
    rsync -aHAX --no-owner --no-group -e "ssh ${SSH_OPTS[*]}" \
      "$src/" "$target:/var/lib/rancher/k3s/storage/" 2>>"$LOG_FILE" \
      || log "  WARN: PVC restore failed for $label"
    log "  NOTE: scale workloads back up manually (kubectl scale deployment --all --replicas=N)"
  else
    log "  would scale down default+tools and rsync PVCs to $target"
  fi
done

log "Restore complete. Verify each service before considering it done."
