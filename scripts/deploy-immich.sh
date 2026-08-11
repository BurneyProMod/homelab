#!/usr/bin/env bash
#
# deploy-immich.sh — deploy the Immich compose stack from this repo to
# pve-exu LXC 111 (hostname: immich, IP 192.168.1.61).
#
# Prerequisites (verified 2026-08-04):
#   - LXC 111 exists with Docker installed and /mnt/immich mounted
#     (mp0 bind of host NFS export 192.168.1.11:/volume1/immich).
#   - Caddy route `http://immich.pve.lan` is enabled on pve-exu LXC 116
#     at /home/npburney/caddy/Caddyfile (multi-line block, then
#     `docker restart caddy-caddy-1`).
#
# Usage:
#   scripts/deploy-immich.sh            # sync + deploy, skip DB restore
#   scripts/deploy-immich.sh --restore  # also restore newest nightly DB dump
#
# The script is idempotent. It does not delete data.

set -euo pipefail

PVE_HOST="root@192.168.1.31"
LXC_ID="111"
LXC_DIR="/home/npburney/immich"
STACK_DIR="$(cd "$(dirname "$0")/.." && pwd)/docker/immich"
RESTORE=0
if [[ "${1:-}" == "--restore" ]]; then
  RESTORE=1
fi

echo "==> [1/6] Sync stack files from repo to LXC ${LXC_ID}"
ssh "$PVE_HOST" "pct exec ${LXC_ID} -- mkdir -p ${LXC_DIR}"
tar -C "$STACK_DIR" -czf - --exclude='data/postgres' . \
  | ssh "$PVE_HOST" "pct exec ${LXC_ID} -- tar -xzf - -C ${LXC_DIR}"
echo "    synced ${LXC_DIR}"

echo "==> [2/6] Create external model-cache volume if missing"
ssh "$PVE_HOST" "pct exec ${LXC_ID} -- docker volume create immich_model-cache"

echo "==> [3/6] Seed model cache (no-op if already populated)"
ssh "$PVE_HOST" "pct exec ${LXC_ID} -- bash -c '
  VOL=/var/lib/docker/volumes/immich_model-cache/_data
  if [ -f ${LXC_DIR}/data/model-cache/facial-recognition/buffalo_l/config.json ] && [ ! -f \$VOL/model-cache/facial-recognition/buffalo_l/config.json ]; then
    mkdir -p \$VOL/model-cache
    cp -a ${LXC_DIR}/data/model-cache/. \$VOL/model-cache/
    echo \"    seeded model cache\"
  else
    echo \"    model cache already present, skipping\"
  fi
'"

echo "==> [4/6] Verify NFS write access at /mnt/immich"
ssh "$PVE_HOST" "pct exec ${LXC_ID} -- bash -c '
  echo deploy-check > /mnt/immich/.deploy-write-test && rm /mnt/immich/.deploy-write-test
'"
echo "    NFS writable"

echo "==> [5/6] Start database + redis, wait for postgres healthy"
ssh "$PVE_HOST" "pct exec ${LXC_ID} -- bash -c '
  cd ${LXC_DIR}
  docker compose up -d database redis
  for i in \$(seq 1 60); do
    if docker compose ps database --format json 2>/dev/null | grep -q healthy; then
      echo \"    postgres healthy after \${i}x2s\"; break
    fi
    sleep 2
  done
'"

if [[ "$RESTORE" == "1" ]]; then
  echo "==> [6/7] Restore newest nightly DB dump from /mnt/immich/backups"
  ssh "$PVE_HOST" "pct exec ${LXC_ID} -- bash -c '
    cd ${LXC_DIR}
    DUMP=\$(ls -1t /mnt/immich/backups/immich-db-backup-*.sql.gz 2>/dev/null | head -1)
    if [ -z \"\$DUMP\" ]; then
      echo \"    no nightly dump found; skipping restore\"; exit 0
    fi
    echo \"    restoring \$DUMP\"
    zcat \"\$DUMP\" | docker compose exec -T database psql -U postgres -d immich > /tmp/immich-restore.log 2>&1
    grep -icE \"error|fatal\" /tmp/immich-restore.log || true
  '"
else
  echo "==> [6/7] DB restore skipped (pass --restore to restore nightly dump)"
fi

echo "==> [7/7] Start full stack"
ssh "$PVE_HOST" "pct exec ${LXC_ID} -- bash -c '
  cd ${LXC_DIR}
  docker compose up -d
  for i in \$(seq 1 90); do
    if docker compose ps immich-server --format json 2>/dev/null | grep -q healthy; then
      echo \"    immich-server healthy\"; break
    fi
    sleep 10
  done
  docker compose ps
'"

echo "Done. Verify: curl http://immich.pve.lan/api/server/ping"
