# Homelab

Configuration-as-code for the Burney homelab. This repository is the **single
source of truth** for the environment — Proxmox, k3s, Docker Compose stacks,
Caddy, and secrets policy. The canonical copy lives on the Synology NAS
(`/volume1/homelab/repo`, mounted on `pve-core` at
`/mnt/synology/homelab/repo`) and mirrors to GitHub (`BurneyProMod/homelab`).

Status: P0 reconcile complete (repo matches live state, 2026-08-11). Commit-to-
live automation is planned — see [docs/gitops-plan.md](docs/gitops-plan.md).

## Architecture

```
Internet → OPNsense (192.168.1.1)
             │
        keepalived VIP 192.168.1.10  (*.burney.network, HA Caddy pair LXC 103/101)
             │
   ┌─────────┼──────────────────────────┐
   │         │                          │
 Proxmox cluster            Docker LXCs            K3s cluster (3 VMs)
 pve-core .30               (per-service LXCs)     k3s-core .70, k3s-exu .71,
 pve-gpu  .32                                    k3s-gpu .72 (NodePorts 30080+)
 pve-exu  .31
```

| Host | IP | Role |
|------|----|------|
| OPNsense | 192.168.1.1 | Gateway, firewall, DNS, DHCP |
| Synology NAS | 192.168.1.11 | NFS storage (`/volume1/homelab`), critical backups |
| pve-core | 192.168.1.30 | Proxmox host; hub (repo mount, Caddy LXC 103, SSO LXCs) |
| pve-gpu | 192.168.1.32 | Proxmox host; Jellyfin/VA-API, Servarr stack, Caddy LXC 101 |
| pve-exu | 192.168.1.31 | Proxmox host; Immich, Vikunja, Karakeep, Paperless, Stash, Scrutiny |
| burndev | 192.168.1.50 | Local LLM (Ollama), `burntv` NFS media share (mergerfs pool) |
| k3s-core / k3s-exu / k3s-gpu | .70 / .71 / .72 | 3-node k3s (all control-plane, `local-path` storage) |
| kwsdisplay | 192.168.1.168 | Rack kiosk: Prometheus, Grafana, Loki, blackbox |
| kws-rpi-1 | — | UniFi Controller |
| homeassistant | — | Home Assistant, ESPHome, Zigbee |

Auth: lldap (LXC 110) → Authentik (LXC 118, `auth.burney.network`) → OIDC +
forward-auth on Caddy. All public sites use `*.burney.network`.

## Repo layout

```
config/        Caddy (HA pair, VIP, certs via step-ca / Cloudflare DNS-01), step-ca
docker/        One dir per Compose stack: compose.yaml + .env.example (real .env is gitignored)
kubernetes/    k3s manifests: apps/, namespaces/, policies/
docs/          Knowledge base (runbook, service inventory, networking, gitops plan)
docs/archive/  Retired layers kept for reference: ansible, kube-monitoring, cert-manager, old apps
scripts/       deploy-k8s, validate, create-secrets, backup/restore, check-k8s
secrets/       homelab.env (gitignored) + homelab.env.example
Makefile       Common operations (validate, deploy-k8s, deploy-docker, backup, restore)
```

## Services

Full inventory with hosts and URLs: [docs/service-inventory.md](docs/service-inventory.md).

### Kubernetes (k3s, NodePorts)

| App | NodePort | Description |
|-----|----------|-------------|
| Trilium | 30081 | Notes |
| code-server | 30082 | Browser IDE |
| Kanboard | 30083 | Kanban |
| Omni-Tools | 30084 | Utility suite |
| Homarr | 30085 | Dashboard (`home.burney.network`) |
| Homebox | 30086 | Inventory |
| Manyfold | 30087 | 3D models |
| Changedetection | 30088 | Website change alerts |
| kube-state-metrics | 30100 | Cluster metrics for kwsdisplay Prometheus |

### Docker / LXCs

Media (pve-gpu): Jellyfin, Sonarr, Radarr, Lidarr, Prowlarr, qBittorrent.
Apps (pve-exu): Immich, Vikunja, RackPeek, Actual Budget, Karakeep, Paperless-ngx, Stash, Scrutiny, Tasks.md.
Apps (pve-core): LLDAP, OpenBao, FileBrowser Quantum, Scanopy, Authentik.
Edge: HA Caddy pair (103/101). The repo `docker/` dirs hold the compose definitions
(plus `.env.example`); runtime `.env` files stay on the hosts, gitignored.

Monitoring runs on kwsdisplay (Docker Compose), scraping k3s via
kube-state-metrics and LAN targets via blackbox. See [docs/monitoring.md](docs/monitoring.md).

## Quick start (operating)

All commands run from the canonical repo on pve-core.

```bash
make validate                # pre-flight: syntax, secrets, mounts, dry-runs
bash scripts/create-secrets.sh   # creates k8s secrets from secrets/homelab.env
bash scripts/deploy-k8s.sh --dry-run   # preview
bash scripts/deploy-k8s.sh    # apply k8s manifests + rollout checks
make deploy-docker           # docker compose up -d per stack (host targeting: planned, P1)
make backup                  # repo + app data to Synology
bash scripts/restore-app-data.sh --dry-run   # preview restore
```

Deployment order, rollback, and recovery: [docs/runbook.md](docs/runbook.md).

## Secrets policy

- No secrets in tracked files. Real values live in `secrets/homelab.env`
  (gitignored, chmod 600) and host-local `.env` files.
- Committed files reference secrets indirectly: `${VAR}`, `secretKeyRef`,
  `{{HOMEPAGE_VAR_*}}`-style placeholders.
- k8s Secrets are created out-of-band via `scripts/create-secrets.sh`; example
  manifests (`*.example.yml`) ship as templates only.
- Leak policy: rotate any credential that appears in this repo.

## Storage

k3s uses `local-path` (rancher.io/local-path, default) — hostPath volumes on
the node where the pod lands. NAS-backed storage for app data is provisioned
per-service (NFS from Synology). See [docs/storage.md](docs/storage.md).

## Docs

- [docs/homelab-docs-master.md](docs/homelab-docs-master.md) — full index
- [docs/gitops-plan.md](docs/gitops-plan.md) — commit-to-live roadmap (P0 done, P1+ pending)
- [docs/runbook.md](docs/runbook.md) — recovery and backup/restore
