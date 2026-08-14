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
source "$REPO_DIR/scripts/lib-config.sh"
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

# ── HARD DISABLE (2026-08-13) ────────────────────────────────────────────────
# Actual restores are DISABLED until the following are fixed and re-reviewed:
#   1. Caddy /etc/caddy + /var/lib/caddy path collision in backup+restore
#   2. File ownership preservation (--no-owner/--no-group removed on both sides)
#   3. k3s restore path (local kubectl check, stale $jump, missing sudo,
#      missing sudo rsync, suppressed failures, no replica recovery)
# Remove this guard ONLY after those fixes are committed and a --dry-run of a
# real restore has been reviewed.
if [ "$DRY_RUN" = "false" ]; then
  echo "RESTORE DISABLED: actual restores are blocked pending backup fixes (2026-08-13)." >&2
  echo "Use --dry-run to preview. Remove the HARD DISABLE guard in restore-app-data.sh only after fixes." >&2
  exit 1
fi

SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8)
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

if ! mountpoint -q "$NAS_ROOT"; then
  log "ERROR: NAS not mounted at $NAS_ROOT. Aborting."
  exit 1
fi

# Path -> slug, MUST match backup-app-data.sh (dir_slug).
# /etc/caddy -> etc_caddy ; /var/lib/caddy -> var_lib_caddy
dir_slug() { echo "$1" | sed -e 's#^/##' -e 's#/#_#g'; }

# Manifest: label|target|jump|type|source-dirs(space sep) — from config/hosts.yaml.
GUESTS=()
while read -r blabel ip btype bjump sources; do
  [ -n "$blabel" ] || continue
  [ -n "$ip" ] || continue
  GUESTS+=("$blabel|root@$ip|$bjump|$btype|$sources")
done < <(cfg_guests_backup)

# k3s nodes come from hosts.yaml guests with role=k3s.
K3S_NODES=()
while read -r g; do
  [ -n "$g" ] || continue
  local_role="$(echo "$g" | awk '{print $6}')"
  local_name="$(echo "$g" | awk '{print $3}')"
  local_ip="$(echo "$g" | awk '{print $4}')"
  [ "$local_role" = "k3s" ] || continue
  K3S_NODES+=("$local_name|npburney@$local_ip")
done < <(cfg_guests)

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

# apply_owners: feed a .owners manifest captured by backup-app-data.sh into a
# remote loop that chowns each path (restore runs as root on the guest, so the
# original uid/gid recorded at backup time are applied correctly).
# Manifest format: uid|gid|type|relpath (find -printf '%U|%G|%y|%P')
# Optional 5th arg "sudo" prefixes chown (k3s nodes: npburney needs sudo).
apply_owners() { # target jump destdir backupdir [sudo]
  local target="$1" jump="$2" destdir="$3" backupdir="$4" sudo_prefix=""
  [ "${5:-}" = "sudo" ] && sudo_prefix="sudo"
  local mf="$backupdir/.owners"
  [ -f "$mf" ] || { log "  no .owners manifest at $mf (legacy backup?)"; return 0; }
  if ! ssh_run "$target" "$jump" \
    "cd '$destdir' && while IFS='|' read -r u g t p; do [ -z \"\$p\" ] && p='.'; $sudo_prefix chown -h \"\$u:\$g\" \"\$p\" 2>/dev/null; done" \
    < "$mf" 2>>"$LOG_FILE"; then
    log "  WARN: ownership apply failed for $destdir"
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
    bdir="$(dir_slug "$src")"
    [ -d "$base/$bdir" ] || { log "  SKIP: $base/$bdir not present"; continue; }
    log "  restoring -> $src"
    $DRY_RUN || rsync_to "$target" "$jump" "$base/$bdir" "$src" 2>>"$LOG_FILE" \
      || log "  WARN: restore failed for $src"
    $DRY_RUN || apply_owners "$target" "$jump" "$src" "$base/$bdir"
  done
  if [ "$type" = "docker" ] && ! $DRY_RUN && [ -d "$base/volumes" ]; then
    log "  restoring named volumes"
    for vdir in "$base"/volumes/*/; do
      [ -d "$vdir" ] || continue
      v="$(basename "$vdir")"
      ssh_run "$target" "$jump" "mkdir -p /var/lib/docker/volumes/$v/_data" || true
      rsync_to "$target" "$jump" "$vdir" "/var/lib/docker/volumes/$v/_data" 2>>"$LOG_FILE" \
        || log "  WARN: volume restore failed for $v"
      apply_owners "$target" "$jump" "/var/lib/docker/volumes/$v/_data" "$vdir"
    done
  fi
done

# ── k3s PVCs ──────────────────────────────────────────────────────────────────
# App workloads live in the `default` and `tools` namespaces only (verified
# 2026-08-13). kubectl runs REMOTELY on the node with sudo (the ops runner does
# not have kubectl). No stale jump: k3s nodes are reached directly. Original
# replica counts are recorded, workloads scaled to 0, PVCs restored via
# --rsync-path="sudo rsync", then replicas restored. Any failure exits non-zero
# (no suppressed failures / false success).

for entry in "${K3S_NODES[@]}"; do
  IFS='|' read -r label target <<< "$entry"
  if [ -n "$ONLY" ] && [ "$label" != "$ONLY" ]; then continue; fi
  src="$BACKUP_ROOT/k8s/$label"
  [ -d "$src" ] || { log "== $label: no backup, skipping =="; continue; }
  log "== k3s PVCs: $label ($target) =="
  if $DRY_RUN; then
    log "  would scale down default+tools (recording replicas), restore PVCs via sudo rsync, scale back up"
    continue
  fi

  # Remote kubectl must work (sudo), or we fail the k3s section, not just warn.
  if ! ssh "${SSH_OPTS[@]}" "$target" "sudo -n kubectl version --client >/dev/null 2>&1"; then
    log "ERROR: sudo kubectl unavailable on $target. Aborting."
    exit 1
  fi

  # Record original replica counts for default+tools.
  repl_file="$(mktemp)"
  for ns in default tools; do
    if ! ssh "${SSH_OPTS[@]}" "$target" \
        "sudo kubectl -n $ns get deploy,sts -o jsonpath='{range .items[*]}{.metadata.namespace}{\" \"}{.kind}{\" \"}{.metadata.name}{\" \"}{.spec.replicas}{\"\\n\"}{end}' 2>/dev/null" \
        >> "$repl_file"; then
      log "ERROR: could not read replica counts in $ns on $label. Aborting."
      rm -f "$repl_file"
      exit 1
    fi
    # Scale down. Fail hard: a PVC restore into a running workload is unsafe.
    if ! ssh "${SSH_OPTS[@]}" "$target" \
        "sudo kubectl -n $ns scale deploy,sts --all --replicas=0 2>/dev/null"; then
      log "ERROR: could not scale down $ns on $label. Aborting (workloads may be partially scaled)."
      rm -f "$repl_file"
      exit 1
    fi
  done

  # Restore PVC storage. Must use sudo rsync: npburney cannot write
  # /var/lib/rancher/k3s/storage directly (backup side uses --rsync-path="sudo rsync").
  if ! rsync -aHAX --no-owner --no-group --delete --rsync-path="sudo rsync" \
      -e "ssh ${SSH_OPTS[*]}" "$src/" "$target:/var/lib/rancher/k3s/storage/" 2>>"$LOG_FILE"; then
    log "ERROR: PVC restore failed for $label."
    rm -f "$repl_file"
    exit 1
  fi
  apply_owners "$target" "-" "/var/lib/rancher/k3s/storage" "$src" sudo \
    || { log "ERROR: ownership apply failed for k3s $label."; rm -f "$repl_file"; exit 1; }

  # Restore original replica counts (fail hard if we cannot bring services back).
  while read -r ns kind name replicas; do
    [ -z "$ns" ] && continue
    kind="$(echo "$kind" | tr '[:upper:]' '[:lower:]')"
    if ! ssh "${SSH_OPTS[@]}" "$target" \
        "sudo kubectl -n $ns scale $kind $name --replicas=$replicas 2>/dev/null"; then
      log "ERROR: could not scale $ns/$name back to $replicas on $label."
      rm -f "$repl_file"
      exit 1
    fi
    log "  scaled $ns/$name -> $replicas"
  done < "$repl_file"
  rm -f "$repl_file"
done

log "Restore complete. Verify each service before considering it done."
exit 0
