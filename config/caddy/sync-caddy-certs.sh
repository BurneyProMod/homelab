#!/bin/bash
# Sync step-ca certs from the HA master (caddy-core, 192.168.1.42) so the
# standby serves identical certificates. Only the VIP holder (master) can
# complete ACME tls-alpn-01 validation, so the master owns renewal and the
# backup mirrors its cert store. Run every few minutes via caddy-cert-sync.timer.
set -euo pipefail

KEY=/root/.ssh/id_ed25519_root_caddy-gpu
SRC=root@192.168.1.42:/var/lib/caddy/.local/share/caddy/certificates/
DST=/var/lib/caddy/.local/share/caddy/certificates/

exec 9>/run/lock/caddy-cert-sync
flock -n 9 || exit 0

changed=$(rsync -az --delete -e "ssh -i $KEY" --out-format="%n" "$SRC" "$DST" || true)

if [ -n "$changed" ]; then
    caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile 2>/dev/null || true
fi
