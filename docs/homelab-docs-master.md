=== README.md ===
# Homelab Documentation

Technical reference for the Burney homelab — setup procedures, best practices,
troubleshooting guides, and security policies.

## Documents

### Core Infrastructure

| Document | Description |
|----------|-------------|
| [runbook.md](runbook.md) | Recovery, clean install, rollback, backup/restore procedures |
| [k3s-single-node-setup.md](k3s-single-node-setup.md) | K3s cluster architecture, bootstrap, Ansible details, storage classes |
| [k3s-troubleshooting.md](k3s-troubleshooting.md) | CrashLoopBackOff, NotReady nodes, CNI issues, kubectl contexts, etcd recovery |
| [docker-services.md](docker-services.md) | Caddy reverse proxy architecture, Docker service inventory, port bindings, deploy order |
| [networking.md](networking.md) | DNS, OPNsense config, hairpin NAT, port map, NetworkPolicy |
| [storage.md](storage.md) | Storage classes, NFS provisioner, PVC migration, data survival |
| [monitoring.md](monitoring.md) | Prometheus/Grafana/Blackbox setup, alert rules |
| [best-practices.md](best-practices.md) | Repo structure, deployment/troubleshooting order, common gotchas |
| [gitops-plan.md](gitops-plan.md) | Commit-to-live deployment architecture, drift inventory, phased GitOps rollout |

### Security & Access

| Document | Description |
|----------|-------------|
| [security.md](security.md) | Secrets policy, gitignore strategy, NetworkPolicy, TLS, socket proxy, audit findings |
| [ssh-key-management.md](ssh-key-management.md) | SSH keys, deploy keys, Pi agent access, HA filesystem layout and MCP tools |

### Home Assistant

| Document | Description |
|----------|-------------|
| [home-assistant-git-backup.md](home-assistant-git-backup.md) | Config version control, GitHub deploy keys, .gitignore, security audit, public repo prep |
| [home-assistant.md](home-assistant.md) | HA overview (MCP tools, dashboards, Python transforms) |
| [home-assistant-energy-monitoring.md](home-assistant-energy-monitoring.md) | Emporia Vue 3, ESPHome config, CT clamp debugging |
| [home-assistant-integrations.md](home-assistant-integrations.md) | ESPHome/Emporia Vue, HA-MCP server, Assist exposure |
| [home-assistant-management.md](home-assistant-management.md) | Device cleanup, dashboard editing, automation design |

### Tools

| Document | Description |
|----------|-------------|
| [pi-agent-setup.md](pi-agent-setup.md) | Pi coding agent configuration, sessions, skills, MCP servers |
| [vikunja-management.md](vikunja-management.md) | Vikunja project organization, CSV import, best practices |

### Projects

| Document | Description |
|----------|-------------|
| [statclock.md](statclock.md) | ESP32 CS2 stat-tracking display, Go CLI, FACEIT API |

## Quick Reference

### Servers

| Host | IP | Role |
|------|----|------|
| burndev | 192.168.1.50 | Primary homelab server (k3s + Docker) |
| synology | 192.168.1.11 | NAS — NFS storage, backups |
| homeassistant | homeassistant.lan | Home Assistant (dedicated Pi) |
| opnsense | 192.168.1.1 | Gateway — DNS, DHCP, routing, firewall |

### Devices

| Device | IP | Notes |
|--------|----|-------|
| Emporia Vue 3 | 192.168.1.139 | Energy monitoring (ESPHome) |
| statclock ESP32 | DHCP | CS2 stat-tracking display |
| kws-rpi-1 | DHCP | Klipper 3D printer controller |

### Key Commands

```bash
# Health check
kubectl --context default get nodes && docker ps --format 'table {{.Names}}\t{{.Status}}'

# Deploy K8s apps
bash scripts/deploy-k8s.sh

# Deploy Docker stacks
make deploy-docker

# K3s reinstall — DESTRUCTIVE: wipes local-path PVCs (termix, trilium, immich-postgres). Back up first.
/usr/local/bin/k3s-uninstall.sh
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.1+k3s1 sh -s - server \
  --write-kubeconfig-mode 644 --disable traefik --disable servicelb \
  --cluster-init --node-name burndev
# Then reinstall nginx-ingress + cert-manager — see k3s-single-node-setup.md

# HA git backup (manual) — uses sh, not bash (Alpine add-on has no bash by default)
ssh homeassistant "sh /config/backup.sh"

# Backup homelab repo to NAS
bash scripts/backup.sh

# Backup Docker volumes + app data to NAS
bash scripts/backup-app-data.sh

# Preview restore from NAS (safe, no changes)
bash scripts/pull-from-nas-backup.sh --dry-run

# Validate all manifests
make validate
```

### Important Paths

| Path | Purpose |
|------|---------|
| `~/dev/homelab/` | Infrastructure repo |
| `~/dev/homelab/docker/` | Docker compose stacks |
| `~/dev/homelab/docker/caddy/certs/` | Caddy TLS certificates (runtime) |
| `~/dev/homelab/docker/caddy/data/` | Caddy ACME data (runtime) |
| `~/dev/homelab/kubernetes/` | K8s manifests |
| `~/dev/homelab/ansible/` | Ansible playbooks |
| `~/dev/homelab/scripts/` | Backup, deploy, restore scripts |
| `/opt/docker/` | Docker compose runtime directories (servarr, vikunja, etc.) |
| `~/dev/statclock/` | StatClock project (Go CLI + ESPHome) |
| `~/.ssh/config` | SSH aliases for all servers |
| `~/.pi/agent/skills/homelab-inventory/` | Pi homelab inventory |
| `/mnt/syn/` | Synology NAS mount point on burndev |
| `/mnt/syn/backups/homelab/` | Backup destination |

### Service Map

```
                          internet
                              │
                     ┌────────┴────────┐
                     │   OPNsense      │
                     │ 192.168.1.1     │
                     │ DNS + NAT       │
                     └────────┬────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
     ┌────────┴────────┐ ┌───┴───┐ ┌────────┴────────┐
     │    burndev      │ │  NAS  │ │ Home Assistant  │
     │ 192.168.1.50    │ │ .1.11 │ │ homeassistant.lan│
     │                 │ │       │ │                 │
     │ Caddy :80/:443  │ │ NFS   │ │ HA + ESPHome    │
     │ Docker stacks   │ │ SMB   │ │ Zigbee/Z-Wave   │
     │ k3s (single)    │ │       │ │                 │
     │ nginx-ingress   │ │       │ │                 │
     │ (vestigial)     │ │       │ │                 │
     └─────────────────┘ └───────┘ └─────────────────┘
```


=== runbook.md ===
# Recovery Runbook

Procedures for clean install, recovery, and rollback of the homelab single-node deployment (burndev, 192.168.1.50).

## Related Docs

| Document | Topic |
|----------|-------|
| [k3s-single-node-setup.md](k3s-single-node-setup.md) | k3s install, storage classes, UFW rules, architecture |
| [k3s-troubleshooting.md](k3s-troubleshooting.md) | CrashLoopBackOff, NotReady nodes, CNI issues, kubectl contexts |
| [docker-services.md](docker-services.md) | Caddy architecture, port bindings, TLS certs, socket proxy, Docker inventory |
| [networking.md](networking.md) | DNS, OPNsense config, hairpin NAT, port map, NetworkPolicy |
| [storage.md](storage.md) | Storage classes, NFS, PVC migration, data survival |
| [monitoring.md](monitoring.md) | Prometheus/Grafana/Blackbox setup, alert rules |
| [security.md](security.md) | Secrets policy, gitignore, NetworkPolicy, TLS, socket proxy, audit findings |
| [ssh-key-management.md](ssh-key-management.md) | SSH keys, deploy keys, Pi agent access, HA filesystem layout |
| [home-assistant-git-backup.md](home-assistant-git-backup.md) | Config backup to GitHub, deploy keys, .gitignore, security audit |
| [home-assistant-management.md](home-assistant-management.md) | Device cleanup, dashboard editing, automation design |
| [home-assistant-energy-monitoring.md](home-assistant-energy-monitoring.md) | Emporia Vue 3, ESPHome config, CT clamp debugging |
| [pi-agent-setup.md](pi-agent-setup.md) | Pi configuration, sessions, skills, MCP servers |
| [vikunja-csv-import.md](vikunja-csv-import.md) | CSV import format for bulk task creation |
| [best-practices.md](best-practices.md) | Repo structure, deployment/troubleshooting order, common gotchas |

## Prerequisites

- Debian-based OS installed on burndev with SSH access
- SSH key (`~/.ssh/id_ed25519_npburney_burndev`) loaded in ssh-agent (`ssh-add -L`)
- Synology NAS (192.168.1.11) with NFS export `/volume1/homelab/k8s/`
- NAS mounted at `/mnt/syn` (add to `/etc/fstab` for persistence)
- `git`, `ansible`, `kubectl`, `helm`, `docker` installed on burndev
- DNS records pointing `*.burndev.lan` and `*.homelab.lan` to `192.168.1.50`

## Service Ownership (Docker vs K8s)

| App | Canonical | Domain | Port | Backend |
|-----|-----------|--------|------|---------|
| Immich | Docker | `immich.pve.lan` | 2283 | pve-exu LXC 111 |
| Jellyfin | Docker | `burney.tv` | 8096 | Caddy → localhost:8096 |
| Sonarr | Docker | `sonarr.burndev.lan` | 8989 | Caddy → localhost:8989 |
| Radarr | Docker | `radarr.burndev.lan` | 7878 | Caddy → localhost:7878 |
| Lidarr | Docker | `lidarr.burndev.lan` | 8686 | Caddy → localhost:8686 |
| Prowlarr | Docker | `prowlarr.burndev.lan` | 9696 | Caddy → localhost:9696 |
| qBittorrent | Docker | `qbit.burndev.lan` | 8889 | Caddy → localhost:8889 |
| Actual Budget | Docker | `actual.burndev.lan` | 5006 | Caddy → localhost:5006 |
| Homepage (burndev) | Docker | `home.burndev.lan` | 3000 | Caddy → localhost:3000 |
| Vikunja | Docker | — | 3456 | localhost only, no public route |
| Scanopy | Docker | — | 60072 | LAN-only (device discovery) |
| Cannery | Docker | — | 4000 | localhost only, no public route |
| RackPeek | Docker | — | 3001 | localhost only, no public route |
| Portainer | Docker | `portainer.burndev.lan` | 9443 | Caddy → localhost:9443 |
| UniFi | Docker | `unifi.burndev.lan` | 8443 | Caddy → localhost:8443 |
| Homepage (K8s) | K8s | `home.homelab.lan` | 30080 | Caddy → NodePort 30080 |
| Trilium | K8s | `trilium.homelab.lan` | 30081 | Caddy → NodePort 30081 |
| Termix | K8s | `termix.homelab.lan` | 30082 | Caddy → NodePort 30082 |
| VS Code | K8s | `code.homelab.lan` | 30083 | Caddy → NodePort 30083 |
| Kanboard | K8s | `kanboard.homelab.lan` | 30084 | Caddy → NodePort 30084 |
| Omni Tools | K8s | `omni.homelab.lan` | 30085 | Caddy → NodePort 30085 |
| Grafana | K8s | `grafana.homelab.lan` | 30086 | Caddy → NodePort 30086 |
| Prometheus | K8s | `prometheus.homelab.lan` | — | kube-prometheus-stack via Caddy |
| Alertmanager | K8s | `alertmanager.homelab.lan` | — | kube-prometheus-stack via Caddy |

**Routing architecture**: Caddy runs in `network_mode: host` and owns ports 80/443. It reverse-proxies Docker services on `127.0.0.1:<port>` and K8s services on `127.0.0.1:30080-30086` (NodePort). Both domain trees (`*.burndev.lan`, `*.homelab.lan`) use separate TLS certificate bundles.

**Port binding summary**:
- `127.0.0.1` — All reverse-proxied Docker services (Caddy handles external access)
- `192.168.1.50` — Jellyfin DLNA (7359/udp), Docker socket proxy (2375)
- `0.0.0.0` — Scanopy device discovery (60072), qBittorrent peer ports (32239), gluetun VPN (8889)

## Clean Install Order

### 1. Bootstrap Kubernetes (Ansible)

```bash
git clone <repo-url> ~/dev/homelab
cd ~/dev/homelab
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml
```

This installs k3s on burndev with Traefik and ServiceLB disabled, embedded etcd, UFW configured, kernel modules loaded, and sysctl tuned.

**What the `common` Ansible role does:**
- Disables swap (required by k3s)
- Loads kernel modules: `overlay`, `br_netfilter`
- Sets sysctl: `net.bridge.bridge-nf-call-iptables=1`, `net.ipv4.ip_forward=1`
- Installs packages: curl, open-iscsi, nfs-common, ufw
- Configures UFW: default deny incoming, allow outgoing; allow SSH (22), HTTP/HTTPS (80/443), k3s API (6443), kubelet (10250), Flannel VXLAN (8472/udp), k3s supervisor (9345), etcd (2379, 2380)

**What the `control_plane` Ansible role does:**
- Detects current state (fresh install vs SQLite vs etcd)
- Performs SQLite-to-etcd migration if going from single-server to HA
- Installs k3s server with `--cluster-init` (or standalone)
- Exports node token for workers/joiners
- Applies node labels and taints

**Node labels (burndev):**
```yaml
node_labels:
  burndev:
    - "node-type=desktop"
    - "gpu=nvidia"
```

**Ansible gotchas**:
- When running from burndev itself, use `ansible_connection: local` in host vars
- `ansible_user` must be `npburney` (not `debian` which was for Proxmox VMs)
- The playbook is `ansible/site.yml`, not `inventory/site.yml`

### 2. Install Cert-Manager

```bash
bash kubernetes/cert-manager/install-cert-manager.sh
kubectl apply -f kubernetes/cert-manager/ca-issuer.yml
```

### 3. Install Platform Components

```bash
bash scripts/install-nfs-provisioner.sh
bash scripts/install-kube-prometheus-stack.sh
bash scripts/install-blackbox-exporter.sh
```

### 4. Deploy K8s Apps

```bash
bash scripts/deploy-k8s.sh --dry-run   # validate first
bash scripts/deploy-k8s.sh             # apply
```

### 5. Deploy Docker Stacks

```bash
make deploy-docker
```

Or individually:
```bash
cd docker/caddy && docker compose up -d      # edge proxy first
cd docker/immich && docker compose up -d
cd docker/jellyfin && docker compose up -d
# ... remaining stacks
```

## Verification

### Caddy (edge proxy)
```bash
docker ps | grep caddy
curl -k https://home.burndev.lan
curl -k https://home.homelab.lan
```

### DNS resolution
```bash
dig home.burndev.lan +short      # expect 192.168.1.50
dig home.homelab.lan +short      # expect 192.168.1.50
```

### NAS mount
```bash
mountpoint /mnt/syn && echo "OK" || echo "NOT MOUNTED"
```

### NFS StorageClass
```bash
kubectl get storageclass nfs
kubectl -n kube-system get pods -l app=nfs-subdir-external-provisioner
```

### Docker socket proxy (Homepage discovery)
```bash
curl http://192.168.1.50:2375/version
```

### K8s services (NodePort)
```bash
curl http://localhost:30080   # Homepage K8s
curl http://localhost:30081   # Trilium
curl http://localhost:30084   # Kanboard
```

### TLS certificates
```bash
# Verify Caddy loads certs (check logs)
docker logs caddy 2>&1 | grep -i cert

# Export K8s CA for browser trust
kubectl get secret homelab-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' \
  | base64 -d > homelab-ca.crt
```

### Validate all manifests
```bash
make validate
```

## Backup Script

Daily rsync of `~/dev/homelab/` to NAS at `/mnt/syn/backups/homelab/`. Script at `scripts/backup.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="/mnt/syn/backups/homelab"
LOG_FILE="$REPO_DIR/scripts/backup.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
log "Starting homelab backup"
if ! mountpoint -q /mnt/syn; then
  log "ERROR: /mnt/syn is not mounted. Backup aborted."
  exit 1
fi
mkdir -p "$BACKUP_DIR"
rsync -aHAX --no-owner --no-group --delete --info=progress2 "$REPO_DIR/" "$BACKUP_DIR/"
log "Backup complete"
```

### What gets backed up

The entire `~/dev/homelab/` repo: K8s manifests, Docker compose files, Ansible playbooks, Homepage config, scripts.

### What does NOT get backed up (by backup.sh)

`backup.sh` only rsyncs the repo. Docker volumes, app data, and PVC data need separate backup:

- Docker volumes in `/opt/docker/` — use `scripts/backup-app-data.sh`
- K8s PVC data on `local-path` — lives in `/var/lib/rancher/k3s`; use `scripts/backup-app-data.sh`
- Caddy certificates in `~/dev/homelab/docker/caddy/certs/` and `data/` — included in `backup-app-data.sh`
- Immich photo library — backed separately on NAS (`/volume1/immich`)

`scripts/backup-app-data.sh` handles Docker volumes, Caddy certs, and K8s local-path PVCs by creating tarballs to `/mnt/syn/backups/homelab/`.

### Backup scripts

Two backup scripts exist:
- `scripts/backup.sh` — rsyncs the repo (`~/dev/homelab/`) to NAS
- **`scripts/backup-app-data.sh`** — backs up Docker volumes, PostgreSQL dumps, Caddy certs, and K8s PVCs to NAS. This is what creates the volume tarballs referenced below.

## Restore from Backup

### Restore order

1. **Network** — Confirm NAS mount, DNS, UFW rules
2. **NAS** — Mount `/mnt/syn`, verify NFS exports
3. **Caddy** — Deploy Caddy first (edge proxy, all routes depend on it)
4. **Core apps** — Immich, Jellyfin, Actual Budget, Trilium (user data)
5. **Monitoring** — Prometheus, Grafana, Alertmanager
6. **Tools** — Everything else (arr stack, Vikunja, Scanopy, etc.)

### Repo restore

```bash
# Preview (safe, no changes)
bash scripts/pull-from-nas-backup.sh --dry-run

# Apply
bash scripts/pull-from-nas-backup.sh --apply

# Check last backup timestamp
cat scripts/backup.log
```

### App-data restore

```bash
# Preview (safe, no changes)
bash scripts/restore-app-data.sh --dry-run

# Apply (requires --force and interactive confirmation)
bash scripts/restore-app-data.sh --force
```

### Per-app restore notes

**Immich (Docker)**:
- Restore volume data from `/mnt/syn/backups/homelab/docker-volumes/opt/docker/immich/`
- Restore PostgreSQL dump: `psql -h localhost -U postgres immich < immich_*.sql`
  (dumps are at `/mnt/syn/backups/homelab/postgres-dumps/`)

**Jellyfin (Docker)**:
- Restore volume data from `/mnt/syn/backups/homelab/docker-volumes/opt/docker/jellyfin/`

**Actual Budget (Docker)**:
- Restore volume data from `/mnt/syn/backups/homelab/docker-volumes/opt/docker/actual-budget/`

**Trilium (K8s)**:
- Scale down: `kubectl -n tools scale deployment trilium --replicas=0`
- Restore PVC data from `/mnt/syn/backups/homelab/k8s/trilium/`
- Scale up: `kubectl -n tools scale deployment trilium --replicas=1`

**Termix (K8s)**:
- Same pattern as Trilium: scale down, restore PVC, scale up

**Caddy certs**:
- Caddy certs/data are at `~/dev/homelab/docker/caddy/certs/` and `~/dev/homelab/docker/caddy/data/`
- Backed up by `backup-app-data.sh` to `/mnt/syn/backups/homelab/caddy/`
- Or restore via `scripts/restore-app-data.sh --force` which handles all paths

### Idempotent re-apply

After restoring data, re-run the deployment to ensure config is current:

```bash
cd ~/dev/homelab/ansible
ansible-playbook site.yml          # idempotent — checks cluster health
bash ~/dev/homelab/scripts/deploy-k8s.sh    # idempotent — re-applies all manifests
```

## Rollback a Failed Deploy

### Docker stack rollback

```bash
cd docker/<stack>
docker compose down
# Fix the issue (edit compose.yaml, .env, etc.)
docker compose up -d
```

For Caddy specifically — if Caddy fails, all routing goes down. Fix Caddy first:
```bash
cd docker/caddy
docker compose down
# Fix Caddyfile or cert paths
docker compose config --quiet   # validate
docker compose up -d
docker logs caddy -f            # watch for errors
```

### K8s manifest rollback

```bash
# Check what changed
git diff HEAD~1

# Revert to previous commit state for K8s manifests
git checkout HEAD~1 -- kubernetes/

# Re-apply
bash scripts/deploy-k8s.sh
```

### Helm rollback

```bash
helm -n monitoring rollback kube-prometheus-stack
helm -n kube-system rollback nfs-provisioner
```

## Rebuild from Blank Debian

1. Install Debian on burndev, set static IP `192.168.1.50`
2. Install packages: `apt install -y git ansible docker.io curl`
3. Install kubectl: follow [k3s docs](https://docs.k3s.io/cluster-access) or use the kubeconfig from Ansible bootstrap
4. Install helm: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`
5. Mount NAS: `mkdir -p /mnt/syn && mount 192.168.1.11:/volume1/homelab /mnt/syn`
6. Clone repo: `git clone <repo-url> ~/dev/homelab`
7. Run the clean install order above (sections 1-5)

## Health Check Commands

```bash
# All-in-one health snapshot
make validate                            # pre-flight checks
kubectl get nodes                        # node status (expect Ready)
kubectl get pods -A | grep -v Running    # non-running pods
docker ps --format 'table {{.Names}}\t{{.Status}}'  # container status
mountpoint /mnt/syn                      # NAS
df -h /mnt/syn                           # NAS disk space
```

## SSH Access for Pi Agent

Pi coding agent needs dedicated SSH keys for homelab servers. See [ssh-key-management.md](ssh-key-management.md) for setup (includes HA filesystem layout and MCP tool access). General pattern:

```bash
# Generate dedicated key
ssh-keygen -t ed25519 -C "pi-agent" -f ~/.ssh/pi_agent_ed25519 -N ""

# Add to ~/.ssh/config
Host <alias>
    HostName <hostname>
    User <user>
    IdentityFile ~/.ssh/pi_agent_ed25519
    IdentitiesOnly yes
```

## Emergency Contacts / External Systems

- **NAS**: Synology at 192.168.1.11 — if down, all NFS PVCs and backups fail
- **Gateway**: OPNsense at 192.168.1.1 — if down, DNS/DHCP/routing fail
- **Backup location**: `/mnt/syn/backups/homelab/` on the NAS
- **Backup log**: `scripts/backup.log` in the repo


=== k3s-single-node-setup.md ===
# k3s Single-Node Setup (burndev)

How the homelab moved from Proxmox VMs to bare-metal k3s on `burndev` (192.168.1.50), plus complete setup and configuration.

## Architecture Decision

**Previous**: Three Proxmox VMs (k8s-cp-01, k8s-worker-01, k8s-worker-02) on mini-PC cluster.
**Current**: Single-node k3s with embedded etcd on burndev, the bare-metal Debian desktop.

### Why the change
- Proxmox VMs added complexity without benefit for a single-user homelab
- burndev runs 24/7 and had capacity
- Single-node means no cross-node networking, no quorum concerns, no etcd split-brain risk

## Prerequisites

- Debian-based OS (burndev runs Debian 13 trixie)
- Static IP configured (192.168.1.50)
- Docker already installed and running
- Synology NAS mounted at `/mnt/syn` for NFS PVCs
- DNS records: `*.burndev.lan` and `*.homelab.lan` → `192.168.1.50`

## Install k3s

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.1+k3s1 sh -s - server \
  --write-kubeconfig-mode 644 \
  --disable traefik \
  --disable servicelb \
  --cluster-init \
  --node-name burndev
```

**Flags explained**:
| Flag | Purpose |
|------|---------|
| `--write-kubeconfig-mode 644` | kubectl works without sudo |
| `--disable traefik` | use nginx-ingress instead |
| `--disable servicelb` | no need for built-in load balancer on single node |
| `--cluster-init` | initializes embedded etcd (required even for single node) |
| `--node-name burndev` | explicit node name matching the host |

## Verify

```bash
sudo k3s kubectl get nodes
# Expected: burndev   Ready   control-plane,etcd   <age>   v1.36.1+k3s1
```

## Post-Install Steps

### 1. Install nginx-ingress (replaces Traefik)

k3s disables Traefik; nginx-ingress is the replacement.

**Note**: nginx-ingress is currently not running (stuck Terminating as of July 2026). Caddy routes directly to NodePorts (30080-30086) instead. The NetworkPolicy allow rules referencing `ingress-nginx` are vestigial. To fully reinstate nginx-ingress, delete the stale namespace and reinstall:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.13.1/deploy/static/provider/baremetal/deploy.yaml
```

### 2. Install cert-manager

```bash
chmod +x kubernetes/cert-manager/install-cert-manager.sh
bash kubernetes/cert-manager/install-cert-manager.sh
kubectl apply -f kubernetes/cert-manager/ca-issuer.yml
```

### 3. Deploy Apps (in order)

```bash
# 1. Namespaces
kubectl apply -f kubernetes/namespaces/

# 2. Network policies
kubectl apply -f kubernetes/policies/tools/
kubectl apply -f kubernetes/policies/monitoring/

# 3. Apps
kubectl apply -f kubernetes/apps/

# 4. Monitoring (optional)
kubectl apply -f kubernetes/monitoring/
```

**Note**: `blackbox-values.yml` and `prometheus-additional-scrape.yml` are **not** `kubectl apply`-able. They are Helm values / Prometheus config snippets used when installing kube-prometheus-stack and blackbox-exporter.

## Ansible Notes (Optional)

When running from burndev itself, Ansible is overkill — it was designed for remote provisioning of Proxmox VMs. Direct `kubectl` or `k3s kubectl` is simpler and sufficient for a local single-node cluster.

### Ansible gotchas (if using)
- The playbook is `ansible/site.yml`, NOT `inventory/site.yml`
- `ansible_user` must be `npburney` (not `debian` which was for Proxmox VMs)
- When running locally, use `connection: local` or skip SSH entirely:
  ```yaml
  # ansible/inventory/host_vars/burndev.yml
  ansible_connection: local
  ansible_user: npburney
  ```

## Kubeconfig

- `/etc/rancher/k3s/k3s.yaml` is the cluster kubeconfig
- The context name is `default`, pointing at `https://127.0.0.1:6443`
- If you switch between burndev and mini-PC, you need separate contexts

```bash
# Copy k3s config to user kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Or set KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Rename context for clarity
kubectl config rename-context default homelab-local
```

## UFW Rules

These ports must be open on the host:

| Port | Proto | Purpose |
|------|-------|---------|
| 22 | TCP | SSH |
| 80 | TCP | HTTP ingress |
| 443 | TCP | HTTPS ingress |
| 6443 | TCP | k3s API server |
| 10250 | TCP | kubelet |
| 8472 | UDP | Flannel VXLAN |
| 9345 | TCP | k3s supervisor |
| 2379 | TCP | etcd client |
| 2380 | TCP | etcd peer |

## Storage Classes

| StorageClass | Backend | Used By |
|-------------|---------|---------|
| `local-path` | Local host disk | termix, trilium, immich-postgres |
| `nfs` | Synology NAS (`/volume1/homelab/k8s/`) | code-server, kanboard, grafana, homepage, immich-upload |
| `immich-upload-manual` | NFS (manually provisioned PV) | immich uploads |

**Important**: Services using `local-path` have data tied to burndev's disk. NFS-backed services survive node rebuilds.

## Services Running on k3s

| Service | Namespace | NodePort | Domain |
|---------|-----------|----------|--------|
| Homepage | default | 30080 | home.homelab.lan |
| Trilium | tools | 30081 | trilium.homelab.lan |
| Termix | tools | 30082 | termix.homelab.lan |
| VS Code | tools | 30083 | code.homelab.lan |
| Kanboard | tools | 30084 | kanboard.homelab.lan |
| Omni Tools | tools | 30085 | omni.homelab.lan |
| Grafana | monitoring | 30086 | grafana.homelab.lan |

## Common Issues

### k3s not found / service not found
This means k3s was never installed or was cleaned up. No `k3s-uninstall.sh` needed — just run the install command.

### Ansible SSH failures
If using Ansible on the same machine, set `ansible_connection: local` in host vars instead of SSH (see Ansible Notes above).

### Missing nginx-ingress
Symptoms: Ingress resources fail with "no matches for kind Ingress" or webhook errors.
Fix: Install nginx-ingress (see Post-Install Steps above).

### cert-manager warnings on first apply
`missing annotation` warnings from `kubectl apply` are normal on first install. cert-manager works correctly despite them.

### DNS hairpin
Symptom: Internal clients can't reach homelab services by domain.
Fix: Enable NAT reflection in OPNsense, or ensure internal DNS resolves directly to `192.168.1.50`.

## k3s Uninstall (if needed)

```bash
/usr/local/bin/k3s-uninstall.sh
```

## Architecture Notes

- Single-node k3s with embedded etcd (no external datastore)
- Caddy runs in Docker (`network_mode: host`, owns ports 80/443)
- Caddy reverse-proxies: Docker services → `127.0.0.1:<port>`, K8s services → `127.0.0.1:30080-30086` (NodePort)
- Docker socket proxy at `192.168.1.50:2375` for Homepage auto-discovery
- NAS at `192.168.1.11` provides NFS for persistent K8s storage and backups

---

# Multi-Node Troubleshooting (Historical — Proxmox Cluster)

These issues occurred on the old 3-node Proxmox cluster. Documented here for reference.

## Node NotReady (kubelet stopped posting)

**Symptom**: Node shows `NotReady`, last heartbeat weeks ago, pods stuck `Terminating`.
**Root cause**: VM went down and never came back.
**Fix**:
```bash
kubectl delete node k8s-worker-01
kubectl delete pods --force --grace-period=0 -n <ns> <stuck-pod>
```

If the node should come back:
1. SSH to the node
2. Check `sudo systemctl status k3s` / `sudo systemctl status k3s-agent`
3. Check disk space: `df -h`
4. Restart k3s: `sudo systemctl restart k3s`

## Cross-node pod networking broken

**Symptom**: Pod on node A cannot reach pod on node B (ECONNREFUSED despite DNS resolution).
**Root cause**: Flannel routing between nodes broke. No CNI DaemonSets visible (k3s uses embedded flannel).
**Diagnosis**: Check CNI with `kubectl get pods -n kube-system`, test cross-node connectivity with `nc -zv <pod-ip> <port>` from a debug pod.
**Fix**: Requires node-level investigation (iptables rules, firewall, flannel config on each node).

## homepage CrashLoopBackOff (readOnly mount)

**Symptom**: Container `chown` fails on a readOnly file.
**Root cause**: ConfigMap mounted with `readOnly: true` but container init tries to `chown`.
**Fix**: Remove `readOnly: true` from the volume mount in the deployment.

## immich-server CrashLoopBackOff (postgres unreachable)

**Symptom**: ECONNREFUSED to postgres, but postgres pod is Running.
**Root cause**: Cross-node networking failure or postgres listening config.
**Diagnosis**: Check postgres `listen_addresses` config, check network policies, verify cross-node connectivity.


=== k3s-troubleshooting.md ===
# k3s Troubleshooting Guide

Common issues encountered in the homelab k3s cluster and how to diagnose/fix them.

## Diagnostic Commands

```bash
# Cluster health
kubectl get nodes -o wide
kubectl get pods -A | grep -v Running
kubectl get events -A --sort-by='.lastTimestamp' | tail -30

# Specific node
kubectl describe node <node-name> | tail -40

# Pods on a specific node
kubectl get pods -A -o wide | grep <node-name>
kubectl get pods -A --field-selector spec.nodeName=<node>

# CrashLoopBackOff pods
kubectl get pods -A | grep CrashLoopBackOff
```

### Pod investigation

```bash
kubectl describe pod <pod-name> -n <ns>    # events, conditions, mounts
kubectl logs <pod-name> -n <ns>            # container logs
kubectl logs <pod-name> -n <ns> --previous # logs from previous (crashed) container
```

## Issue: Node NotReady

### Symptoms
- `kubectl get nodes` shows status `NotReady`
- Pods stuck in `Terminating` on that node
- Kubelet stopped posting heartbeats

### Causes
- Node is powered off or unreachable
- Kubelet stopped (crashed, OOM, disk pressure)
- Network partition — node can't reach the control plane

### Diagnosis
```bash
# Check when node last reported
kubectl describe node <node-name> | grep -A5 Conditions
# Look for: KubeletReady, MemoryPressure, DiskPressure, NetworkUnavailable

# Check if node is reachable
ping -c 2 <node-ip>

# Check k3s service on the node
ssh <node> "sudo systemctl status k3s"
ssh <node> "sudo journalctl -u k3s -n 50"
```

### Fix
If the node is permanently gone:

```bash
# Remove node from cluster
kubectl delete node <node-name>

# Force-delete stuck pods
kubectl delete pods --force --grace-period=0 -n <ns> <pod-name>
```

If the node should come back:
1. SSH to the node
2. Check `sudo systemctl status k3s` / `sudo systemctl status k3s-agent`
3. Check disk space: `df -h`
4. Restart k3s: `sudo systemctl restart k3s`

## Issue: CrashLoopBackOff — Read-Only Volume Mount

### Symptoms
- Pod enters CrashLoopBackOff
- Logs show `chown: changing ownership of '...': Read-only file system`
- Container has an init or startup script that runs `chown` on a config volume

### Example (homepage)
Homepage container runs `chown -R 1000:1000 /app/config` at startup, but `/app/config/docker.yaml` is mounted `readOnly: true` from a ConfigMap.

### Fix
Remove `readOnly: true` from the volume mount in the Deployment spec:

```yaml
volumeMounts:
  - name: docker-config
    mountPath: /app/config/docker.yaml
    subPath: docker.yaml
    readOnly: true   # ← REMOVE THIS LINE
```

Apply: `kubectl apply -f kubernetes/apps/homepage.yml`

## Issue: CrashLoopBackOff — Database Connection Refused

### Symptoms
- App pod in CrashLoopBackOff
- Logs show: `ECONNREFUSED <ip>:5432` (PostgreSQL) or similar

### Diagnosis Tree

```bash
# 1. Is the database pod running?
kubectl get pods -n <ns> | grep postgres

# 2. Can the database pod accept local connections?
kubectl exec -n <ns> deployment/<db-deploy> -- pg_isready

# 3. Does DNS resolve from the app pod?
kubectl exec -n <ns> deployment/<app-deploy> -- nslookup <db-svc>

# 4. Can a test pod reach the database?
kubectl run -n <ns> -it --rm test-conn --image=alpine:3.19 --restart=Never -- \
  sh -c "apk add netcat-openbsd; nc -zv -w 3 <db-svc> 5432"

# 5. Check if cross-node networking works (multi-node only):
# Run test pod on same node as DB, then on different node
kubectl get pods -n <ns> -o wide  # note which node each pod is on
```

### Common Causes & Fixes

| Cause | Fix |
|-------|-----|
| DB pod not running | Check DB pod logs, restart if needed |
| NetworkPolicy blocks traffic | Check `kubernetes/policies/` for deny rules |
| CNI broken (flannel) | Restart k3s, check `iptables -L -n -t nat` |
| Wrong DB_HOST env var | Check deployment env vars match service name |
| DB not listening on all interfaces | Check `listen_addresses` in postgresql.conf |

## Issue: Cross-Node Networking (CNI / Flannel)

If pods on different nodes can't reach each other (flannel issue):

```bash
# On the node: check iptables
sudo iptables -L -n -t nat | grep FLANNEL

# Check flannel interface
ip link show flannel.1
ip addr show flannel.1

# Restart k3s (flannel is embedded)
sudo systemctl restart k3s
```

## Issue: kubectl Context Wrong

### Symptoms
- `kubectl --context <name>` fails with "context was not found"
- Commands target the wrong cluster

### Diagnosis
```bash
# See all contexts
kubectl config get-contexts

# Current context
kubectl config current-context

# Full config
kubectl config view
```

### Kubeconfig Locations
- k3s writes config to `/etc/rancher/k3s/k3s.yaml`
- User config at `~/.kube/config`
- `KUBECONFIG` env var overrides everything

### Fix
```bash
# Copy k3s config to user kubeconfig
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Or set KUBECONFIG
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Rename/migrate context if needed
kubectl config rename-context default homelab-local
```

## Issue: Stuck Terminating Pods

**Symptom**: Pods in `Terminating` state for minutes/hours.

**Cause**: The node the pod was running on is unreachable, so the kubelet can't confirm the container has been stopped.

**Fix**:
```bash
kubectl delete pod <pod> -n <ns> --force --grace-period=0
```

## Issue: etcd Quorum Loss

**Symptom**: `kubectl` commands time out. API server is unresponsive.

**Cause**: In an HA etcd cluster (odd number of nodes), more than half are offline. The remaining node can't achieve quorum.

**Fix**: Reinstall k3s as single-node:
```bash
/usr/local/bin/k3s-uninstall.sh
curl -sfL https://get.k3s.io | sh -s - server --cluster-init ...
```

## Quick Reference: Pod Status Meanings

| Status | Meaning | Action |
|--------|---------|--------|
| `Running` | Healthy | None |
| `CrashLoopBackOff` | Container crashes repeatedly | Check logs |
| `ImagePullBackOff` | Can't pull image | Check image name, registry access |
| `Pending` | Can't schedule | Check resources, node capacity, PVC binding |
| `Terminating` | Stuck shutting down | Force delete: `kubectl delete pod --force --grace-period=0` |
| `Error` | Container exited with error | Check logs |
| `Completed` | Job finished | Normal for Jobs/CronJobs |

## Prevention

1. **Single-node is simpler** — fewer failure modes than HA clusters
2. **Monitor node health** — Prometheus alerts for NodeNotReady
3. **Regular backups** — NFS PVCs survive node reinstall; local-path PVCs need separate backup
4. **Test restores** — verify backup integrity before you need it


=== docker-services.md ===
# Docker Services & Caddy Reverse Proxy

## Architecture

All Docker services run on burndev alongside the k3s cluster. Caddy is the unified edge proxy — it terminates TLS and routes to both Docker containers and K8s NodePorts.

```
Internet → OPNsense (192.168.1.1) → burndev (192.168.1.50)
                                       │
                                       ├── Caddy (host network, :80/:443)
                                       │   ├── *.burndev.lan → Docker services (127.0.0.1:<port>)
                                       │   └── *.homelab.lan → K8s NodePorts (127.0.0.1:30080-30086)
                                       │
                                       ├── Docker services (127.0.0.1 bound)
                                       └── k3s NodePorts
```

### Domain Trees

Two separate TLS certificate bundles:

| Domain Tree | Target | Services |
|-------------|--------|----------|
| `*.burndev.lan` | Docker | immich, jellyfin, sonarr, radarr, lidarr, prowlarr, qbit, actual, home, portainer, unifi |
| `*.homelab.lan` | K8s | home, trilium, termix, code, kanboard, omni, grafana |

## Service Inventory

| App | Domain | Port | Compose Location |
|-----|--------|------|-----------------|
| Immich | `immich.pve.lan` | 2283 | `docker/immich/` (pve-exu LXC 111) |
| Jellyfin | `burney.tv` | 8096 | `docker/jellyfin/` |
| Sonarr | `sonarr.burndev.lan` | 8989 | `docker/servarr/` |
| Radarr | `radarr.burndev.lan` | 7878 | `docker/servarr/` |
| Lidarr | `lidarr.burndev.lan` | 8686 | `docker/servarr/` |
| Prowlarr | `prowlarr.burndev.lan` | 9696 | `docker/servarr/` |
| qBittorrent | `qbit.burndev.lan` | 8889 | `docker/servarr/` (via gluetun VPN) |
| Actual Budget | `actual.burndev.lan` | 5006 | `docker/actual-budget/` |
| Homepage (Docker) | `home.burndev.lan` | 3000 | Docker compose on burndev |
| Vikunja | — (localhost only) | 3456 | `docker/vikunja/` |
| Scanopy | — (LAN-only) | 60072 | `docker/scanopy/` |
| Cannery | — (localhost only) | 4000 | `docker/cannery/` |
| RackPeek | — (localhost only) | 3001 | `docker/rackpeek/` |
| Portainer | `portainer.burndev.lan` | 9443 | Docker compose |
| UniFi | `unifi.burndev.lan` | 8443 | Docker compose |

## Caddy Configuration

- Location: `docker/caddy/compose.yaml`
- Caddyfile: `docker/caddy/Caddyfile`
- Network mode: `host` (must own ports 80/443 directly)
- Certificates: `docker/caddy/certs/` and `docker/caddy/data/`
- TLS: Caddy manages certificates automatically via Let's Encrypt or internal CA

### Caddy Verification

```bash
# Check Caddy is running
docker ps | grep caddy

# Watch Caddy logs
docker logs caddy -f

# Check TLS certs loaded
docker logs caddy 2>&1 | grep -i cert

# Validate Caddyfile
docker compose config --quiet

# Test routes
curl -k https://home.burndev.lan
curl -k https://home.homelab.lan
```

### Caddy Failure = All Routing Down

If Caddy fails, no service is reachable via domain names. Always fix Caddy first:
```bash
cd docker/caddy
docker compose down
# Fix Caddyfile or cert paths
docker compose config --quiet   # validate
docker compose up -d
docker logs caddy -f            # watch for errors
```

### K8s CA Certificate (for browser trust)

```bash
kubectl get secret homelab-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' \
  | base64 -d > homelab-ca.crt
```

## Docker Socket Proxy

Homepage auto-discovers Docker services through a read-only socket proxy at `192.168.1.50:2375`. See `docker/socket-proxy/compose.yaml`.

Homepage labels on compose services:
```yaml
labels:
  - homepage.group=Docker
  - homepage.name=Vikunja
  - homepage.href=http://192.168.1.50:3456
  - homepage.description=Task and project management
```

## Deploy Order

1. **Caddy first** — edge proxy must be running before anything else
2. Core services (Immich, Jellyfin, Actual Budget)
3. Arr stack (Sonarr, Radarr, Lidarr, Prowlarr, qBittorrent)
4. Tools (Vikunja, Scanopy, Portainer, etc.)

```bash
cd docker/caddy && docker compose up -d      # first
cd docker/immich && docker compose up -d
cd docker/jellyfin && docker compose up -d
# ... remaining stacks
```

Or use the Makefile:
```bash
make deploy-docker
```

## Port Binding Summary

| Bind Address | Ports | Purpose |
|-------------|-------|---------|
| `0.0.0.0` | 80, 443 | Caddy (host network) |
| `127.0.0.1` | 2283, 8096, 8989, 7878, 8686, 9696, 8889, 5006, 3000, 9443, 8443 | Docker services (Caddy proxies) |
| `127.0.0.1` | 30080-30086 | K8s NodePorts (Caddy proxies) |
| `192.168.1.50` | 2375 | Docker socket proxy (Homepage discovery) |
| `192.168.1.50` | 7359/udp | Jellyfin DLNA |
| `0.0.0.0` | 60072 | Scanopy device discovery |
| `0.0.0.0` | 32239 | qBittorrent peer ports |

## Docker Compose Patterns

### Services with databases

Some services (Vikunja, Scanopy) include their own PostgreSQL containers in the compose file. These are isolated per-stack — no shared database instances.

### Network_mode: host services

- **Caddy**: `network_mode: host` — must bind :80/:443
- **Scanopy daemon**: `network_mode: host` + `privileged: true` — LAN device discovery requires raw network access

### gluetun VPN (servarr stack)

qBittorrent routes through gluetun VPN container. WireGuard credentials must be in a `.env` file, NOT hardcoded in compose.yaml.


=== networking.md ===
# Networking & DNS

## Architecture Overview

```
Internet → OPNsense (192.168.1.1) → burndev (192.168.1.50)
                                        ├── Caddy (host network, :80/:443)
                                        │   ├── *.burndev.lan → Docker services (127.0.0.1:<port>)
                                        │   └── *.homelab.lan → K8s NodePorts (127.0.0.1:30080-30086)
                                        │
                                        └── k3s NodePorts (nginx-ingress vestigial; Caddy routes directly)
```

## DNS Resolution

### Internal resolution

Services use `*.burndev.lan` (Docker) and `*.homelab.lan` (Kubernetes). Both resolve to `192.168.1.50`.

### OPNsense Configuration

For internal clients to resolve homelab domains, add DNS overrides in OPNsense:

1. **Unbound DNS → Overrides → Host Overrides**
   - Host: `burndev`, Domain: `burndev.lan`, IP: `192.168.1.50`
   - Host: `*`, Domain: `burndev.lan`, IP: `192.168.1.50` (wildcard)
   - Host: `*`, Domain: `homelab.lan`, IP: `192.168.1.50` (wildcard)

2. **Hairpin NAT** (NAT reflection): Required for internal clients to reach services via the public/WAN IP. Enable in Firewall → Settings → Advanced → NAT Reflection mode for port forwards.

### Without hairpin NAT

Internal clients trying to reach `*.burndev.lan` or `*.homelab.lan` must resolve directly to `192.168.1.50`. If DNS resolves to the WAN IP and hairpin NAT isn't working, connections will fail.

## Caddy (Edge Proxy)

Caddy runs as a Docker container in `network_mode: host`, owning ports 80 and 443 directly. It terminates TLS for both domain trees using separate certificate bundles.

```
Docker services  → Caddy → 127.0.0.1:<docker-port>
K8s NodePorts    → Caddy → 127.0.0.1:30080-30086
```

Location: `docker/caddy/compose.yaml` and `docker/caddy/Caddyfile`

If Caddy fails, all external routing is down. Fix Caddy first before debugging backend services.

## Port Summary

| Port | Binding | Purpose |
|------|---------|---------|
| 80, 443 | `0.0.0.0` (via host network) | Caddy HTTP/HTTPS |
| 2375 | `192.168.1.50` | Docker socket proxy (Homepage discovery, read-only) |
| 2283 | `127.0.0.1` | Immich (Docker) |
| 8096 | `127.0.0.1` | Jellyfin (Docker) |
| 8989 | `127.0.0.1` | Sonarr |
| 7878 | `127.0.0.1` | Radarr |
| 8686 | `127.0.0.1` | Lidarr |
| 9696 | `127.0.0.1` | Prowlarr |
| 8889 | `127.0.0.1` | qBittorrent (via gluetun VPN) |
| 5006 | `127.0.0.1` | Actual Budget |
| 3000 | `127.0.0.1` | Homepage (Docker) |
| 3456 | `127.0.0.1` | Vikunja |
| 4000 | `127.0.0.1` | Cannery |
| 3001 | `127.0.0.1` | RackPeek |
| 9443 | `127.0.0.1` | Portainer |
| 8443 | `127.0.0.1` | UniFi |
| 60072 | `0.0.0.0` | Scanopy (LAN device discovery) |
| 7359/udp | `192.168.1.50` | Jellyfin DLNA |
| 32239 | `0.0.0.0` | qBittorrent peer port |
| 30080-30086 | NodePort | K8s services (Homepage K8s, Trilium, Termix, VS Code, Kanboard, Omni Tools, Grafana) |

## NetworkPolicy (Kubernetes)

Both `tools` and `monitoring` namespaces use **default-deny** ingress:

```yaml
# kubernetes/policies/tools/default-deny.yml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: tools
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

Allow rules:
- `allow-ingress.yml` — permits traffic from `ingress-nginx` namespace
- `allow-monitoring.yml` — permits traffic from `monitoring` namespace (Prometheus scraping)

Any new app in `tools` namespace must have an ingress allow rule or it will be unreachable.


=== storage.md ===
# Storage Architecture

## Storage Classes

Three storage classes are used across the cluster:

| Storage Class | Backend | Access Mode | Use Case |
|--------------|---------|-------------|----------|
| `nfs` | Synology NAS (192.168.1.11) via NFS provisioner | ReadWriteMany | Shared configs, code-server workspaces, Grafana dashboards, Kanboard data |
| `local-path` | Local node disk (/var/lib/rancher/k3s) | ReadWriteOnce | App data that doesn't need to survive node failure (termix sessions, trilium notes, immich postgres) |
| `immich-upload-manual` | Synology NAS (manual PV, `/volume1/immich`) | ReadWriteMany | Immich photo/video uploads |
| `""` (empty) | Manual NFS PV binding | ReadWriteMany | Homepage config/images (bound to specific NFS PVs) |

## NFS Provisioner

Automatically creates PVCs backed by the Synology NAS:
```bash
bash scripts/install-nfs-provisioner.sh
```

Default path: `/volume1/homelab/k8s/` on `192.168.1.11`

## Manual NFS PVs

Some services use manually-created PersistentVolumes pointing to specific NFS paths:

- **Homepage config**: `192.168.1.11:/volume1/homelab/k8s/homepage/config`
- **Homepage images**: `192.168.1.11:/volume1/homelab/k8s/homepage/images`
- **Immich uploads**: `192.168.1.11:/volume1/immich` (200Gi, Retain policy)

## PVC Naming & Migration Notes

During the Proxmox-to-bare-metal migration, PVCs using `proxmox-local` storage class were renamed and migrated to `local-path`:

| Old PVC | New PVC | Old SC | New SC |
|---------|---------|--------|--------|
| `termix-data-proxmox` | `termix-data` | `proxmox-local` | `local-path` |
| `trilium-data-proxmox` | `trilium-data` | `proxmox-local` | `local-path` |
| `immich-postgres-data` (unnamed rename) | `immich-postgres-data` | `proxmox-local` | `local-path` |

**Important**: Data on `local-path` PVCs lives on the node's disk. If k3s is uninstalled, this data is lost — ensure backups are in place.

## NAS Mount

The Synology NAS must be mounted at `/mnt/syn` on burndev:
```bash
mount 192.168.1.11:/volume1/homelab /mnt/syn
```

Add to `/etc/fstab` for persistence:
```
192.168.1.11:/volume1/homelab /mnt/syn nfs defaults 0 0
```

Verify:
```bash
mountpoint /mnt/syn && echo "OK" || echo "NOT MOUNTED"
```

## Data Survival on Cluster Wipe

| Storage Class | Survives `k3s-uninstall.sh`? |
|--------------|------------------------------|
| `nfs` (NFS provisioner) | ✅ Yes — data on NAS |
| `local-path` | ❌ No — data in `/var/lib/rancher/k3s` on node disk |
| Manual NFS PVs | ✅ Yes — data on NAS |
| Docker volumes (bind mounts) | ✅ Yes — in `/opt/docker/` |


=== monitoring.md ===
# Monitoring Stack

## Components

- **Prometheus**: Metrics collection and alerting (via kube-prometheus-stack Helm chart)
- **Grafana**: Dashboards and visualization
- **Blackbox Exporter**: ICMP ping and HTTP probe monitoring for external hosts
- **Alertmanager**: Alert routing (bundled with kube-prometheus-stack)

## Access

| Service | URL |
|---------|-----|
| Prometheus | `prometheus.homelab.lan` |
| Grafana | `grafana.homelab.lan` |
| Alertmanager | `alertmanager.homelab.lan` |

All use TLS certs from the internal CA.

## Installation

```bash
bash scripts/install-kube-prometheus-stack.sh
bash scripts/install-blackbox-exporter.sh
```

Note: `kubernetes/monitoring/blackbox-values.yml` and `kubernetes/monitoring/prometheus-additional-scrape.yml` are Helm values/config inputs, NOT standalone kubectl manifests.

## Monitoring Targets

### ICMP Ping (Blackbox Exporter)

Monitors core infrastructure:
- `192.168.1.1` — OPNsense gateway
- `192.168.1.50` — burndev
- `192.168.1.11` — Synology NAS

### OPNsense SNMP

- Target: `192.168.1.1:9273`
- Job: `opnsense`

## Alert Rules

Defined in `kubernetes/monitoring/alert-rules.yml`:

| Alert | Condition | Severity |
|-------|-----------|----------|
| NodeDown | `up{job="kubernetes-nodes"} == 0` for 5m | critical |
| HighCPUUsage | CPU > 90% for 10m | warning |
| HighMemoryUsage | Memory > 90% for 10m | warning |

## Grafana

### Provisioning

Grafana is provisioned via ConfigMaps:
- `grafana-datasources` — Prometheus datasource
- `grafana-dashboards-provider` — Dashboard provisioning config
- `grafana-config` — `grafana.ini` settings

### Homelab Overview Dashboard

Pre-configured dashboard (`homelab-overview`) with panels:
- Nodes Online/Offline (stat)
- Per-node CPU, memory, disk
- Refresh: 30s

### Storage

Grafana data (dashboards, users, preferences) stored on NFS PVC (`grafana-data`, 5Gi, `nfs` storage class).

## Prometheus Additional Scrape Config

File: `kubernetes/monitoring/prometheus-additional-scrape.yml`

Not a kubectl manifest — this is passed to the kube-prometheus-stack Helm chart as `prometheus.prometheusSpec.additionalScrapeConfigs`.

## NetworkPolicy

Monitoring namespace has default-deny ingress. Prometheus pods are not exposed via ingress from tools namespace — they're accessed through their own Ingress resources.


=== security.md ===
# Security & Secrets Management

Comprehensive security policies for the homelab — secrets management, network policies, TLS, git hygiene, and audit findings.

## Secrets Policy

**Never commit secrets to the repository.** All secrets are excluded via `.gitignore`.

### Secrets That Must Never Be Committed

| Category | Examples | Where They Live |
|---|---|---|
| SSH private keys | `id_ed25519_npburney_burndev`, deploy keys | `~/.ssh/` (not in repo) |
| TLS private keys | `*-key.pem`, `privkey.pem` | Docker volumes, not in repo |
| API keys / tokens | FACEIT_API_KEY, Cloudflare tokens | `.env` files (gitignored) |
| Database passwords | postgres, redis passwords | `.env` files or Docker secrets |
| WireGuard keys | private key, preshared key | `.env` files, never in compose.yaml |
| OAuth credentials | Google, Nest, GitHub tokens | `.storage/` (gitignored) |
| ACME account keys | Let's Encrypt account private keys | Docker volumes |
| HA auth database | `.storage/auth` | gitignored |
| Cloud auth tokens | Nabu Casa, cloud connections | `.cloud/` (gitignored) |

## Kubernetes Secrets

1. Copy the example file: `cp kubernetes/apps/immich-secret.example.yml kubernetes/apps/immich-secret.yml`
2. Edit with real values
3. Apply: `kubectl apply -f kubernetes/apps/immich-secret.yml`
4. The real secret file is gitignored (`*secret.yml`)

Available examples:
- `code-server-secret.example.yml` — `PASSWORD`, `SUDO_PASSWORD`
- `immich-secret.example.yml` — `DB_USERNAME`, `DB_PASSWORD`, `DB_DATABASE_NAME`

## Docker .env Files

1. Copy the example: `cp docker/vikunja/.env.example docker/vikunja/.env`
2. Edit with real values
3. `.env` is gitignored

## .gitignore Strategy

### Docker stacks

The homelab repo uses this pattern for Docker directories:

```gitignore
/docker/**
!/docker/**/
!/docker/**/compose.yaml
!/docker/**/.env.example
```

This ignores everything under `/docker/`, then selectively re-includes:
- Directory structure (`!/docker/**/`)
- Compose files (`compose.yaml`)
- Example env files (`.env.example`)

What's blocked: `.env` files, certs, ACME keys, data directories, and any other runtime artifacts under `/docker/`.

**However**: Compose files themselves must never contain secrets because they ARE included by this pattern. If a compose.yaml has hardcoded passwords or WireGuard keys, those secrets will be committed.

### Home Assistant config

See the [Home Assistant Git Backup](home-assistant-git-backup.md) guide for the HA-specific `.gitignore`.

### General rules

- Secrets go in `.env` files or environment variables, never in committed YAML/JSON/config files
- `.env.example` files should show the structure with placeholder values
- Actual `.env` files are gitignored
- Docker certs and data directories are gitignored via the `/docker/**` rule
- If in doubt, `git add -n <path>` to see what would be staged before committing

## NetworkPolicy (Default-Deny)

Both `tools` and `monitoring` namespaces default to denying all ingress:

```yaml
# kubernetes/policies/tools/default-deny.yml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: tools
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

Egress is intentionally **unrestricted** for DNS, metrics export, and API calls.

### Allow Rules

**tools namespace**:
- `allow-ingress.yml` — permits traffic from `ingress-nginx` namespace (allows web traffic to reach pods)
- `allow-monitoring.yml` — permits traffic from `monitoring` namespace (allows Prometheus scraping)

**monitoring namespace**:
- Only `default-deny.yml` — monitoring pods are not exposed via ingress in the tools namespace; Prometheus/Grafana are accessed through their own ingress resources.

Any new app in `tools` namespace must have an ingress allow rule or it will be unreachable.

## TLS

### Internal CA

cert-manager creates a self-signed CA (`homelab-ca`) using ECDSA P-256. All `*.homelab.lan` certs are issued by this CA:

```bash
kubectl apply -f kubernetes/cert-manager/ca-issuer.yml
```

Export CA cert for browser trust:
```bash
kubectl get secret homelab-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > homelab-ca.crt
```

### External (Caddy)

Caddy handles Let's Encrypt / ZeroSSL certificates for `*.burndev.lan`. Certificates are stored in `docker/caddy/data/` and `docker/caddy/certs/`.

## Docker Socket Proxy

Homepage discovers Docker services via a read-only socket proxy at `192.168.1.50:2375`:

```yaml
# docker/socket-proxy/compose.yaml
services:
  dockerproxy:
    image: ghcr.io/tecnativa/docker-socket-proxy:latest
    container_name: homepage-dockerproxy
    environment:
      CONTAINERS: 1   # Only allow container listing
      POST: 0         # Deny POST (mutations)
    ports:
      - "192.168.1.50:2375:2375"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
```

Key security properties:
- Binds to `192.168.1.50` only (not `0.0.0.0`) — LAN-only access
- `CONTAINERS: 1` — only allows listing containers (no exec, no create)
- `POST: 0` — denies all write operations
- Socket mounted read-only (`:ro`)

## Codebase Audit Findings (Historical)

Issues found during the initial homelab codebase audit that have been or should be addressed:

### CRITICAL: WireGuard keys in compose.yaml

`docker/servarr/compose.yaml` had hardcoded WireGuard private key, preshared key, and VPN address inside the gluetun service config. Since compose files ARE tracked by git, these would have been committed.

**Fix**: Move all secrets to a `.env` file in the servarr directory (which is gitignored by the `/docker/**` pattern).

### CRITICAL: TLS certificates and private keys

`docker/caddy/certs/` and `docker/caddy/data/caddy/acme/` contain TLS private keys and ACME account keys. These are properly gitignored by `/docker/**` but must never be explicitly added to git.

### HIGH: Default passwords in compose files

Some compose files had hardcoded passwords like `POSTGRES_PASSWORD=postgres` or `POSTGRES_PASSWORD=changeme`. While these are defaults, they should be externalized to `.env` files.

### HIGH: Identity exposure in configuration

`configuration.yaml` (Home Assistant) and similar config files contain:
- Mobile device names (e.g., `mobile_app_pixel_8_pro`)
- Entity names that reveal room layout
- Integration names indicating what services are running

For a public-facing repo: review and sanitize these. Consider using generic names instead of personal device names.

### MEDIUM: Third-party code licensing

Custom JavaScript files in `www/` (like `threedy-card.js`) should be verified for license compatibility if the repo is public. HACS-managed components (in `www/community/`) are auto-gitignored.

## Git Hygiene for Public Repos

### Before making a repo public

1. **Audit commit history** — secrets in old commits are still accessible:
   ```bash
   git log --all --full-history -- '**/secrets.yaml' '**/*-key.pem' '**/.env'
   ```
2. **If secrets found**: nuke history entirely (delete remote, re-init local, force-push clean history)
3. **Rotate all credentials** that were ever in the repo
4. **Verify `.gitignore`** by doing a dry-run:
   ```bash
   git add -n .   # what would be staged?
   ```

### Nuking git history

The only reliable way to guarantee secrets are gone:

```bash
# 1. Delete the GitHub repo via web UI
# 2. Remove local git history
rm -rf .git
# 3. Fresh init
git init
git add .
git commit -m "Initial clean commit"
# 4. Create new remote and push
git remote add origin <url>
git push -u origin main --force
```

Force-pushing an orphan branch keeps the repo URL but GitHub may retain old commits as dangling objects (accessible by hash) for days/weeks. Deleting and recreating the repo is safer.

### Ongoing safety

- `git add -u` not `git add -A` in automated scripts — never auto-stage new untracked files
- Periodically run `git status` to catch untracked files
- Review diffs before pushing: `git diff --cached`
- Use separate repos for public and private configs

## Terraform Secrets (deprecated, Proxmox removed)

The `terraform/` directory has been removed (Proxmox VMs no longer used). If reintroduced, pass API tokens via environment variables: `TF_VAR_proxmox_api_token`.


=== ssh-key-management.md ===
# SSH Key Management for Homelab

Patterns for managing SSH access across homelab servers, including Pi agent access and deploy keys for automated git operations.

## Current SSH Aliases

| Alias | Host | User | Key | Status |
|-------|------|------|-----|--------|
| `homeassistant` | `homeassistant.lan` | `root` | `~/.ssh/homeassistant_ed25519` | ✅ Working |
| `kws-rpi-1` | (Klipper printer) | — | — | Configured |
| `synology` | (NAS) | — | — | Server file exists, SSH not yet configured |

## Server Access Keys

Each server should have its own SSH key pair. Keys are stored in `~/.ssh/` with a naming convention:

```
~/.ssh/
├── id_ed25519_npburney_burndev              # default personal key
├── homeassistant_ed25519   # HA Pi
├── pi_agent_ed25519        # dedicated Pi agent key (least-privilege)
├── synology_ed25519        # NAS
└── ...
```

### Adding a new server

**Part 1: SSH Config (`~/.ssh/config`)**

Generate a key:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/<keyfile>_ed25519 -C "server-name" -N ""
```

Copy to server:
```bash
ssh-copy-id -i ~/.ssh/<keyfile>_ed25519 user@host
```

Add an SSH config entry:
```
Host <alias>
    HostName <hostname-or-ip>
    User <username>
    IdentityFile ~/.ssh/<keyfile>_ed25519
    IdentitiesOnly yes
```

Test:
```bash
ssh <alias> hostname
```

**Part 2: Homelab Inventory**

Create a server file at `~/.pi/agent/skills/homelab-inventory/references/servers/<alias>.md` following the format of existing files (see `burndev.md` or `synology.md`).

Then update `references/INDEX.md` with a lookup entry mapping user-facing terminology to the host alias.

### Key hardening

In SSH config entries:
- `IdentitiesOnly yes` — prevents ssh from trying all keys in the agent
- `StrictHostKeyChecking accept-new` — for automated connections

## Pi Agent Access

Per AGENTS.md policy, Pi should use a dedicated, least-privileged key.

### Current Pi SSH aliases

```
Host homeassistant
    HostName homeassistant.lan
    User root
    IdentityFile ~/.ssh/homeassistant_ed25519
```

The AGENTS.md recommends a separate key (`~/.ssh/pi_agent_ed25519`) specifically for Pi, distinct from personal keys. This provides:
- Audit trail (which connections came from Pi vs manual)
- Ability to revoke Pi access without affecting personal access
- Least privilege principle

## Deploy Keys (GitHub)

Deploy keys provide read/write access to a single GitHub repository without tying to a user account. Used for automated git push (e.g., HA config backups).

### Creating a deploy key

```bash
ssh-keygen -t ed25519 -C "description" -f /path/to/key -N ""
```

Add the public key to the repo:
GitHub → Repository → Settings → Deploy Keys → Add deploy key
Check "Allow write access" if the key needs to push.

### Deploy key gotchas

- A deploy key can only be used on **one** repository. If "Key is already in use", delete it from the old repo or generate a new key.
- Deploy keys survive repo deletion (they're tied to the key, not the repo).
- For Home Assistant: store the key inside `/config/.ssh/` so it persists across add-on restarts (the `/config` directory is mounted, not ephemeral).

## Home Assistant SSH Access

Home Assistant runs on a dedicated Pi (`homeassistant.lan`). SSH access goes through the **SSH add-on** (`core_ssh`), which provides an Alpine container with `/config` mounted.

```bash
ssh homeassistant
# Lands in /root (add-on container)
# /config is the HA config directory
```

The add-on's `authorized_keys` must include your public key. Configure in HA UI: **Settings → Add-ons → Terminal & SSH → Configuration → Authorized Keys**.

The add-on container is ephemeral — installed packages (like `git`, `crond`) must be re-installed after add-on restarts unless persisted via `init_commands`.

### Why SSH is needed (vs MCP tools)

The Home Assistant MCP tools operate through the REST/WebSocket API — they **cannot** read raw YAML files from the filesystem. For tasks like reading `automations.yaml` or `configuration.yaml`, SSH access is required.

| Tool | Server | What it can do |
|------|--------|---------------|
| `ha_config_get_automation` | ha-mcp | Get single automation config by entity_id |
| `ha_search` | ha-mcp | Search for automation entities |
| `ha_get_overview` | ha-mcp | System overview with entity listing |
| `GetLiveContext` | home-assistant | Real-time state of entities |
| `HassTurnOn`/`HassTurnOff` | home-assistant | Control devices |

### HA Filesystem Layout

Key paths inside the HA environment:

| Path | Contents |
|------|----------|
| `/config/automations.yaml` | Automation definitions |
| `/config/configuration.yaml` | Main HA configuration |
| `/config/scenes.yaml` | Scene definitions |
| `/config/scripts.yaml` | Script definitions |
| `/config/secrets.yaml` | Secrets (gitignored, not in repo) |
| `/config/.ssh/` | Deploy keys for git backup |
| `/config/backup.sh` | Auto-backup script (git push) |
| `/config/www/` | Web assets (HACS, custom cards) |

## Synology NAS

The Synology (192.168.1.11) is the primary backup destination. SSH access is not yet configured (as of last audit). To set up:

1. Enable SSH on Synology DSM (Control Panel → Terminal & SNMP)
2. Add public key to `/var/services/homes/<user>/.ssh/authorized_keys`
3. Add SSH config entry

## Best Practices

1. **One key per purpose** — don't reuse personal keys for automation
2. **Deploy keys for git** — more secure than personal access tokens
3. **`IdentitiesOnly yes`** — prevents ssh agent from trying wrong keys
4. **Rotate keys** after any suspected compromise (e.g., key accidentally pushed to a public repo)
5. **Audit `~/.ssh/authorized_keys`** on each server periodically
6. **Never commit private keys** — verify `.gitignore` covers `.ssh/` and any key directories


=== home-assistant-git-backup.md ===
# Home Assistant — Git Backup Configuration

Home Assistant configuration is backed up to a private GitHub repo at `github.com:BurneyProMod/homeassistant`.

## How It Works

A `backup.sh` script inside the HA environment auto-commits and pushes config changes. It runs via a cron job or HA automation (2am daily).

## Deploy Key

- Key file: `/config/.ssh/ha-git`
- SSH config uses `IdentitiesOnly=yes` and `StrictHostKeyChecking=accept-new`
- The deploy key must be added as a Deploy Key in the GitHub repo settings (Settings → Deploy Keys, with write access)

### Generating a Deploy Key

```bash
mkdir -p /config/.ssh
chmod 700 /config/.ssh
ssh-keygen -t ed25519 -C "ha-github-deploy" -f /config/.ssh/ha-github-deploy-key -N ""
```

### Deploy key gotchas

- A deploy key can only be used on **one** repository. If you see "Key is already in use", delete it from the old repo or generate a new key.
- Deploy keys survive repo deletion (they're tied to the key, not the repo).
- For Home Assistant: store the key inside `/config/.ssh/` so it persists across add-on restarts (the `/config` directory is mounted, not ephemeral).

## One-Time Setup Script (ha-git-init.sh)

Save as `/config/ha-git-init.sh` and run once to initialize git, SSH, and the cron job:

```bash
#!/bin/sh
apk add git openssh
mkdir -p ~/.ssh
cp /config/.ssh/ha-github-deploy-key ~/.ssh/
chmod 600 ~/.ssh/ha-github-deploy-key
cat > ~/.ssh/config << 'SSHEOF'
Host github.com
   HostName github.com
   User git
   IdentityFile ~/.ssh/ha-github-deploy-key
   IdentitiesOnly yes
   StrictHostKeyChecking accept-new
SSHEOF
chmod 600 ~/.ssh/config
cat > /etc/periodic/daily/ha-git-backup << 'CRONEOF'
#!/bin/sh
cd /config
git add -u
git commit -m "auto-backup $(date -Iseconds)" 2>&1 || true
git push origin main 2>&1 || true
CRONEOF
chmod +x /etc/periodic/daily/ha-git-backup
crond
```

Run once:
```bash
chmod +x /config/ha-git-init.sh
sh /config/ha-git-init.sh
```

## backup.sh (Fixed Version)

Key security fixes applied:

```bash
#!/bin/bash
set -eu

config_directory="/config"
ssh_directory="/config/.ssh"
deploy_key="${ssh_directory}/ha-git"
known_hosts="${ssh_directory}/known_hosts"

if [ ! -f "$deploy_key" ]; then
    echo "Deploy key not found: $deploy_key" >&2
    exit 1
fi

chmod 700 "$ssh_directory"
chmod 600 "$deploy_key"

export GIT_SSH_COMMAND="ssh -i $deploy_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts"

cd "$config_directory"

git config user.name "Home Assistant"
git config user.email "home-assistant@localhost"

# CRITICAL: Use 'git add -u' NOT 'git add -A'
# -u only stages modifications/deletions to already-tracked files
# -A would stage everything, risking accidental exposure of new files
git add -u

if git diff --cached --quiet; then
    echo "No configuration changes to back up."
    exit 0
fi

git commit -m "auto-backup $(date '+%Y-%m-%dT%H:%M:%S%z')"
git push origin master

echo "Home Assistant configuration pushed successfully."
```

## HA Automation for Daily Backup

### shell_command

Add to `configuration.yaml`:

```yaml
shell_command:
  backup: "sh /config/backup.sh"
```

### Automation

Add to `automations.yaml`:

```yaml
- id: "daily-backup"
  alias: Daily Backup
  description: "Backup Home Assistant configuration folder"
  trigger:
    - platform: time
      at: "02:00:00"
  condition: []
  action:
    - service: shell_command.backup
      data: {}
      response_variable: backup_response
    - if:
        - condition: template
          value_template: "{{ backup_response['returncode'] == 0 }}"
      then:
        - service: notify.notify
          data:
            title: Backup successful
            message: "{{ backup_response['stdout'] }}"
      else:
        - service: notify.notify
          data:
            title: Backup failed
            message: "{{ backup_response['stderr'] }}"
  mode: single
```

## .gitignore

Critical entries to prevent secret leakage:

```gitignore
# Secrets
secrets.yaml
.cloud/

# SSH keys
.ssh/

# Home Assistant runtime data
.storage/
.ha_mcp/
home-assistant_v2.db*
home-assistant.log*
*.db-shm
*.db-wal
backups/
tmp/

# Cache & transient files
.cache/
tts/
www/community/
zigbee.db*
.ha_run.lock
.HA_VERSION
.shopping_list.json
custom_components/

# Python
__pycache__/
*.pyc

# ESPHome (managed separately)
esphome/
```

## Tracked Files (Safe to Commit)

| File | Purpose |
|------|---------|
| `automations.yaml` | Automation definitions |
| `configuration.yaml` | Main HA configuration |
| `scenes.yaml` | Scene definitions |
| `scripts.yaml` | Script definitions |
| `ui-lovelace.yaml` | Dashboard layout |
| `backup.sh` | Auto-backup script |
| `blueprints/` | Automation/script blueprints |

## CRITICAL: Files That Must NEVER Be Public

| File | Content | Risk |
|------|---------|------|
| `.ssh/ha-github-deploy-key` | SSH private key | Repo push access |
| `.cloud/remote_private.pem` | TLS private key | Nabu Casa remote access |
| `.cloud/production_auth.json` | Cloud auth tokens | Nabu Casa account takeover |
| `.storage/auth` | User database (hashed pws, tokens) | Account compromise |
| `.storage/application_credentials` | OAuth app credentials | Google/Nest/API access |
| `.storage/http.auth` | API access tokens | HA API access |
| `.storage/auth.session` | Active session tokens | Session hijacking |
| `.storage/mobile_app` | Push tokens + device data | Push notification spam |
| `.storage/cloud` | Cloud connection tokens | Nabu Casa access |
| `.cache/nest/event_media/` | Nest camera snapshots | Privacy breach |
| `home-assistant_v2.db-*` | SQLite WAL files | Entity state history |
| `home-assistant.log*` | Log files | May contain IPs, entity names |

## Pre-Public Checklist

Before making the HA repo public:

1. **Revoke all deploy keys** on GitHub
2. **Rotate Nabu Casa remote certs** — the private key in `.cloud/remote_private.pem` is compromised if ever pushed
3. **Rotate Cloud auth** — delete `.cloud/production_auth.json` and re-authenticate
4. **Rotate all OAuth credentials** — Google, Nest, etc.
5. **Audit `configuration.yaml`** — remove/redact device names, notification targets, mobile device names
6. **Regenerate HA auth** — force all users to re-login
7. **Delete repo history entirely** (not just add to .gitignore):

### How to Completely Wipe Git History

```bash
# Option A: Delete and recreate repo (SAFEST)
# 1. Delete repo on GitHub (Settings → Delete this repository)
# 2. Locally:
cd /config
rm -rf .git
git init
git add .
git commit -m "Initial clean backup"
git remote add origin git@github.com:USER/REPO.git
git push -u origin main

# Option B: Orphan branch force-push (keeps repo URL, less safe)
git checkout --orphan clean
git add .
git commit -m "Clean public backup"
git push -u origin clean:main --force
```

**Why Option A is safer**: Once a secret is in git history, `.gitignore` won't protect it. GitHub may cache old commits accessible by direct hash for days/weeks even after force-push. Option A (delete + recreate) is the only guaranteed way.

## Security Checklist

- [x] `git add -u` not `git add -A` — prevents untracked files from being committed
- [x] `secrets.yaml` in `.gitignore` — API keys, passwords not exposed
- [x] `.storage/` in `.gitignore` — TLS certs, internal state not exposed
- [x] `.ssh/` in `.gitignore` — deploy keys not exposed
- [x] `.cloud/` in `.gitignore` — ACME account keys not exposed
- [x] Third-party HACS components in `www/community/` gitignored
- [x] Deploy key file matches the `backup.sh` reference (`ha-git`)
- [x] `backup.sh` has `set -eu` for early exit on errors

## History

- Repo URL: `git@github.com:BurneyProMod/homeassistant.git`
- Initial commit: Jul 16, 2026 — 12 files, 729 lines
- First commit author fix needed: `git config --global user.name/email` + `git commit --amend --reset-author`


=== home-assistant.md ===
# Home Assistant

## Setup & Access

- **URL**: `http://homeassistant.lan:8123`
- **SSH alias**: `homeassistant` → `homeassistant.lan` as root with key `~/.ssh/homeassistant_ed25519`
- **Version**: 2026.7.2 (as of July 2026)
- **MCP Server**: `ha-mcp` (27 tools) — connects through the MCP gateway

## MCP Tools Available

The `ha-mcp` server provides configuration management tools. Key capabilities:

### Read Operations
- `ha_mcp_ha_config_get_dashboard` — List dashboards, get config, search for cards
- `ha_mcp_ha_config_get_automation` — Retrieve automation config by entity_id or unique_id
- `ha_mcp_ha_search` — Search entities, automations, scripts, scenes, helpers, dashboard cards
- `ha_mcp_ha_get_overview` — System summary with entity counts, domain stats
- `ha_mcp_ha_get_entity` — Get detailed state and attributes of a specific entity
- `ha_mcp_ha_config_get_calendar_events` — Retrieve calendar events

### Write Operations
- `ha_mcp_ha_config_set_dashboard` — Create/update dashboards (config replacement or Python transforms)
- `ha_mcp_ha_config_set_automation` — Create/update automations
- `ha_mcp_ha_manage_config_entry` — Delete integration config entries
- `ha_mcp_ha_manage_helper` — Delete helpers (entities, automations, etc.)

## Dashboard Management

### Access

Dashboards are managed via the HA storage API:
```python
# Get a dashboard
ha_mcp_ha_config_get_dashboard(url_path="lovelace")

# List all dashboards
ha_mcp_ha_config_get_dashboard(list_only=True)
```

### Editing with Python Transforms (Recommended)

Python transforms are preferred over full config replacement for surgical edits:

```python
# Replace all cards in a view
config['views'][0]['cards'] = [...]

# Delete a specific card
del config['views'][0]['cards'][1]

# Add a card
config['views'][0]['cards'].append({...})
```

**Important**: After delete/add operations, indices shift. Always fetch a fresh `config_hash` before subsequent transforms.

### Dashboard Tips

- Use `grid` cards for layouts rather than manual CSS
- `square: true` for uniform icon grids (lights, person chips)
- `sections` view type for organization with headings
- Weather entities: `weather.forecast_burney_home`

## Stale Integration Cleanup

When integrations go offline, their config entries leave orphaned entities behind.

### Identifying stale entries
```python
# Check system logs
ha_mcp_ha_config_get_logs(source="system")

# Search for orphaned entities
ha_mcp_ha_get_orphaned_entities()
```

### Removing config entries
```python
ha_mcp_ha_manage_config_entry(action="delete", entry_id="...")
```

### Removing orphaned automations
```python
ha_mcp_ha_manage_helper(action="delete", target="automation.washing_machine_monitor_nfc_registration")
```

## Known Issues & Fixes

### Emporia Vue 3 Power Monitoring

When branch CTs are installed backwards, using `*pos` (positive-only) filter silently zeros out the readings. Use `*abs` (absolute value) instead to reveal hidden loads. Check circuit configuration in the Emporia Vue integration settings.

### Person Tracking (Companion App)

If person entities show `unknown`, the device tracker (phone) isn't sending GPS coordinates. Required on each phone:
1. Home Assistant Companion App installed
2. Location permission set to "Always allow"
3. Battery optimization disabled for the HA app

### Broken Custom Integrations

`hikvision_next` is incompatible with Python 3.14 due to `urllib3.contrib.appengine` removal. Keep if still partially functional, but expect entities to be unavailable.

### Stale Entities After Removal

Deleting a config entry does NOT automatically remove its entities. Run orphan detection after cleanup:
```python
ha_mcp_ha_get_orphaned_entities()
```

## Useful Automations (Template Ideas)

Based on available devices:

1. **Climate setback when away** — person entities leave → set thermostat to eco
2. **Motion-activated lights** — Aqara P1 motion → turn on room lights, turn off after N minutes
3. **Doorbell notification** — front/garage doorbell → TTS announcement on speakers
4. **Power anomaly alert** — Emporia Vue circuit > threshold → notification
5. **Printer complete notification** — moonraker print status → TTS/speaker announcement
6. **Leak detection alarm** — water sensor triggered → all speakers announce
7. **UPS power loss** — NUT sensor on battery → shutdown non-critical devices


=== home-assistant-energy-monitoring.md ===
# Home Assistant — Energy Monitoring (Emporia Vue 3)

Notes from setting up and troubleshooting an Emporia Vue 3 energy monitor via ESPHome in Home Assistant.

## Hardware

- **Device**: Emporia Vue 3 (16-circuit energy monitor)
- **Connection**: ESPHome firmware (replaces stock firmware)
- **Communication**: I2C between ESP32 and energy monitoring ICs
- **IP**: 192.168.1.139 (static, on LAN)

## ESPHome Configuration Tips

### CT Clamp Orientation

**Critical finding**: If CT clamps are installed backwards, the `*pos` filter will silently zero out the readings. Using `*abs` is safer for initial setup because it shows power regardless of clamp orientation.

```yaml
# Problem: Only shows positive power, zeroes out reversed clamps
filters:
  - &throttle_avg
    throttle_average: 5s
  - &pos
    lambda: return max(0.0f, x);

# Fix: Show absolute power (reveals backwards clamps)
filters:
  - &throttle_avg
    throttle_average: 5s
  - &abs
    lambda: return std::abs(x);
```

Once clamps are oriented correctly, switch back to `*pos` for accurate directional readings.

### YAML Anchors & Indentation

ESPHome YAML is sensitive to indentation. When using YAML anchors for shared filter chains, ensure each anchor is a separate list item, not nested:

```yaml
# ❌ WRONG — abs/invert/pos nested under throttle
.filters:
  - &throttle_avg
    throttle_average: 5s
    - &abs
      lambda: return std::abs(x);

# ✅ CORRECT — each anchor is a separate list item
.filters:
  - &throttle_avg
    throttle_average: 5s
  - &abs
    lambda: return std::abs(x);
```

### Logging & Debugging

ESPHome log levels for the emporia_vue component:

- `INFO` — connection status, I2C reads
- `DEBUG` — raw I2C hex bytes
- `VERBOSE` — full I2C transaction details

**Limitation**: The `emporia_vue` component does **not** log decoded CT values at any log level — only raw I2C bytes. This makes it hard to debug per-CT-port readings from logs alone.

To change log level for a specific component:

```yaml
logger:
  level: INFO
  logs:
    emporia_vue: DEBUG
    i2c: DEBUG
```

### Flashing & OTA

To pull device logs after flashing, use the ESPHome add-on in Home Assistant:
**Settings → Add-ons → ESPHome → (device) → Logs**

OTA updates are supported — no physical access needed after initial flash.

### Substitutions for Readability

Use substitutions to give circuits meaningful names:

```yaml
substitutions:
  display_name: "Emporia Vue 3"
  leg_1: "Phase R"
  leg_2: "Phase L"
  cir_1: "Furnace"
  cir_2: "Living Room"
  cir_3: "Kitchen"
  # ... etc
```

### 240V Appliances

Larger 240V appliances (HVAC, water heater, dryer, range, EV charger) may not have individual CT clamps if the panel's breaker layout doesn't accommodate 16+ clamps. These show up as the gap between the phase totals and the sum of monitored branch circuits:

```
Phase Total Power - Sum(Branch Circuit Power) = Unmonitored Load
```

## HA Entity Exposure

ESPHome entities are not automatically exposed to Assist. To make them available:

1. Go to **Settings → Voice Assistants → Assist**
2. Expose the ESPHome entities you want accessible via voice/Assist
3. Or use the `assist_pipeline` integration settings

## Useful Entities

After successful setup, the device exposes ~21 entities:
- Phase voltage (L, R)
- Phase power (L, R)  
- Total power
- Per-circuit power (1-16, depending on configuration)
- Daily energy (total and per-phase)
- Device status (RSSI, uptime, etc.)


=== home-assistant-integrations.md ===
# Home Assistant Integrations

Notes on specific integrations, their quirks, and setup details.

## Emporia Vue 3 (via ESPHome)

Whole-home energy monitoring with 8-16 circuit-level CT clamps.
Integrated through ESPHome (not the cloud-based Emporia integration).

### ESPHome Config Tips

- Use `substitutions` for leg/circuit friendly names — makes them reusable
  across the config
- The `total_power` and per-phase power sensors may read 0 if the mains CT
  clamps aren't properly mapped. Check that `power_sensor` IDs for legs
  are correctly referenced in the ESPHome YAML
- Entities must be **exposed to Assist** to be visible through the
  Home Assistant MCP tools. Go to Settings → Voice assistants → Expose

### ESPHome YAML structure

```yaml
esphome:
  name: emporiavue3
  friendly_name: "${display_name}"

substitutions:
  display_name: "Emporia Vue 3"
  leg_1: "Phase R"
  leg_2: "Phase L"
  cir_1: "Circuit 1"
  # ... cir_2 through cir_16
```

### Debugging ESPHome sensors

If sensors show unexpected values (e.g., per-circuit power works but
total/phase power reads 0):

1. Check ESPHome device logs in Home Assistant for warnings
2. Enable debug logging in the ESPHome device config:
   ```yaml
   logger:
     level: DEBUG
   ```
3. Validate CT clamp assignments — each circuit CT must be mapped to the
   correct phase (leg)

## HA-MCP Server

The Home Assistant Model Context Protocol integration (`ha-mcp`) enables
AI agents to query HA state and control devices through a structured API.

### Startup failure: Python 3.14 KeyError

**Symptom**: ha-mcp add-on fails to start with:
```
KeyError: '__editable__.homeassistant-2026.7.2.finder.__path_hook__'
```

**Root cause**: Home Assistant 2026.7.2 is installed in editable/development
mode on Python 3.14. The `importlib.invalidate_caches()` call in
`embedded_server.py` walks all registered finders and hits a KeyError on
an editable-install finder that's not fully registered.

**Fix**: The error is transient — retrying 5 minutes later typically works.
A permanent fix would require wrapping the `invalidate_caches()` call in
`try/except KeyError` in the ha-mcp source.

**Timeline example**:
- 16:41 — config entry re-added
- 21:30:28 — bring-up failed with KeyError
- 21:35:10 — bring-up succeeded (5 min later, after partial cache invalidation)

### MCP tool limitations

- MCP tools operate through HA's REST/WebSocket API — they cannot read
  raw YAML files from the filesystem
- To read files like `automations.yaml` or `configuration.yaml`, use SSH
  to the HA host instead
- Entities must be exposed to Assist to appear in MCP queries
- After adding entities to Assist, the MCP server may need a moment to
  refresh its entity cache

## Exposing Entities to Assist

Required for entities to be visible through MCP/voice:

1. Home Assistant → Settings → Voice assistants
2. Click "Expose" (or "Expose entities")
3. Find the entities you want to expose
4. Toggle them on

Entities not exposed to Assist are invisible to MCP queries even if they
exist and are active in Home Assistant.


=== home-assistant-management.md ===
# Home Assistant — Device & Integration Management

Best practices for managing Home Assistant devices, integrations, and dashboards based on real troubleshooting sessions.

## Removing Stale Devices & Integrations

### Identifying Stale Integrations

Check Home Assistant logs for recurring connection errors:

1. **Settings → System → Logs** — look for repeated connection failures
2. Common stale patterns:
   - `Error connecting to <ip>:<port>` — device unreachable
   - `Python <version> incompatibility` — integration needs update/removal
   - `Failed to set up` / `Setup failed` — integration config broken

### Safe Removal Process

```yaml
# In configuration.yaml, remove or comment out the integration
# Then restart HA: Settings → System → Restart
```

Or use the UI: **Settings → Devices & Services → (integration) → ⋮ → Delete**

**Note**: When removing devices, choose **"Delete"** rather than "Ignore" so that the device can be re-discovered later if it comes back online.

### Example Session: Cleaned Integrations

| Integration | Issue | Action |
|---|---|---|
| Pi-hole (`192.168.1.2`) | Unreachable, can't connect or determine API version | Removed |
| hikvision_next | Python 3.14 incompatibility | Kept (pending update) |
| Sovol SV08 (moonraker) | Printer no longer in use | Removed |
| Additional stale device | No longer present | Removed |

## Dashboard Management

### Dashboard Types

Home Assistant supports two dashboard storage modes:

1. **UI-created** — stored in `.storage/lovelace*`, managed through the HA UI
2. **YAML-defined** — declared in `configuration.yaml` via `lovelace:` key, or in separate YAML files

UI-created dashboards show up in the API and can be read by MCP tools. YAML-defined dashboards may not show up in API queries.

### Reading Dashboards

The HA MCP (`ha-mcp` server) can read dashboards created through the UI:
- `ha_get_dashboard` — get dashboard configuration
- `ha_get_overview` — system overview including dashboard list

**Limitation**: Dashboards defined in YAML (`configuration.yaml` or `ui-lovelace.yaml`) may not appear in API results. Full filesystem access (SSH) is needed to read those.

### Editing Dashboards

The MCP tools **cannot** edit dashboards. Options:
1. **HA UI** — drag-and-drop editor at `http://<ha-ip>:8123`
2. **Manual YAML** — edit `ui-lovelace.yaml` or the raw config via SSH
3. **API** — POST to `/api/lovelace/config` with a long-lived access token

## Automation Design

When designing automations, consider:

1. **Triggers** — what starts the automation (state change, time, event, MQTT)
2. **Conditions** — when should it NOT run (time range, state checks, presence)
3. **Actions** — what to do (notify, control devices, call services)

### Useful Automation Patterns

| Pattern | Example |
|---|---|
| Motion → Light | Motion sensor triggers lights, auto-off after N minutes |
| Package Delivery → Notification | Mail sensor change → phone notification |
| Door/Window → Alert | Contact sensor open while away → notification |
| Device Offline → Alert | Integration unavailable → notification |
| Time-based | Turn off all lights at midnight |
| Presence-based | Away mode when all phones leave |

### Automation Tips

- Set `mode: single` for most automations (prevents parallel runs)
- Use `initial_state: true` to ensure automations are enabled on restart
- Test with **Run** button in UI before relying on triggers
- Check logs after HA restart for automation setup errors

## Entity Management

### Finding Entities

```yaml
# In configuration.yaml, get the full entity list via:
# Settings → Devices & Services → Entities
```

Or use MCP: `GetLiveContext` with domain filter, or `ha_mcp_ha_get_overview`.

### Entity Naming Convention

Entities exposed to Assist need friendly names. Rename in:
**Settings → Devices & Services → Entities → (entity) → ⋮ → Rename**

### Troubleshooting Unknown Entities

| Cause | Fix |
|---|---|
| Device offline | Check device power/network |
| Integration removed | Re-add integration |
| Companion app killed | Disable battery optimization for HA app |
| GPS permission denied | Grant "Always" location permission |
| Entity renamed | Update all references (automations, scripts, dashboards) |


=== pi-agent-setup.md ===
# Pi Coding Agent — Setup & Configuration

How Pi is configured for the homelab environment, including AGENTS.md policies, skills, and session management.

## Session Storage

Pi stores all chat sessions as JSONL files at:

```
~/.pi/agent/sessions/
```

Organization: sessions are grouped into subdirectories by working directory (CWD):

| Directory | CWD |
|-----------|-----|
| `--home-npburney--/` | `~` (home directory) |
| `--home-npburney-dev--/` | `~/dev` |
| `--home-npburney-dev-homelab--/` | `~/dev/homelab` |
| `--home-npburney-dev-homelab-docker-caddy--/` | `~/dev/homelab/docker/caddy` |
| `--home-npburney-dev-statclock--/` | `~/dev/statclock` |

### Session File Format

Each file is a JSONL (one JSON object per line) with these types:

| type | Description |
|------|-------------|
| `session` | Session metadata (id, timestamp, cwd) |
| `model_change` | Model/provider selection |
| `thinking_level_change` | Thinking level setting |
| `message` | User/assistant/tool messages |

### Session Commands

| Command | Action |
|---------|--------|
| `/session` | Show current session (file, ID, tokens, cost) |
| `/resume` | Pick from previous sessions |
| `/new` | Start new session |
| `/name <name>` | Set session display name |
| `/fork` | Create new session from a past message |
| `/clone` | Duplicate current branch to new session |
| `/export [file]` | Export to HTML or JSONL |
| `/import <file>` | Resume from exported JSONL |
| `/tree` | Jump to any point in session history |

## AGENTS.md Configuration

Location: `~/.pi/agent/AGENTS.md`

Key policies:

### Vikunja
- Vikunja is the source of truth for projects and chores
- Read/analyze freely; no mutations without explicit request

### Homelab Change Policy
- All state-changing homelab actions require explicit confirmation
- Must identify exact host, service, environment before acting
- Must show exact command, expected effect, and rollback plan

### Homelab Inventory
- Load `homelab-inventory` skill before any homelab work
- Treat inventory as reference; verify live state read-only

### Diagnosis vs Implementation
- Read-only investigation only for inspection/diagnosis requests
- Separate evidence, inference, recommendation, and action

## Skills Directory

Skills are loaded from two locations:

1. `~/.pi/agent/skills/` — Private skills (homelab-inventory)
2. `~/dev/.pi/skills/pi-skills/` — Shared skills (brave-search, browser-tools, gccli, gdcli, gmcli, transcribe, vscode, youtube-transcript)

### Available Skills

| Skill | Purpose |
|-------|---------|
| `homelab-inventory` | Maps hosts, services, storage, backups, dependencies |
| `brave-search` | Web search and content extraction |
| `browser-tools` | Interactive browser automation via CDP |
| `gccli` | Google Calendar CLI |
| `gdcli` | Google Drive CLI |
| `gmcli` | Gmail CLI |
| `transcribe` | Local speech-to-text (Apple Silicon) |
| `vscode` | VS Code diff viewing |
| `youtube-transcript` | YouTube transcript fetching |

## MCP Servers

Connected MCP servers:

| Server | Tools | Purpose |
|--------|-------|---------|
| `vikunja` | 53 | Task/project management |
| `ha-mcp` | 27 | Home Assistant API access |

### Vikunja MCP Notes
- CSV import supported for bulk task creation
- See `vikunja-import.csv` in the homelab repo

### Home Assistant MCP Notes
- Cannot read raw filesystem files (no YAML file access)
- Can read entity state, control devices, get automation config by entity_id
- For filesystem access, SSH is needed (see [ssh-key-management.md](ssh-key-management.md))

## Models

Default model: DeepSeek v4 Pro (high thinking)

Fast forks (mechanical tasks) use lower effort. The AGENTS.md routes:
- Fast forks for narrow, mechanical, read-only tasks
- Balanced/deep for architecture, security, implementation
- Parent agent owns clarification, coordination, final review


=== vikunja-csv-import.md ===
# Vikunja CSV Import Format

How to generate a Vikunja-compatible CSV for bulk import of projects and tasks.

## CSV Format

```csv
title,description,project_title,priority,labels,due_date,done
```

### Columns

| Column | Required | Description |
|--------|----------|-------------|
| `title` | Yes | Task title |
| `description` | No | Task description (Markdown supported, can include URLs) |
| `project_title` | No | Project name — tasks with the same project_title are grouped. If empty, task goes to "Inbox" |
| `priority` | No | 0=None, 1=Low, 2=Medium, 3=High, 4=Urgent |
| `labels` | No | Comma-separated label names |
| `due_date` | No | Format: `YYYY-MM-DD` |
| `done` | No | `true` or `false` (default: false) |

## Example

```csv
title,description,project_title,priority,labels,due_date,done
Set up QoS on router,[Guide link](https://example.com/qos),Homelab Infrastructure,3,networking,,
Configure DNS filtering,"[Article 1](https://example.com/dns1) [Article 2](https://example.com/dns2)",Homelab Infrastructure,4,networking,dns,,
Research ESP32 smart home,https://example.com/esp32,Home Automation,2,esp32,hardware,,
```

## Usage

1. Create the CSV file
2. In Vikunja, go to project list → Import
3. Select the CSV file
4. Vikunja will:
   - Create projects for any `project_title` values that don't exist
   - Create tasks under those projects
   - Set priority, labels, and due dates as specified

## Notes

- Multiple URLs in description: Use Markdown links or plain URLs
- One task can have multiple links if there's enough topic overlap
- Tasks without a `project_title` go to the default "Inbox" project
- Labels are created automatically if they don't exist
- The import is additive — it won't delete existing tasks

## Scripting Bulk Import

Since Vikunja's CSV import only supports tasks (not nested subtasks or bucket assignment), for more complex imports use the Vikunja API directly. A generated CSV at `~/dev/homelab/vikunja-import.csv` contains ~298 tasks across 14 projects organized from saved bookmarks.


=== vikunja-management.md ===
# Vikunja Task Management

Vikunja is the source of truth for projects and chores.

## Access

- URL: `http://localhost:3456` (Docker, no public route — per AGENTS.md)
- The agent may read and analyze Vikunja freely but must not create, edit, move, complete, archive, or delete anything without explicit request.

## CSV Import Format

Vikunja accepts CSV imports with these columns:

```csv
title,description,project_title,priority,labels,due_date,done
```

| Column | Required | Description |
|--------|----------|-------------|
| `title` | Yes | Task title |
| `description` | No | Task description (Markdown supported, can include URLs) |
| `project_title` | No | Project name — tasks with the same project_title are grouped. Empty = Inbox |
| `priority` | No | 0=None, 1=Low, 2=Medium, 3=High, 4=Urgent, 5=DO NOT USE (see note) |
| `labels` | No | Comma-separated label names (auto-created if new) |
| `due_date` | No | Format: `YYYY-MM-DD` |
| `done` | No | `true` or `false` (default: false) |

> **Priority note**: The Vikunja API scales 0–4 (0=None, 4=Urgent). The CSV import may accept 1–5 mapping. Test with a small import first. If Vikunja rejects priority=0 in CSV, use 1–5 scale (1=Lowest, 5=Highest).

### Example CSV

```csv
title,description,project_title,priority,labels,due_date,done
Set up QoS on router,[Guide link](https://example.com/qos),Homelab Infrastructure,2,networking,,
Configure DNS filtering,"[Article 1](https://example.com/dns1) [Article 2](https://example.com/dns2)",Homelab Infrastructure,3,"networking,dns",,
Research ESP32 smart home,https://example.com/esp32,Home Automation,1,"esp32,hardware",,
```

### Usage

1. Create the CSV file
2. In Vikunja, go to project list → Import
3. Select the CSV file
4. Vikunja auto-creates projects/labels that don't exist
5. Tasks without `project_title` go to "Inbox"
6. Import is additive — never deletes existing tasks

### Bulk Import

A generated CSV at `~/dev/homelab/vikunja-import.csv` contains ~298 tasks across 14 projects organized from saved bookmarks. For complex imports (nested subtasks, bucket assignment), use the Vikunja API directly.

### Best Practices for Import CSVs

1. **Use broad projects, narrow tags** — Instead of "3D Printing - Voron", "3D Printing - SV08", use one "3D Printing" project with `voron`, `sv08`, `prusa` tags. Same for "Homelab" with `network`, `docker`, `kubernetes`, `monitoring`, etc.

2. **Merge overlapping links** — Multiple bookmarks on the same topic → one task with multiple links in the description.

3. **Use priority for triage, labels for complexity** — e.g., `complexity-3`, `complexity-5`, `complexity-8` as labels. Priority (1-3) is for urgency.

4. **Avoid over-splitting** — Before creating a project, ask: "Would this be better as a tag under an existing project?" Two tasks under "3D Printing" with `voron` and `sv08` tags is better than two separate projects.

## Project Organization (Current)

| Project | Typical Tags |
|---------|-------------|
| Homelab | network, docker, kubernetes, monitoring, automation, dashboard, proxmox, storage, security, auth, media, home-automation, ai |
| 3D Printing | sv08, voron, prusa, filament, slicer, calibration |
| Projects & Making | hardware, project, dev-tools, electronics |
| Tools & Utilities | dev-tools, windows, linux, cli |
| Reading & Learning | personal, dev-tools, reference |
| Shopping | shopping |
| Gaming | gaming |
| Media | watching, reading |


=== statclock.md ===
# StatClock — ESP32 CS2 Stat Tracking Display

A CS2 stat-tracking display that fetches player stats from the FACEIT API (and eventually Leetify/Twitch) and shows them on a physical ESP32-driven display.

Repository: `~/dev/statclock/`

## Architecture

```
┌─────────────┐     FACEIT API      ┌──────────────┐
│  Go CLI     │ ◄────────────────── │  open.faceit  │
│  (main.go)  │                     │  .com/data/v4 │
└──────┬──────┘                     └──────────────┘
       │ stdout (ELO, matches, etc.)
       ▼
┌─────────────┐
│  ESP32-C3   │  ◄── ESPHome (esp32.yaml)
│  Display     │
└─────────────┘
```

## Project Structure

| Path | Purpose |
|------|---------|
| `main.go` | Go CLI — fetches FACEIT data (ELO, matches, account age, win/loss) |
| `leetify.go` | Go data models for Leetify API (not yet wired up) |
| `esp32.yaml` | ESPHome top-level config — selects display profile |
| `display/` | Display profiles: `max7219_7seg.yaml`, `max7219_dotmat.yaml`, `tm1637.yaml` |
| `images/` | Showcase photos |
| `.env.example` | Template for API keys |

## Setup

### Prerequisites

```bash
# For Go CLI
sudo apt install -y golang

# For ESPHome / ESP32 flashing
sudo apt install -y pipx
pipx install esphome
```

### Go CLI

```bash
cd ~/dev/statclock

# Initialize module (if go.mod doesn't exist)
go mod init statclock
go mod tidy

# Set up API credentials
cp .env.example .env
# Edit .env with your FACEIT API key and nickname

# Run checks
go vet ./...
go build ./...

# Query stats
go run . -metric elo        # Current ELO
go run . -metric matches    # Total matches
go run . -metric age        # Account age in days
go run . -metric wl         # Win/Loss
```

### ESP32 Flashing

```bash
# Validate config
esphome config esp32.yaml

# Compile check (no flash)
esphome compile esp32.yaml

# Flash to ESP32
esphome run esp32.yaml
```

## Display Profiles

Edit `esp32.yaml` line: `substitutions.display_profile: <profile>`

| Profile | Display Type | File |
|---------|-------------|------|
| `max7219_7seg` | MAX7219 8-digit 7-segment | `display/max7219_7seg.yaml` |
| `max7219_dotmat` | MAX7219 32x8 dot matrix | `display/max7219_dotmat.yaml` |
| `tm1637` | TM1637 4-digit | `display/tm1637.yaml` |

### Wiring (MAX7219)

| ESP32 GPIO | MAX7219 Pin |
|-----------|-------------|
| GPIO4 (MOSI) | DIN |
| GPIO5 (SCLK) | CLK |
| GPIO6 | CS |
| 3V3/5V | VCC |
| GND | GND |

### Wiring (TM1637)

| ESP32 GPIO | TM1637 Pin |
|-----------|------------|
| GPIO4 | DIO |
| GPIO5 | CLK |
| 3V3/5V | VCC |
| GND | GND |

## FACEIT API

- API base: `https://open.faceit.com/data/v4`
- Auth: Bearer token in `FACEIT_API_KEY`
- Endpoints used:
  - `GET /players?nickname=...&game=cs2` — player lookup
  - `GET /players/{player_id}/stats/cs2` — detailed stats

## TODO (from README)

- Fix font scaling / look into different displays
- Store local variables in SQLite
- Display extended FaceIT stats
- Leetify API integration
- Twitch API integration
- Edit case .stl to fit under 3D Printed AWP Asiimov

## Environment Variables

```bash
FACEIT_API_KEY=your_key_here       # Required
FACEIT_NICKNAME=username_here      # Required (or FACEIT_NAME)
FACEIT_GAME=cs2                    # Default: cs2
FACEIT_METRIC=elo                  # Default: elo
```


=== best-practices.md ===
# Homelab Best Practices

## Repository Structure

```
~/dev/homelab/
├── AGENTS.md              # AI agent instructions (deployment order, secrets, gotchas)
├── README.md              # Human-readable overview
├── Makefile               # Common operations (deploy, validate)
├── ansible/               # K3s bootstrap playbooks
│   ├── inventory/
│   │   ├── hosts.ini       # Server inventory (burndev only)
│   │   ├── group_vars/     # Global vars (k3s_version, ansible_user)
│   │   └── host_vars/      # Per-host overrides
│   ├── roles/
│   │   ├── common/         # Kernel modules, sysctl, UFW, packages
│   │   ├── control_plane/  # K3s server install
│   │   └── worker/         # K3s agent install (preserved for future scale-out)
│   └── site.yml            # Top-level playbook
├── config/homepage/        # Homepage dashboard config (synced to NAS)
├── docker/                 # Per-service Docker compose stacks
│   ├── caddy/              # Edge proxy (deploy FIRST)
│   ├── immich/             # Photo backup
│   ├── jellyfin/           # Media server
│   ├── servarr/            # Sonarr/Radarr/Lidarr/Prowlarr/qBittorrent
│   ├── actual-budget/      # Budgeting
│   ├── vikunja/            # Task management
│   ├── scanopy/            # Network device discovery
│   ├── cannery/            # Pantry management
│   ├── rackpeek/           # Server monitoring
│   └── socket-proxy/       # Docker API proxy for Homepage
├── kubernetes/
│   ├── apps/               # K8s app manifests (Deployments, Services, Ingresses)
│   ├── cert-manager/       # CA issuer + install script
│   ├── monitoring/         # Grafana, Prometheus rules, Blackbox config
│   ├── namespaces/         # Namespace definitions
│   └── policies/           # NetworkPolicy (default-deny per namespace)
├── scripts/
│   ├── backup.sh           # Rsync repo to NAS
│   ├── sync-homepage.sh    # Sync homepage config to NAS NFS share
│   └── deploy-k8s.sh       # Apply all K8s manifests in order
└── docs/                   # This documentation
```

## Git Hygiene

### What to commit
- All YAML manifests, playbooks, scripts, configs
- Example secret files (`*secret.example.yml`, `.env.example`)
- Documentation

### What NEVER to commit
- `.env` files (real secrets)
- `*secret.yml` (real K8s secrets)
- `*.pem`, `*.key`, `.crt` (TLS private keys)
- `*.log` (log files)
- Docker volume data (in `docker/*/data/`, `docker/*/config/`)
- Terraform `.tfstate`, `.tfvars` (if reintroduced)

### Docker directory whitelist

`.gitignore` uses an inverse pattern — everything under `docker/` is ignored EXCEPT `compose.yaml` and `.env.example`:

```gitignore
/docker/**
!/docker/**/
!/docker/**/compose.yaml
!/docker/**/.env.example
```

This prevents accidental commits of large volume data (Jellyfin cache, Sonarr media covers, Immich database).

## Deployment Order

**Strictly ordered. Each step depends on the previous.**

1. **K3s bootstrap**: `ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml`
2. **Cert-manager**: `bash kubernetes/cert-manager/install-cert-manager.sh && kubectl apply -f kubernetes/cert-manager/ca-issuer.yml`
3. **nginx-ingress**: `kubectl apply -f <nginx-ingress-manifest-url>`
4. **K8s manifests**: namespaces → policies → apps → monitoring
5. **Caddy (Docker)**: `cd docker/caddy && docker compose up -d`
6. **Remaining Docker stacks**: Immich, Jellyfin, arr stack, tools

## Troubleshooting Order

When something breaks, investigate in this order:

1. **Caddy** — if edge proxy is down, nothing routes
2. **DNS** — verify `*.burndev.lan` and `*.homelab.lan` resolve to `192.168.1.50`
3. **NAS mount** — NFS being down breaks all NFS-backed PVCs
4. **K3s** — `kubectl get nodes`, check if API server is responding
5. **nginx-ingress** — `kubectl -n ingress-nginx get pods`
6. **cert-manager** — certificate renewal failures show as TLS errors

## Common Gotchas

### nginx-ingress not installed
Symptom: All Ingress resources fail with webhook errors.
Fix: Install nginx-ingress (k3s disabled Traefik, doesn't include nginx).

### Wrong ansible_user
Symptom: `Permission denied (publickey,password)` for `debian@192.168.1.50`.
Fix: Change `ansible_user: npburney` and `ansible_connection: local` when running on burndev itself.

### prometheus scrape configs applied with kubectl
Symptom: YAML parse errors on `blackbox-values.yml` or `prometheus-additional-scrape.yml`.
Fix: These are Helm inputs, not manifests. They're consumed by the kube-prometheus-stack chart.

### Storage class mismatch
Symptom: PVCs stuck in Pending after migrating from Proxmox.
Fix: Old `proxmox-local` PVCs were renamed to use `local-path` or `nfs`. Verify storage classes exist: `kubectl get storageclass`.

### DNS hairpin
Symptom: Internal clients can't reach homelab services by domain.
Fix: Enable NAT reflection in OPNsense, or ensure internal DNS resolves directly to `192.168.1.50`.

## AI Agent Conventions (AGENTS.md)

The `AGENTS.md` file at the repo root governs AI agent behavior:

- **Vikunja**: Read-only by default; mutations require explicit request
- **Secrets**: Never commit; use example files
- **Deployment**: Strictly ordered; must follow sequence
- **Homelab inventory**: Load skill before homelab operations
- **Context**: Use explicit `--context default` for all kubectl commands targeting burndev
- **Architecture**: burndev is single-node k3s + Docker; no Proxmox VMs


