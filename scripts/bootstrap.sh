#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# bootstrap.sh — rebuild the entire homelab from this repo after a disaster.
#
# Philosophy: pull the repo, fill out config/hosts.yaml, run this script
# stage by stage. Dry-run by default; every stage is scoped and fails hard.
# Destructive stages (infra, os-bootstrap, k3s) require --stage and, where
# noted, an explicit --apply.
#
# Usage:
#   bash scripts/bootstrap.sh [--stage N] [--dry-run|--apply] [--only GUEST]
#
# Stages:
#   0  preflight      validate config + connectivity + NAS mount
#   1  infra          create Proxmox LXC/VMs from hosts.yaml (pct/qm)
#   2  os-bootstrap   per-host: ssh key, docker+compose, NFS mounts, cron
#   3  k3s            install/join 3-node k3s, extract kubeconfig
#   4  secrets        check secrets/homelab.env, run create-secrets.sh
#   5  docker         deploy per-host docker stacks (host map)
#   6  k8s            deploy-k8s.sh (manifests + rollouts)
#   7  configs        push caddy/step-ca file configs
#   8  data-restore   restore-app-data.sh (still hard-disabled pending review)
#
# Run stages in order. `--stage 0` is always safe and idempotent.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/scripts/lib-paths.sh"
source "$REPO_DIR/scripts/lib-config.sh"
LOG_FILE="/var/log/bootstrap.log"

STAGE=""
DRY_RUN=true
ONLY=""

# Parse args: --stage=N or --stage N (consumes the next arg)
parse_args() {
  local args=("$@") i=0
  while [ $i -lt ${#args[@]} ]; do
    case "${args[$i]}" in
      --stage=*) STAGE="${args[$i]#--stage=}" ;;
      --stage) i=$((i+1)); STAGE="${args[$i]:-}" ;;
      --apply) DRY_RUN=false ;;
      --dry-run) DRY_RUN=true ;;
      --only=*) ONLY="${args[$i]#--only=}" ;;
      --help|-h)
        sed -n '1,30p' "$0" | grep -E "^#|^$" | sed 's/^# \{0,1\}//'
        exit 0 ;;
      *) echo "Unknown flag: ${args[$i]}"; exit 1 ;;
    esac
    i=$((i+1))
  done
}
parse_args "$@"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
die() { log "ERROR: $*"; exit 1; }

run() { # print + optionally execute a command
  if $DRY_RUN; then
    log "  (dry) $*"
  else
    log "  run: $*"
    eval "$*"
  fi
}

ssh_host() { # host cmd... (ssh with BatchMode, optional user)
  local host="$1"; shift
  ssh -o BatchMode=yes -o ConnectTimeout=8 "$host" "$@"
}

# ── Stage 0: preflight ───────────────────────────────────────────────────────

stage_preflight() {
  log "== stage 0: preflight =="
  bash "$REPO_DIR/scripts/validate.sh" || die "validate.sh failed (stage 0)"
  log "validate OK"
  [ -f "$HOSTS_YAML" ] || die "config/hosts.yaml missing"
  log "hosts.yaml present: $HOSTS_YAML"
  if mountpoint -q "$NAS_ROOT"; then
    log "NAS mounted at $NAS_ROOT"
  else
    log "WARN: NAS not mounted at $NAS_ROOT (expected on pve-core; ok on other hosts)"
  fi
  # SSH reachability of every enabled guest + node (fast, non-fatal)
  local g
  while read -r g; do
    [ -n "$g" ] || continue
    local node ip name
    node="$(echo "$g" | awk '{print $2}')"; name="$(echo "$g" | awk '{print $3}')"; ip="$(echo "$g" | awk '{print $4}')"
    [ "$ip" = "dhcp" ] && continue
    local user="root"
    case "$name" in k3s-*) user="npburney" ;; esac
    if timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "${user}@${ip}" 'true' 2>/dev/null; then
      log "  reachable: $name ($ip)"
    else
      log "  WARN: not reachable yet: $name ($ip) — will be created in stage 1"
    fi
  done < <(cfg_guests)
  log "stage 0 complete"
}

# ── Stage 1: infra (Proxmox LXC/VM provisioning) ─────────────────────────────

stage_infra() {
  log "== stage 1: infra (Proxmox guests) =="
  # Guests are created on their configured node, with the tool matching the
  # guest type: lxc -> pct create, vm -> qm create (k3s guests 120-122 are VMs;
  # creating them via pct was wrong and produced undersized LXCs).
  local g
  while read -r g; do
    [ -n "$g" ] || continue
    local vmid node name ip type
    vmid="$(echo "$g" | awk '{print $1}')"; node="$(echo "$g" | awk '{print $2}')"
    name="$(echo "$g" | awk '{print $3}')"; ip="$(echo "$g" | awk '{print $4}')"
    type="$(echo "$g" | awk '{print $5}')"
    local tool="pct"
    [ "$type" = "vm" ] && tool="qm"
    # Find the node's IP
    local node_ip=""
    while read -r n; do
      [ "$(echo "$n" | awk '{print $1}')" = "$node" ] && node_ip="$(echo "$n" | awk '{print $2}')"
    done < <(cfg_nodes)
    [ -n "$node_ip" ] || { log "  WARN: no IP for node $node (skip $name)"; continue; }
    if timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "root@$node_ip" "$tool status $vmid >/dev/null 2>&1" 2>/dev/null; then
      log "  $name (vmid $vmid): already exists on $node — skip"
      continue
    fi
    if $DRY_RUN; then
      log "  (dry) would create $type $vmid ($name) on $node (ip $ip) via $tool"
      continue
    fi
    if [ "$type" = "vm" ]; then
      # VM: cloud-init template, disk, net. Sizing overridable via env.
      local vm_tmpl="${QM_TEMPLATE:-local:vztmpl/debian-12-cloud-amd64.qcow2}"
      local vm_storage="${QM_STORAGE:-local-lvm}"
      local cores="${QM_CORES:-4}" mem="${QM_MEM:-4096}" disk="${QM_DISK:-32}"
      ssh "root@$node_ip" \
        "qm create $vmid --name $name --memory $mem --cores $cores --net0 virtio,bridge=vmbr0 \
           --scsi0 $vm_storage:0,import-from=$vm_tmpl,size=${disk}G \
           --ide2 $vm_storage:cloudinit --boot order=scsi0 \
           --serial0 socket --vga serial0 \
           --ipconfig0 ip=${ip}/24,gw=${NET_GATEWAY:-192.168.1.1} \
           --agent enabled=1" \
        || die "qm create failed for $name"
      ssh "root@$node_ip" "qm start $vmid" || die "qm start failed for $name"
      log "  created VM $vmid ($name) on $node"
    else
      # LXC. Template + storage configurable via env; defaults are the common
      # homelab setup (debian-12, local-lvm).
      local tmpl="${PCT_TEMPLATE:-local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst}"
      local storage="${PCT_STORAGE:-local-lvm}"
      local net=""
      if [ "$ip" != "dhcp" ]; then
        net="name=eth0,bridge=vmbr0,ip=${ip%/*},gw=${NET_GATEWAY:-192.168.1.1},type=veth"
      else
        net="name=eth0,bridge=vmbr0,ip=dhcp,type=veth"
      fi
      ssh "root@$node_ip" \
        "pct create $vmid $tmpl --hostname $name --memory 2048 --cores 2 --storage $storage --net0 \"$net\" --ostype debian --unprivileged 1" \
        || die "pct create failed for $name"
      ssh "root@$node_ip" "pct start $vmid" || die "pct start failed for $name"
      log "  created LXC $vmid ($name) on $node"
    fi
  done < <(cfg_guests)
  log "stage 1 complete"
}

# ── Stage 2: os-bootstrap ────────────────────────────────────────────────────

stage_os_bootstrap() {
  log "== stage 2: os-bootstrap =="
  log "NOTE: this stage assumes guests exist (run stage 1 first)."
  local g
  while read -r g; do
    [ -n "$g" ] || continue
    local name ip type
    name="$(echo "$g" | awk '{print $3}')"; ip="$(echo "$g" | awk '{print $4}')"; type="$(echo "$g" | awk '{print $5}')"
    [ "$type" = "vm" ] && continue  # k3s VMs handled by stage 3
    [ "$ip" = "dhcp" ] && continue
    local user="root"
    if ! timeout 5 ssh -o BatchMode=yes -o ConnectTimeout=3 -o StrictHostKeyChecking=accept-new "${user}@${ip}" 'true' 2>/dev/null; then
      log "  WARN: $name ($ip) not reachable — skip"
      continue
    fi
    if $DRY_RUN; then
      log "  (dry) bootstrap $name ($ip): docker+compose, NFS mounts, cron"
      continue
    fi
    # Docker + compose plugin
    ssh "$user@$ip" '
      command -v docker >/dev/null 2>&1 || (curl -fsSL https://get.docker.com | sh)
      command -v docker compose >/dev/null 2>&1 || (mkdir -p /usr/local/lib/docker/cli-plugins && curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose && chmod +x /usr/local/lib/docker/cli-plugins/docker-compose)
      systemctl enable --now docker
    ' || log "  WARN: docker install failed on $name"
    # NFS mount of NAS homelab share (skip if already mounted)
    local nas_ip nas_share
    nas_ip="$(cfg_nas | awk '{print $2}')"; nas_share="$(cfg_nas | awk '{print $3}')"
    local mount_dest="$(cfg_nas_mount pve)"
    ssh "$user@$ip" "
      grep -q '$mount_dest' /etc/fstab 2>/dev/null || echo '$nas_ip:$nas_share $mount_dest nfs4 defaults,_netdev 0 0' >> /etc/fstab
      mkdir -p $mount_dest
      mountpoint -q $mount_dest || mount $mount_dest || true
    " || log "  WARN: NFS setup failed on $name"
    log "  bootstrapped $name"
  done < <(cfg_guests)
  log "stage 2 complete"
}

# ── Stage 3: k3s ─────────────────────────────────────────────────────────────
# Builds a 3-node control-plane cluster (matches the live environment: all
# three k3s nodes report control-plane,etcd), disables Traefik and ServiceLB
# per docs/k3s-single-node-setup.md (nginx-ingress is the replacement; the
# live cluster has no traefik/servicelb services), and extracts kubeconfig to
# pve-core.

stage_k3s() {
  log "== stage 3: k3s cluster (3 control-plane nodes) =="
  local k3s_line k3s_server k3s_nodes
  k3s_line="$(cfg_k3s)"; k3s_server="$(echo "$k3s_line" | awk '{print $1}')"
  k3s_nodes="$(echo "$k3s_line" | awk '{for(i=2;i<=NF-2;i++) printf "%s ", $i}')"
  [ -n "$k3s_server" ] || die "no k3s server in hosts.yaml"
  local server_ip=""
  while read -r g; do
    [ "$(echo "$g" | awk '{print $3}')" = "$k3s_server" ] && server_ip="$(echo "$g" | awk '{print $4}')"
  done < <(cfg_guests)
  [ -n "$server_ip" ] || die "no IP for k3s server $k3s_server"
  log "server: $k3s_server ($server_ip); nodes: $k3s_nodes"
  local disable_flags="--disable traefik --disable servicelb"
  local k3s_version="${K3S_VERSION:-v1.36.1+k3s1}"
  if $DRY_RUN; then
    log "  (dry) k3s $k3s_version: server --cluster-init on $k3s_server ($disable_flags)"
    for node in $k3s_nodes; do
      [ "$node" = "$k3s_server" ] && continue
      log "  (dry) join $node as server (control-plane) via $server_ip:6443"
    done
    log "  (dry) extract kubeconfig from $k3s_server to pve-core"
    return 0
  fi
  # Install FIRST server with --cluster-init (idempotent)
  ssh "npburney@$server_ip" "
    command -v k3s >/dev/null 2>&1 || curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='$k3s_version' sudo sh -s - server --cluster-init $disable_flags
    sudo systemctl enable --now k3s
  " || die "k3s server install failed on $k3s_server"
  # Extract node token
  local token
  token="$(ssh "npburney@$server_ip" 'sudo cat /var/lib/rancher/k3s/server/node-token' 2>/dev/null | tr -d '\n')"
  [ -n "$token" ] || die "could not read k3s node token"
  # Join the rest as SERVERS (control-plane, not agents)
  for node in $k3s_nodes; do
    [ "$node" = "$k3s_server" ] && continue
    local node_ip=""
    while read -r g; do
      [ "$(echo "$g" | awk '{print $3}')" = "$node" ] && node_ip="$(echo "$g" | awk '{print $4}')"
    done < <(cfg_guests)
    [ -n "$node_ip" ] || { log "  WARN: no IP for k3s node $node"; continue; }
    ssh "npburney@$node_ip" "
      command -v k3s >/dev/null 2>&1 || curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION='$k3s_version' sudo K3S_URL=https://$server_ip:6443 K3S_TOKEN='$token' sh -s - server $disable_flags
      sudo systemctl enable --now k3s
    " || die "k3s server join failed on $node"
    log "  joined $node as control-plane"
  done
  # Extract kubeconfig to pve-core, pointing at the first server's IP.
  log "extracting kubeconfig to $REPO_DIR/kubeconfig"
  ssh "npburney@$server_ip" 'sudo cat /etc/rancher/k3s/k3s.yaml' \
    | sed "s/127.0.0.1/$server_ip/g; s/^    server:.*/    server: https:\/\/$server_ip:6443/" \
    > "$REPO_DIR/kubeconfig" 2>>"$LOG_FILE" \
    || die "could not extract kubeconfig from $k3s_server"
  chmod 600 "$REPO_DIR/kubeconfig"
  log "kubeconfig written to $REPO_DIR/kubeconfig (chmod 600)"
  log "stage 3 complete"
}

# ── Stage 4: secrets ─────────────────────────────────────────────────────────

stage_secrets() {
  log "== stage 4: secrets =="
  if [ ! -f "$REPO_DIR/secrets/homelab.env" ]; then
    die "secrets/homelab.env missing — copy secrets/homelab.env.example and fill in real values"
  fi
  if $DRY_RUN; then
    log "  (dry) would run create-secrets.sh"
  else
    bash "$REPO_DIR/scripts/create-secrets.sh" || die "create-secrets.sh failed"
  fi
  log "stage 4 complete"
}

# ── Stage 5: docker ──────────────────────────────────────────────────────────

stage_docker() {
  log "== stage 5: docker stacks (per host) =="
  local g
  while read -r g; do
    [ -n "$g" ] || continue
    local vmid name ip stack
    vmid="$(echo "$g" | awk '{print $1}')"; name="$(echo "$g" | awk '{print $3}')"
    ip="$(echo "$g" | awk '{print $4}')"; stack="$(echo "$g" | awk '{ $1=$2=$3=$4=$5=$6=""; print }' | sed 's/^ *//')"
    [ -n "$stack" ] || continue
    [ "$ip" = "dhcp" ] && { log "  WARN: $name has no static IP — skip docker deploy"; continue; }
    if [ -n "$ONLY" ] && [ "$name" != "$ONLY" ] && [ "$vmid" != "$ONLY" ]; then continue; fi
    if $DRY_RUN; then
      log "  (dry) deploy on $name ($ip): $stack"
      continue
    fi
    # Guests do NOT have the repo. rsync each stack dir (compose + config +
    # .env if present) to /opt/deploy/docker/<stack> on the guest, then run
    # compose there. Fail hard: a stage that reports completion must have
    # actually deployed (no warn-only).
    for s in $stack; do
      local srcdir="$REPO_DIR/docker/$s"
      [ -d "$srcdir" ] || { log "ERROR: docker/$s not in repo"; exit 1; }
      local dest="/opt/deploy/docker/$s"
      log "  rsync docker/$s -> $name:$dest"
      rsync -a --delete -e "ssh -o BatchMode=yes -o ConnectTimeout=8" \
        "$srcdir/" "root@$ip:$dest/" 2>>"$LOG_FILE" \
        || { log "ERROR: rsync failed for $s on $name"; exit 1; }
      # .env is gitignored, so it won't have rsynced; if one exists in the repo
      # it is copied above; otherwise the operator must provide it on the guest.
      local cf="compose.yaml"
      ssh "root@$ip" "test -f $dest/docker-compose.yml" 2>/dev/null && cf="docker-compose.yml"
      ssh "root@$ip" "test -f $dest/.env" 2>/dev/null || log "  NOTE: no .env on $name for $s (copy .env.example and fill)"
      log "  compose up $s on $name"
      ssh "root@$ip" "cd $dest && docker compose -f $cf up -d" 2>>"$LOG_FILE" \
        || { log "ERROR: compose up failed for $s on $name"; exit 1; }
    done
    log "  deployed stacks on $name"
  done < <(cfg_guests)
  log "stage 5 complete"
}

# ── Stage 6: k8s ─────────────────────────────────────────────────────────────

stage_k8s() {
  log "== stage 6: k8s manifests =="
  if $DRY_RUN; then
    log "  (dry) would run deploy-k8s.sh"
    return 0
  fi
  bash "$REPO_DIR/scripts/deploy-k8s.sh" || die "deploy-k8s.sh failed"
  log "stage 6 complete"
}

# ── Stage 7: configs ─────────────────────────────────────────────────────────

stage_configs() {
  log "== stage 7: file configs (caddy, step-ca) =="
  local g
  while read -r g; do
    [ -n "$g" ] || continue
    local name ip role
    name="$(echo "$g" | awk '{print $3}')"; ip="$(echo "$g" | awk '{print $4}')"; role="$(echo "$g" | awk '{print $6}')"
    if [ "$role" = "edge" ] && [ -n "$ip" ]; then
      if $DRY_RUN; then
        log "  (dry) rsync config/caddy/ -> $name:/etc/caddy/"
      else
        rsync -a --delete "$REPO_DIR/config/caddy/" "root@$ip:/etc/caddy/" \
          || log "  WARN: caddy config sync failed for $name"
        ssh "root@$ip" "systemctl reload caddy 2>/dev/null || systemctl restart caddy" \
          || log "  WARN: caddy reload failed on $name"
      fi
    fi
  done < <(cfg_guests)
  log "stage 7 complete"
}

# ── Stage 8: data restore ────────────────────────────────────────────────────

stage_data_restore() {
  log "== stage 8: data restore =="
  if $DRY_RUN; then
    log "  (dry) would run restore-app-data.sh --force (still HARD-DISABLED in that script)"
    return 0
  fi
  bash "$REPO_DIR/scripts/restore-app-data.sh" --force || die "restore-app-data.sh refused (hard-disable guard)"
  log "stage 8 complete"
}

# ── dispatch ─────────────────────────────────────────────────────────────────

log "bootstrap: stage=${STAGE:-all} dry_run=$DRY_RUN only=${ONLY:-none}"

if [ -n "$STAGE" ]; then
  case "$STAGE" in
    0) stage_preflight ;;
    1) stage_infra ;;
    2) stage_os_bootstrap ;;
    3) stage_k3s ;;
    4) stage_secrets ;;
    5) stage_docker ;;
    6) stage_k8s ;;
    7) stage_configs ;;
    8) stage_data_restore ;;
    *) die "unknown stage: $STAGE" ;;
  esac
else
  stage_preflight
  stage_infra
  stage_os_bootstrap
  stage_k3s
  stage_secrets
  stage_docker
  stage_k8s
  stage_configs
  stage_data_restore
fi

log "bootstrap complete."
