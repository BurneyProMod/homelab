#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# lib-config.sh — read config/hosts.yaml for every deploy/backup script.
#
# Requires: python3 with PyYAML (validate.sh already depends on this; if yamllint
# is present, PyYAML is present). Falls back to a plain-grep parser if PyYAML is
# missing so the repo stays usable on a fresh host (rebuild scenario).
#
# Usage (after sourcing):
#   cfg_guests            # "vmid node name ip type enabled role stack" lines
#   cfg_guest_stack VMID  # stack string for a guest ("" if none)
#   cfg_guest_by_name NAME # line for the first guest matching NAME
#   cfg_nodes             # "name ip ssh_user" lines
#   cfg_nas               # "host ip share" + mount paths via cfg_nas_mount HOST
#   cfg_k3s               # "server nodes..." + kubeconfig via cfg_k3s_kubeconfig
#   cfg_backup            # "runner ssh_key runner_uid schedule"
#
# All getters exit 1 (with a message on stderr) if hosts.yaml is missing.
# ─────────────────────────────────────────────────────────────────────────────

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOSTS_YAML="${HOSTS_YAML:-$REPO_DIR/config/hosts.yaml}"

_cfg_die() { echo "lib-config: $*" >&2; return 1; }

_cfg_require_file() {
  [ -f "$HOSTS_YAML" ] || _cfg_die "config/hosts.yaml not found at $HOSTS_YAML (copy from hosts.yaml.example if this is a fresh clone)"
}

# YAML -> bash via python3 (one call per query; repo is small, keep it simple
# and dependency-free).
_cfg_py() {
  _cfg_require_file || return 1
  python3 - "$HOSTS_YAML" "$1" <<'PYEOF'
import sys, os

try:
    import yaml
except ImportError:
    sys.exit(3)  # caller falls back to grep parser

def load():
    with open(sys.argv[1]) as f:
        return yaml.safe_load(f) or {}

query = sys.argv[2]
d = load()

def emit_guests(d):
    for g in d.get("guests", []):
        if not g.get("enabled", True):
            continue
        print(f"{g['vmid']} {g['node']} {g['name']} {g.get('ip','')} {g.get('type','lxc')} {g.get('role','')} {g.get('stack','')}")

def emit_all_guests(d):
    for g in d.get("guests", []):
        print(f"{g['vmid']} {g['node']} {g['name']} {g.get('ip','')} {g.get('type','lxc')} {g.get('enabled',True)} {g.get('role','')} {g.get('stack','')}")

def emit_nodes(d):
    for n in d.get("proxmox_nodes", []):
        print(f"{n['name']} {n['ip']} {n.get('ssh_user','root')}")

def emit_standalone(d):
    for s in d.get("standalone", []):
        print(f"{s['name']} {s.get('ip','')} {s.get('role','')} {s.get('ssh_user','')} {s.get('stacks','')}")

def emit_nas(d):
    n = d.get("nas", {})
    print(f"{n.get('host','synology')} {n.get('ip','')} {n.get('share','')}")

def emit_nas_mount(d):
    n = d.get("nas", {})
    mp = n.get("mount_paths", {})
    # called with second arg = host key
    print(mp.get(sys.argv[3] if len(sys.argv) > 3 else "pve", ""))

def emit_k3s(d):
    k = d.get("k3s", {})
    print(f"{k.get('server','')} {' '.join(k.get('nodes',[]))} {k.get('kubeconfig','/etc/rancher/k3s/k3s.yaml')} {k.get('storage_class','local-path')}")

def emit_backup(d):
    b = d.get("backup", {})
    print(f"{b.get('runner','')} {b.get('ssh_key','')} {b.get('runner_uid','')} {b.get('schedule','')}")

def emit_guests_backup(d):
    # one line per guest with backup fields:
    # blabel ip btype bjump sources
    for g in d.get("guests", []):
        if not g.get("enabled", True):
            continue
        blabel = g.get("blabel", g.get("name", ""))
        if not blabel:
            continue
        print(f"{blabel} {g.get('ip','')} {g.get('btype','')} {g.get('bjump','-')} {g.get('sources','')}")

def emit_pg_targets(d):
    for t in d.get("pg_targets", []):
        print(f"{t['blabel']} {t['ip']}")

funcs = {
    "guests": emit_guests,
    "guests-all": emit_all_guests,
    "guests-backup": emit_guests_backup,
    "pg-targets": emit_pg_targets,
    "nodes": emit_nodes,
    "standalone": emit_standalone,
    "nas": emit_nas,
    "nas-mount": emit_nas_mount,
    "k3s": emit_k3s,
    "backup": emit_backup,
}

if query in funcs:
    funcs[query](d)
else:
    sys.exit(2)
PYEOF
}

# Plain-grep fallback (no PyYAML): extracts list values for the known shapes.
_cfg_grep_fallback() {
  _cfg_require_file || return 1
  local query="$1"
  case "$query" in
    guests)
      grep -E "vmid:|name:|ip:|type:|enabled:|role:|stack:" "$HOSTS_YAML" \
        | tr -d ' {}-' | sed -E 's/:[[:space:]]*/:/g' \
        | awk -F: '{a[$1]=$2} /vmid:/{if (a["enabled"]=="true"||a["enabled"]==""){print a["vmid"],a["node"],a["name"],a["ip"],a["type"],a["role"],a["stack"]}}' \
        | sed 's/^/fallback /'
      ;;
    nodes)
      grep -E "name:|ip:|ssh_user:" "$HOSTS_YAML" | grep -A2 -B2 "pve-" \
        | tr -d ' {}-' | sed -E 's/:[[:space:]]*/:/g' \
        | awk -F: '/pve-/{n=$2} /ip:/{i=$2} /ssh_user:/{print n,i,$2}' | sort -u
      ;;
    *) _cfg_die "no grep fallback for query '$query'" ;;
  esac
}

# ── Public getters ───────────────────────────────────────────────────────────

# cfg_guests: enabled guests, one per line: vmid node name ip type role stack
cfg_guests() {
  local out
  out="$(_cfg_py guests)" || true
  if [ -z "$out" ]; then
    out="$(_cfg_grep_fallback guests 2>/dev/null | sed 's/^fallback //')"
  fi
  [ -n "$out" ] || _cfg_die "no enabled guests in hosts.yaml"
  echo "$out"
}

# cfg_guests_all: all guests incl. disabled (with enabled flag)
cfg_guests_all() { _cfg_py guests-all || _cfg_die "cannot read guests"; }

# cfg_guest_by_name NAME -> line for first match
cfg_guest_by_name() {
  local name="$1" g
  while read -r g; do
    if [ "$(echo "$g" | awk '{print $3}')" = "$name" ]; then
      echo "$g"
      return 0
    fi
  done < <(cfg_guests)
  return 1
}

# cfg_guest_stack VMID -> stack string ("" if none)
cfg_guest_stack() {
  local vmid="$1" g
  while read -r g; do
    [ "$(echo "$g" | awk '{print $1}')" = "$vmid" ] && { echo "$g" | awk '{ $1=$2=$3=$4=$5=$6=""; print }' | sed 's/^ *//'; return 0; }
  done < <(cfg_guests)
  return 1
}

# cfg_nodes: proxmox nodes, one per line: name ip ssh_user
cfg_nodes() { _cfg_py nodes || _cfg_grep_fallback nodes; }

# cfg_nas: "host ip share"
cfg_nas() { _cfg_py nas; }

# cfg_nas_mount HOSTKEY -> mount path (defaults to "pve" key)
cfg_nas_mount() { _cfg_py nas-mount "$1"; }

# cfg_k3s: "server node1 node2 ... kubeconfig storageclass"
cfg_k3s() { _cfg_py k3s; }

# cfg_backup: "runner ssh_key runner_uid schedule"
cfg_backup() { _cfg_py backup; }

# cfg_guests_backup: enabled guests with backup fields, one per line:
#   blabel ip btype bjump sources
cfg_guests_backup() {
  local out
  out="$(_cfg_py guests-backup)" || true
  [ -n "$out" ] || _cfg_die "no backup-enabled guests in hosts.yaml"
  echo "$out"
}

# cfg_pg_targets: postgres dump targets, one per line: blabel ip
cfg_pg_targets() {
  local out
  out="$(_cfg_py pg-targets)" || true
  [ -n "$out" ] || _cfg_die "no pg targets in hosts.yaml"
  echo "$out"
}
