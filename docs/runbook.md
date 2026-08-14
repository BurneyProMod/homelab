# Recovery Runbook


> **Status: historical.** This runbook documents the decommissioned burndev single-node deployment. Workloads now run on the Proxmox cluster — see [proxmox-cluster.md](proxmox-cluster.md) for the current topology, [service-inventory.md](service-inventory.md) for live services, and [backup-layout.md](backup-layout.md) for backup/restore destinations. vzdump restores are done via the Proxmox UI.
>
> Surviving burndev roles: NFS media share, Ollama, central rsyslog listener, and the homelab repo mirror (backup.sh).

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
