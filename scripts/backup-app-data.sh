#!/usr/bin/env bash
set -euo pipefail

# Host-aware app-data backup for the current homelab (Proxmox LXCs + 3-node k3s).
# Runs on the ops runner LXC 115 (operations), which has the NAS mount and the
# dedicated backup-runner SSH key (~/.ssh/id_ed25519_backup).
#
# Layout written under $BACKUP_ROOT:
#   docker/<label>/<src-slug>/   compose project dirs (bind-mounted data + configs)
#   docker/<label>/volumes/<name>/   named docker volumes (_data)
#   native/<label>/<src-slug>/   native (non-docker) service data dirs
#   postgres/<label>/  pg_dumpall SQL dumps (crash-consistent, belt & suspenders)
#   k8s/<node>/        local-path PVC storage per k3s node
# Each data dir also carries a .owners manifest (uid|gid|type|relpath) captured
# at backup time, because the unprivileged runner (uid 100000 on the NAS) cannot
# chown on the NFS mount. Restore applies it on the guest side where it runs as
# root. Source dirs are named by path slug (/etc/caddy -> etc_caddy) so distinct
# paths can never collide (the old basename scheme merged /etc/caddy and
# /var/lib/caddy into one "caddy" dir and the second rsync --delete wiped the
# first -- fixed 2026-08-13).
#
# Docker guests not backed by a postgres dump are stopped (docker compose stop)
# before their data is copied and started afterwards, so SQLite / file-backed
# apps get a consistent snapshot. k3s PVCs are copied with workloads scaled to 0.
#
# Usage: bash scripts/backup-app-data.sh [--dry-run]

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/scripts/lib-paths.sh"
source "$REPO_DIR/scripts/lib-config.sh"
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

# Path -> slug used for destination dir names in BOTH scripts.
# /etc/caddy -> etc_caddy ; /var/lib/caddy -> var_lib_caddy
dir_slug() { echo "$1" | sed -e 's#^/##' -e 's#/#_#g'; }

# ── Manifest (source of truth: config/hosts.yaml) ─────────────────────────────
# GUESTS entries: label|target|jump|type|source-dirs(space sep)
# type: docker = compose project dirs + named volumes; native = data dirs only
# jump: "-" or "root@192.168.1.40" (caddy LXC 101 bridges to the 10.30.0.0/24 media VLAN)
GUESTS=()
while read -r blabel ip btype bjump sources; do
  [ -n "$blabel" ] || continue
  [ -n "$ip" ] || continue
  GUESTS+=("$blabel|root@$ip|$bjump|$btype|$sources")
done < <(cfg_guests_backup)

# postgres dumps: label|target|container (discovered per guest below)
PG_TARGETS=()
while read -r blabel ip; do
  [ -n "$blabel" ] || continue
  PG_TARGETS+=("$blabel|root@$ip")
done < <(cfg_pg_targets)

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

# capture_owners: record uid|gid|type|relpath for every entry under srcdir.
# The runner cannot chown on the NAS, so this manifest is the ownership record;
# restore-app-data.sh applies it on the guest (as root).
capture_owners() { # target jump srcdir destdir
  local target="$1" jump="$2" srcdir="$3" destdir="$4"
  if ! ssh_run "$target" "$jump" "cd '$srcdir' && find . -printf '%U|%G|%y|%P\\n'" > "$destdir/.owners" 2>>"$LOG_FILE"; then
    warn "ownership manifest failed for $srcdir"
  fi
}

# remote_compose_file target jump srcdir -> compose file basename, or empty.
# The check MUST run on the guest: $srcdir is a path on the remote host and
# does not exist on the backup runner (fixed 2026-08-13; previously this ran
# locally so quiescing silently never happened).
remote_compose_file() { # target jump srcdir
  local target="$1" jump="$2" srcdir="$3"
  local name
  if ssh_run "$target" "$jump" "test -f '$srcdir/compose.yaml'" 2>/dev/null; then
    name="compose.yaml"
  elif ssh_run "$target" "$jump" "test -f '$srcdir/docker-compose.yml'" 2>/dev/null; then
    name="docker-compose.yml"
  else
    return 1
  fi
  echo "$srcdir/$name"
}

# Guests that get a postgres dump keep running (dump is the consistent artifact).
# Everyone else is stopped before copying so SQLite/file data is consistent.
pg_label() { # label -> 0 if in PG_TARGETS, 1 otherwise
  local label="$1" e
  for e in "${PG_TARGETS[@]}"; do
    [ "${e%%|*}" = "$label" ] && return 0
  done
  return 1
}

# ── Docker / native guests ────────────────────────────────────────────────────

for entry in "${GUESTS[@]}"; do
  IFS='|' read -r label target jump type sources <<< "$entry"
  base="$BACKUP_ROOT/$type/$label"
  log "== $label ($target) =="
  stop_again=()   # compose files to restart after copying
  if [ "$type" = "docker" ] && ! pg_label "$label" && ! $DRY_RUN; then
    for src in $sources; do
      cf="$(remote_compose_file "$target" "$jump" "$src")" \
        || { warn "no compose file on guest at $src; cannot quiesce"; continue; }
      log "  stopping $src for consistent snapshot"
      if ! ssh_run "$target" "$jump" "docker compose -f '$cf' stop" 2>>"$LOG_FILE"; then
        warn "stop failed for $src; snapshot may be inconsistent"
      fi
      stop_again+=("$cf")
    done
  fi
  for src in $sources; do
    dest="$base/$(dir_slug "$src")"
    mkdir -p "$dest"
    log "  rsync $src -> $dest"
    if ! $DRY_RUN; then
      if ! rsync_from "$target" "$jump" "$src" "$dest" 2>>"$LOG_FILE"; then
        warn "rsync failed for $src (host down or path missing?)"
      fi
      capture_owners "$target" "$jump" "$src" "$dest"
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
      capture_owners "$target" "$jump" "/var/lib/docker/volumes/$v/_data" "$vdest"
    done
  fi
  if [ "${#stop_again[@]}" -gt 0 ]; then
    for cf in "${stop_again[@]}"; do
      if $DRY_RUN; then
        log "  (dry) starting $cf"
        continue
      fi
      log "  starting $cf"
      if ! ssh_run "$target" "$jump" "docker compose -f '$cf' start" 2>>"$LOG_FILE"; then
        warn "START FAILED for $cf - manual intervention required"
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
# App workloads live in the `default` and `tools` namespaces (verified 2026-08-13;
# kube-system coredns/local-path-provisioner/metrics-server and kube-state-metrics
# are infrastructure and must NOT be scaled). Workloads are scaled to 0 before
# the rsync so SQLite/PVC data is consistent, then scaled back up.

for entry in "${K3S_NODES[@]}"; do
  IFS='|' read -r label target <<< "$entry"
  dest="$BACKUP_ROOT/k8s/$label"
  mkdir -p "$dest"
  log "== k3s PVCs: $label ($target) =="
  if $DRY_RUN; then
    continue
  fi
  # Record original replicas for default+tools, then scale those to 0.
  repl_file="$(mktemp)"
  for ns in default tools; do
    if ! ssh "${SSH_OPTS[@]}" "$target" \
        "sudo kubectl -n $ns get deploy,sts -o jsonpath='{range .items[*]}{.metadata.namespace}{\" \"}{.kind}{\" \"}{.metadata.name}{\" \"}{.spec.replicas}{\"\\n\"}{end}' 2>/dev/null" \
        >> "$repl_file"; then
      warn "could not read replica counts in $ns from $label; skipping PVC backup"
      rm -f "$repl_file"
      continue 2
    fi
    ssh "${SSH_OPTS[@]}" "$target" \
      "sudo kubectl -n $ns scale deploy,sts --all --replicas=0 2>/dev/null" \
      || warn "could not scale down $ns on $label; PVC backup may be inconsistent"
  done
  if ! rsync -aHAX --no-owner --no-group --delete --rsync-path="sudo rsync" -e "ssh ${SSH_OPTS[*]}" \
      "$target:/var/lib/rancher/k3s/storage/" "$dest/" 2>>"$LOG_FILE"; then
    warn "k3s rsync failed for $label"
  fi
  # Ownership manifest (sudo runs the WHOLE command: npburney cannot cd into
  # root-owned /var/lib/rancher/k3s/storage itself -- fixed 2026-08-13).
  if ! ssh "${SSH_OPTS[@]}" "$target" \
      "sudo sh -c 'cd /var/lib/rancher/k3s/storage && find . -printf \"%U|%G|%y|%P\\n\"'" > "$dest/.owners" 2>>"$LOG_FILE"; then
    warn "ownership manifest failed for k3s $label"
  fi
  # Restore original replica counts.
  while read -r ns kind name replicas; do
    [ -z "$ns" ] && continue
    kind="$(echo "$kind" | tr '[:upper:]' '[:lower:]')"
    if ! ssh "${SSH_OPTS[@]}" "$target" \
        "sudo kubectl -n $ns scale $kind $name --replicas=$replicas 2>/dev/null"; then
      warn "could not scale $ns/$name back to $replicas on $label"
    fi
  done < "$repl_file"
  rm -f "$repl_file"
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
