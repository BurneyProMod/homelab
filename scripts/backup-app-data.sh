#!/usr/bin/env bash
set -euo pipefail

# Host-aware app-data backup for the current homelab (Proxmox LXCs + 3-node k3s).
# Runs on the ops runner LXC 115 (operations), which has the NAS mount and the
# dedicated backup-runner SSH key (~/.ssh/id_ed25519_backup).
#
# Layout written under $BACKUP_ROOT:
#   docker/<label>/    compose project dirs (bind-mounted data + configs)
#   docker/<label>/volumes/<name>/   named docker volumes (_data)
#   native/<label>/    native (non-docker) service data dirs
#   postgres/<label>/  pg_dumpall SQL dumps (crash-consistent, belt & suspenders)
#   k8s/<node>/        local-path PVC storage per k3s node
#
# Usage: bash scripts/backup-app-data.sh [--dry-run]

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/scripts/lib-paths.sh"
LOG_FILE="/var/log/backup-app-data.log"
DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8)
RSYNC_SSH="ssh ${SSH_OPTS[*]}"

FAILURES=0
warn() { log "  WARN: $*"; FAILURES=$((FAILURES + 1)); }

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

if ! mountpoint -q "$NAS_ROOT"; then
  log "ERROR: NAS not mounted at $NAS_ROOT. Aborting."
  exit 1
fi

# ── Manifest ──────────────────────────────────────────────────────────────────
# label|target|jump|type|source-dirs(space sep)
# type: docker = compose project dirs + named volumes; native = data dirs only
# jump: "-" or "root@192.168.1.40" (caddy LXC 101 bridges to the 10.30.0.0/24 media VLAN)
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

# postgres dumps: label|target|container (discovered per guest below)
PG_TARGETS=(
  "immich|root@192.168.1.61"
  "paperless|root@192.168.1.67"
  "authentik|root@192.168.1.66"
)

K3S_NODES=(
  "k3s-core|npburney@192.168.1.70"
  "k3s-exu|npburney@192.168.1.71"
  "k3s-gpu|npburney@192.168.1.72"
)

ssh_run() { # target [jump] command...
  local target="$1" jump="$2"; shift 2
  if [ "$jump" != "-" ]; then
    ssh "${SSH_OPTS[@]}" -J "$jump" "$target" "$@"
  else
    ssh "${SSH_OPTS[@]}" "$target" "$@"
  fi
}

rsync_from() { # target jump src dest
  local target="$1" jump="$2" src="$3" dest="$4"
  if [ "$jump" != "-" ]; then
    rsync -aHAX --no-owner --no-group --delete -e "ssh ${SSH_OPTS[*]} -J $jump" "$target:$src/" "$dest/"
  else
    rsync -aHAX --no-owner --no-group --delete -e "ssh ${SSH_OPTS[*]}" "$target:$src/" "$dest/"
  fi
}

# ── Docker / native guests ────────────────────────────────────────────────────

for entry in "${GUESTS[@]}"; do
  IFS='|' read -r label target jump type sources <<< "$entry"
  base="$BACKUP_ROOT/$type/$label"
  log "== $label ($target) =="
  for src in $sources; do
    dest="$base/$(basename "$src")"
    mkdir -p "$dest"
    log "  rsync $src -> $dest"
    if ! $DRY_RUN; then
      if ! rsync_from "$target" "$jump" "$src" "$dest" 2>>"$LOG_FILE"; then
        warn "rsync failed for $src (host down or path missing?)"
      fi
    fi
  done
  if [ "$type" = "docker" ] && ! $DRY_RUN; then
    vols=$(ssh_run "$target" "$jump" "docker volume ls -q 2>/dev/null | grep -vE '^[0-9a-f]{64}$'" 2>/dev/null || true)
    for v in $vols; do
      vdest="$base/volumes/$v"
      mkdir -p "$vdest"
      log "  volume $v"
      if ! rsync_from "$target" "$jump" "/var/lib/docker/volumes/$v/_data" "$vdest" 2>>"$LOG_FILE"; then
        warn "volume rsync failed for $v"
      fi
    done
  fi
done

# ── Postgres dumps ────────────────────────────────────────────────────────────

for entry in "${PG_TARGETS[@]}"; do
  IFS='|' read -r label target <<< "$entry"
  jump="-"   # all pg guests are on the LAN (no jump needed)
  log "== $label: postgres dump =="
  if $DRY_RUN; then
    continue
  fi
  container=$(ssh_run "$target" "$jump" "docker ps --format {{.Names}} 2>/dev/null | grep -iE 'postgres|pgsql|db' | head -1" 2>/dev/null || true)
  if [ -z "$container" ]; then
    warn "no postgres container found, skipping dump"
    continue
  fi
  dest="$BACKUP_ROOT/postgres/$label"
  mkdir -p "$dest"
  out="$dest/all_$(date '+%Y%m%d-%H%M%S').sql"
  log "  pg_dumpall from $container"
  if ssh_run "$target" "$jump" "docker exec $container pg_dumpall -U postgres 2>/dev/null" > "$out" && [ -s "$out" ]; then
    log "  OK: $out ($(du -h "$out" | cut -f1))"
    ls -1t "$dest"/all_*.sql 2>/dev/null | tail -n +8 | xargs -r rm -f   # keep last 7
  else
    # Fallback: dump the app-named database with the app-named user.
    rm -f "$out"
    if ssh_run "$target" "$jump" "docker exec $container pg_dump -U $label -d $label 2>/dev/null" > "$out" && [ -s "$out" ]; then
      log "  OK (fallback user): $out ($(du -h "$out" | cut -f1))"
    else
      warn "pg_dumpall/pg_dump failed for $label (raw volume copy still covers this)"
      rm -f "$out"
    fi
  fi
done

# ── k3s PVC storage ───────────────────────────────────────────────────────────

for entry in "${K3S_NODES[@]}"; do
  IFS='|' read -r label target <<< "$entry"
  dest="$BACKUP_ROOT/k8s/$label"
  mkdir -p "$dest"
  log "== k3s PVCs: $label ($target) =="
  if ! $DRY_RUN; then
    if ! rsync -aHAX --no-owner --no-group --delete --rsync-path="sudo rsync" -e "ssh ${SSH_OPTS[*]}" \
        "$target:/var/lib/rancher/k3s/storage/" "$dest/" 2>>"$LOG_FILE"; then
      warn "k3s rsync failed for $label"
    fi
  fi
done

if $DRY_RUN; then
  log "Dry run complete (nothing written)"
  exit 0
fi

SIZE="$(du -sh "$BACKUP_ROOT" 2>/dev/null | cut -f1)"
if [ "$FAILURES" -gt 0 ]; then
  log "App-data backup FINISHED WITH $FAILURES FAILURES ($SIZE on disk)"
  exit 1
fi
log "App-data backup complete ($SIZE on disk)"
