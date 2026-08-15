#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# switch-discovery.sh — homelab network device inventory.
#
# Builds a consolidated "what's on my network" report from three sources:
#
#   1. UniFi controller  — APs + WiFi clients (which AP, MAC, IP, hostname)
#   2. Host LLDP         — physical host-to-host adjacency (via pve-core)
#   3. ARP + DNS         — MAC -> IP -> hostname for every wired device
#
# NOTE ON SCOPE: the switches in this homelab are UNMANAGED. They expose no
# MAC-address table, no SNMP, and do not run LLDP themselves, so a per-port
# "switch port 12 -> jellyfin" map is NOT obtainable. This script delivers the
# closest achievable result: a full device inventory with LLDP adjacency and
# MAC/IP/hostname correlation for every reachable device.
#
# Requires:
#   - UniFi controller reachable at UNIFI_HOST (default unifi.local:11443)
#   - UniFi local-admin credentials in ~/.secrets/unifi as KEY=VALUE lines:
#         username=<local-admin-login>     # e.g. opencode
#         password=<password>
#       (apikey is accepted too; the script tries password first, then apikey)
#   - SSH (key-based) from this host to the LLDP/ARP source host (pve-core).
#
# Usage:
#   bash scripts/switch-discovery.sh            # full inventory report
#   bash scripts/switch-discovery.sh --json     # emit JSON instead of table
#   bash scripts/switch-discovery.sh --ap-only  # UniFi data only, skip LLDP/ARP
#
# Env overrides:
#   UNIFI_HOST, UNIFI_SITE, UNIFI_SECRETS, UNIFI_SSH_HOST
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

UNIFI_HOST="${UNIFI_HOST:-unifi.local:11443}"
UNIFI_SITE="${UNIFI_SITE:-default}"
UNIFI_SECRETS="${UNIFI_SECRETS:-$HOME/.secrets/unifi}"
UNIFI_SSH_HOST="${UNIFI_SSH_HOST:-pve-core}"
MODE=table
AP_ONLY=0

for a in "$@"; do
  case "$a" in
    --json) MODE=json ;;
    --ap-only) AP_ONLY=1 ;;
    --help|-h) grep -A40 '^# ─' "$0" | sed -n '1,60p'; exit 0 ;;
    *) echo "unknown arg: $a" >&2; exit 1 ;;
  esac
done

log() { echo "[$(date '+%H:%M:%S')] $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

# ── UniFi credentials ────────────────────────────────────────────────────────
[ -f "$UNIFI_SECRETS" ] || die "unifi secrets not found at $UNIFI_SECRETS"
set -a; . "$UNIFI_SECRETS"; set +a
# UniFi local-admin login username. The secrets file may use either `username=`
# or `firstname=` (a local admin's login name equals its first name).
UNIFI_USER="${username:-${firstname:-${UNIFI_USERNAME:-}}}"
[ -n "${UNIFI_USER:-}" ] && [ -n "${password:-}" ] || die "secrets file needs username= and password= (got username='${UNIFI_USER:-}')"

COOKIE_JAR="$(mktemp)"; trap 'rm -f "$COOKIE_JAR"' EXIT

# Build a --resolve entry "host:port:IP" for SNI/Host pinning when the controller
# hostname (unifi.local) is not in this host's DNS but is reachable by IP.
UNIFI_HOSTNAME="${UNIFI_HOST%%:*}"
UNIFI_PORT="${UNIFI_HOST#*:}"
UNIFI_IP="${UNIFI_IP:-$(getent hosts "$UNIFI_HOSTNAME" | awk '{print $1; exit}' 2>/dev/null || true)}"
UNIFI_IP="${UNIFI_IP:-192.168.1.125}"  # default: UniFi controller host (kws-rpi-1)
[ -n "$UNIFI_IP" ] || die "cannot resolve UniFi host '$UNIFI_HOSTNAME' (set UNIFI_IP)"
RESOLVE="$UNIFI_HOSTNAME:$UNIFI_PORT:$UNIFI_IP"

unifi_curl() { # unifi_curl <method> <path> [data]
  local method="$1" path="$2" data="${3:-}"
  if [ -n "$data" ]; then
    curl -sk -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X "$method" \
      --resolve "$RESOLVE" -H "Host: $UNIFI_HOSTNAME" \
      -H 'Content-Type: application/json' --data "$data" \
      "https://$UNIFI_HOST$path"
  else
    curl -sk -b "$COOKIE_JAR" -c "$COOKIE_JAR" -X "$method" \
      --resolve "$RESOLVE" -H "Host: $UNIFI_HOSTNAME" \
      "https://$UNIFI_HOST$path"
  fi
}

# ── Login to UniFi ───────────────────────────────────────────────────────────
login() {
  local body code=""
  body="$(unifi_curl POST /api/auth/login \
    "{\"username\":\"$UNIFI_USER\",\"password\":\"$password\",\"rememberMe\":false}")" \
    || die "UniFi login request failed"
  code="$(printf '%s' "$body" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("unique_id",""))' 2>/dev/null || true)"
  if [ -z "$code" ]; then
    log "password rejected; retrying with apikey..."
    body="$(unifi_curl POST /api/auth/login \
      "{\"username\":\"$UNIFI_USER\",\"password\":\"$apikey\",\"rememberMe\":false}")" \
      || die "UniFi login request failed"
    code="$(printf '%s' "$body" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("unique_id",""))' 2>/dev/null || true)"
  fi
  [ -n "$code" ] || die "UniFi authentication failed (check ~/.secrets/unifi)"
  log "authenticated to UniFi controller ($UNIFI_HOST)"
}

fetch_aps() { # prints AP lines: MAC<TAB>name<TAB>model<TAB>state
  unifi_curl GET "/proxy/network/api/s/$UNIFI_SITE/stat/device" \
    | python3 -c 'import sys,json
d=json.load(sys.stdin)["data"]
for x in d:
    if x.get("type")=="uap":
        print(x.get("mac",""),"\t",x.get("name",""),"\t",x.get("model",""),"\t",x.get("state",""))'
}

fetch_wifi() { # prints wifi client lines: MAC<TAB>hostname<TAB>ip<TAB>ap_mac
  unifi_curl GET "/proxy/network/api/s/$UNIFI_SITE/stat/sta" \
    | python3 -c 'import sys,json
d=json.load(sys.stdin)["data"]
for c in d:
    nm=c.get("hostname") or c.get("name") or c.get("oui","")
    print(c.get("mac",""),"\t",nm,"\t",c.get("ip",""),"\t",c.get("ap_mac",""))'
}

# ── Host LLDP + ARP (via SSH) ────────────────────────────────────────────────
fetch_lldp() {
  # Physical + bridged host LLDP neighbors (skip container fwbr/fwpr/veth noise).
  # 2>/dev/null drops the remote login banner; sed strips the banner text.
  ssh -o ConnectTimeout=8 -o BatchMode=yes "$UNIFI_SSH_HOST" \
    'lldpctl 2>/dev/null | awk "/^Interface:/{iface=\$2; sub(/,/,\"\",iface)} /SysName:/{print iface\"\t\"\$2}" 2>/dev/null' \
    2>/dev/null | grep -E '^(nic|vmbr|eth|en)'
}

fetch_arp() {
  # ip neigh columns: <ip> dev <iface> lladdr <mac> ... -> $1=ip, $5=mac
  # Emit raw "ip<TAB>mac" lines; DNS resolution happens locally (avoids nested
  # quoting over SSH). 2>/dev/null drops the remote login banner.
  ssh -o ConnectTimeout=8 -o BatchMode=yes "$UNIFI_SSH_HOST" \
    "ip -4 neigh show | awk '/lladdr/ && /REACHABLE|STALE|DELAY/ {print \$1\"\t\"\$5}' 2>/dev/null" \
    2>/dev/null
}

# ── Report ───────────────────────────────────────────────────────────────────
login

log "fetching UniFi access points..."
APS="$(fetch_aps)"
log "fetching UniFi WiFi clients..."
WIFI="$(fetch_wifi)"

if [ "$AP_ONLY" -eq 1 ]; then
  if [ "$MODE" = json ]; then
    python3 - "$APS" "$WIFI" <<'PYEOF'
import sys, json
aps, wifi = sys.argv[1], sys.argv[2]
def rows(s):
    return [[c.strip() for c in l.split("\t")] for l in s.splitlines() if l.strip()]
print(json.dumps({"access_points":[dict(zip(["mac","name","model","state"],r)) for r in rows(aps)],
                  "wifi_clients":[dict(zip(["mac","hostname","ip","ap_mac"],r)) for r in rows(wifi)]}, indent=2))
PYEOF
  else
    printf '%-20s %-22s %-10s %s\n' "MAC" "NAME" "MODEL" "STATE"
    printf '%-20s %-22s %-10s %s\n' "---" "----" "-----" "-----"
    while IFS=$'\t' read -r mac name model state; do [ -n "$mac" ] && printf '%-20s %-22s %-10s %s\n' "$mac" "$name" "$model" "$state"; done <<<"$APS"
    echo
    echo "== WiFi Clients =="
    printf '%-20s %-22s %-16s %s\n' "MAC" "HOSTNAME" "IP" "AP"
    printf '%-20s %-22s %-16s %s\n' "---" "--------" "--" "--"
    while IFS=$'\t' read -r mac name ip ap; do [ -n "$mac" ] && printf '%-20s %-22s %-16s %s\n' "$mac" "$name" "$ip" "$ap"; done <<<"$WIFI"
  fi
  exit 0
fi

log "fetching host LLDP adjacency ($UNIFI_SSH_HOST)..."
LLDP="$(fetch_lldp)"
log "fetching ARP/DNS correlation ($UNIFI_SSH_HOST)..."
ARP="$(fetch_arp)"

if [ "$MODE" = json ]; then
  python3 - "$APS" "$WIFI" "$LLDP" "$ARP" <<'PYEOF'
import sys, json
def rows(s):
    return [[c.strip() for c in l.split("\t")] for l in s.splitlines() if l.strip()]
aps, wifi, lldp, arp = sys.argv[1:5]
print(json.dumps({
  "access_points":[dict(zip(["mac","name","model","state"],r)) for r in rows(aps)],
  "wifi_clients":[dict(zip(["mac","hostname","ip","ap_mac"],r)) for r in rows(wifi)],
  "lldp_neighbors":[dict(zip(["local_interface","peer"],r)) for r in rows(lldp)],
  "wired_devices":[dict(zip(["ip","mac","hostname"],r)) for r in rows(arp)],
}, indent=2))
PYEOF
  exit 0
fi

echo "=============================="
echo " ACCESS POINTS (UniFi)"
echo "=============================="
printf '%-20s %-22s %-12s %s\n' "MAC" "NAME" "MODEL" "STATE"
printf '%-20s %-22s %-12s %s\n' "---" "----" "-----" "-----"
while IFS=$'\t' read -r mac name model state; do [ -n "$mac" ] && printf '%-20s %-22s %-12s %s\n' "$mac" "$name" "$model" "$state"; done <<<"$APS"

echo
echo "=============================="
echo " WIFI CLIENTS (UniFi)"
echo "=============================="
printf '%-20s %-24s %-16s %s\n' "MAC" "HOSTNAME" "IP" "AP"
printf '%-20s %-24s %-16s %s\n' "---" "--------" "--" "--"
while IFS=$'\t' read -r mac name ip ap; do [ -n "$mac" ] && printf '%-20s %-24s %-16s %s\n' "$mac" "$name" "$ip" "$ap"; done <<<"$WIFI"

echo
echo "=============================="
echo " HOST LLDP ADJACENCY"
echo "=============================="
printf '%-20s %s\n' "LOCAL IFACE" "PEER"
printf '%-20s %s\n' "-----------" "----"
while IFS=$'\t' read -r iface peer; do [ -n "$iface" ] && [ -n "$peer" ] && printf '%-20s %s\n' "$iface" "$peer"; done <<<"$LLDP"

echo
echo "=============================="
echo " WIRED DEVICES (ARP + DNS)"
echo "=============================="
printf '%-16s %-19s %s\n' "IP" "MAC" "HOSTNAME"
printf '%-16s %-19s %s\n' "--" "---" "--------"
while IFS=$'\t' read -r ip mac; do
  [ -n "$ip" ] || continue
  local_host="$(getent hosts "$ip" | awk '{print $2; exit}' 2>/dev/null || true)"
  [ -n "$local_host" ] || local_host="(unknown)"
  printf '%-16s %-19s %s\n' "$ip" "$mac" "$local_host"
done <<<"$ARP"
