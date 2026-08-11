# Homelab Infrastructure Audit — 2026-07-19

Verified live state against inventory. Read-only inspection. No changes were made.

---

## 1. Homelab Inventory and Topology

### Host Summary

| Host | IP | Role | OS | Status | Notes |
|---|---|---|---|---|---|
| burndev | 192.168.1.50 | Main Docker host, k3s server, Pi agent, rsyslog receiver, GPU/AI host | Debian 13 (trixie) | **Active** | Sole active server |
| kws-rpi-1 | (mDNS) | UniFi Network/UniFi OS | Debian 13 (trixie), Raspberry Pi | **Active** | UniFi running via podman |
| synology | 192.168.1.11 | NAS, NFS storage, backup destination | Synology DSM | **Active** | NFS exports /volume1/immich |
| kwsdisplay.lan | 192.168.1.168 | Rack display and kiosk | — | **Active** | Pingable, web accessible |
| homeassistant.lan | 192.168.1.129 | Home Assistant | — | **Active** | HA OS responding on :8123 |
| OPNsense.lan | 192.168.1.1 | Firewall/router | OPNsense | **Active** | Web UI reachable, SSH blocked |
| proxmox1.lan | resolves to WAN IP (<WAN-IP>) | Proxmox node 1 | — | **DNS broken** | PTR points to WAN, not LAN |
| proxmox2.lan | resolves to 10.8.0.1 (VPN) | Proxmox node 2 | — | **DNS broken** | PTR points to VPN IP |
| k8s-cp-01 | 192.168.1.60 | Old k3s control-plane | Debian 13 | **Retired?** | Pingable but not in burndev k3s |
| k8s-worker-01 | 192.168.1.61 | Old k3s worker | Debian 13 | **DOWN** | Not responding to ping |
| k8s-worker-02 | 192.168.1.62 | Old k3s worker | Debian 13 | **Retired?** | Pingable but not in burndev k3s |

### Critical DNS Issues

- `proxmox1.lan` resolves to <WAN-IP> (public WAN IP) — **broken**
- `proxmox2.lan` resolves to 10.8.0.1 (VPN tunnel address) — **broken**
- `synology.lan` resolves to 192.168.2.1 (MGMT VLAN gateway, not the NAS) — **broken**
- `homeassistant.lan` resolves to 192.168.1.129 — **correct**

### NFS Mounts

| Source | Mount Point | Status | Use |
|---|---|---|---|
| 192.168.1.11:/volume1/immich | /mnt/immich | **Mounted** | Immich library storage |
| (autofs) | /mnt/syn | **Not mounted** | Backup destination, homelab repo sync |
| — | /mnt/tank | Empty | Unknown |
| — | /mnt/burntv | Empty | Unknown |

---

## 2. OPNsense Router Configuration

**Status**: Reachable at https://192.168.1.1 (web UI). SSH access blocked.

**What could not be verified** (SSH inaccessible):
- Interface assignments (WAN, LAN, MGMT, IoT, HOMEVPN, MNTR)
- igc0/igc1/igc5 physical mappings
- DHCP server (Dnsmasq vs Kea)
- Firewall rules between VLANs
- NAT and port forwards (Project Fika)
- API users and permissions
- Configuration backup to Synology
- OPNsense repository and backup key arrangement

**Verified**:
- OPNsense is up at 192.168.1.1
- Web UI responds on HTTPS
- ntopng on port 3000 and OPNsense exporter on 9273 were not reachable during audit
- MGMT VLAN gateway 192.168.2.1 is pingable (from LAN)
- IoT VLAN gateway 192.168.99.1 is NOT pingable

**Recommended**: Establish SSH access to OPNsense to complete this section.

---

## 3. VLAN and Switch Configuration

**Status**: Not directly verified. Switch topology and VLAN configuration were not accessible during this audit.

**Recommended**: Access UniFi controller on kws-rpi-1 to document switch ports, VLAN assignments, and PVID/native VLAN settings.

---

## 4. UniFi Controller and Wireless

**Status**: UniFi OS running on kws-rpi-1.

**Verified on kws-rpi-1**:
- UniFi Network Server (Java process, PID 1712) running via podman
- MongoDB (PID 1889) bound to 127.0.0.1:27117
- Postgres 14 for unifi-core
- UniFi Identity Update App running
- unifi-os-log-bridge forwarding logs to syslog
- Listening ports: 8080, 8444, 8880, 8881, 8882, 6789, 11443
- **NOT listening on 8443** — web UI may be on different port
- OS: Debian 13 (trixie) on Raspberry Pi
- Memory: 3.7G total, 1.9G used
- Disk: 58G total, 9.1G used (17%)

**Caddy proxy**: `unifi.burndev.lan` proxies to `https://localhost:8443` on burndev (502 — dead backend). The real UniFi controller runs on kws-rpi-1, not burndev. The Caddy proxy target is wrong.

**burndev UniFi directories** (inactive):
- `/opt/docker/unifi/` — contains data, db, db.broken.20260510_142034
- `/opt/docker/unifi-bak/` — old linuxserver/unifi-controller compose
- `/opt/docker/unifiosserver/` — UniFi OS server attempt (UOS_SYSTEM_IP=192.168.1.50)
- `/opt/docker/uniosserver/` — another UniFi compose

**Recommended**: Update Caddyfile to proxy `unifi.burndev.lan` to kws-rpi-1 IP and correct port. Clean up inactive UniFi directories on burndev.

---

## 5. Internal DNS, Certificates, and Caddy

### Caddy

- **Host**: burndev, container `caddy`
- **Image**: caddy:2.11.4-alpine
- **Network mode**: host
- **Configuration source**: `/home/npburney/dev/homelab/docker/caddy/Caddyfile`
- **Certificate path**: `/home/npburney/dev/homelab/docker/caddy/certs/`
- **Data path**: `/home/npburney/dev/homelab/docker/caddy/data/`

### Certificates

| File | Created | Covers |
|---|---|---|
| burndev.lan+1.pem | 2026-03-14 | burndev.lan + 1 SAN |
| burney.tv.pem | 2026-03-14 | burney.tv |

Certificates are manually generated (not Let's Encrypt). Auto HTTPS is disabled.

### Reverse Proxy Map (Live Caddyfile)

| Public URL | Backend | Backend Status |
|---|---|---|
| burndev.lan | localhost:8080 (llama-server) | ✅ Active |
| home.burndev.lan | localhost:3000 (Karakeep, NOT Homepage) | ✅ Active |
| immich.burndev.lan | localhost:2283 | ✅ Active |
| vikunja.burndev.lan | 192.168.1.50:3456 | ✅ Active |
| arcane.burndev.lan | localhost:3552 | ✅ Active |
| actual.burndev.lan | localhost:5006 | ✅ Active |
| burney.tv | localhost:8096 (Jellyfin) | ❌ Backend down |
| seerr.burndev.lan | localhost:5055 | ❌ Backend down |
| metube.burndev.lan | localhost:8082 | ❌ Backend down |
| sonarr.burndev.lan | localhost:8989 | ❌ Backend down |
| radarr.burndev.lan | localhost:7878 | ❌ Backend down |
| lidarr.burndev.lan | localhost:8686 | ❌ Backend down |
| prowlarr.burndev.lan | localhost:9696 | ❌ Backend down |
| qbit.burndev.lan | localhost:8889 | ❌ Backend down |
| trilium.burndev.lan | localhost:8005 | ❌ Backend down |
| portainer.burndev.lan | https://localhost:9443 (tls_insecure_skip_verify) | ❌ Backend down |
| unifi.burndev.lan | https://localhost:8443 (tls_insecure_skip_verify) | ❌ Wrong target |

**Port conflict**: Port 3000 is used by Karakeep, not Homepage. The `home.burndev.lan` URL serves Karakeep.

**Stale config**: `/opt/docker/caddy/Caddyfile` is outdated. The live config is in `/home/npburney/dev/homelab/docker/caddy/Caddyfile`.

**Old Nginx**: `/opt/docker/nginx/` contains an unused Nginx Proxy Manager setup (jc21/nginx-proxy-manager). Container not running.

---

## 6. Docker Service Platform

### Running Containers

| Container | Image | Ports | Network | Status |
|---|---|---|---|---|
| caddy | caddy:2.11.4-alpine | host network | host | ✅ |
| immich_server | ghcr.io/immich-app/immich-server:v3 | 2283 | immich_default | ✅ |
| immich_machine_learning | ghcr.io/immich-app/immich-machine-learning:v3 | — | immich_default | ✅ |
| immich_postgres | ghcr.io/immich-app/postgres:14-vectorchord0.4.3 | 5432 | immich_default | ✅ |
| immich_redis | valkey/valkey:9 | 6379 | immich_default | ✅ |
| vikunja-vikunja-1 | vikunja/vikunja:2.3.0 | 3456 | vikunja_default | ✅ |
| karakeep-web-1 | ghcr.io/karakeep-app/karakeep:release | 3000 | karakeep_default | ✅ |
| karakeep-chrome-1 | gcr.io/zenika-hub/alpine-chrome:124 | — | karakeep_default | ✅ |
| karakeep-meilisearch-1 | getmeili/meilisearch:v1.41.0 | 7700 | karakeep_default | ✅ |
| scanopy-daemon | ghcr.io/scanopy/scanopy/daemon:latest | host network | host | ✅ |
| scanopy-postgres-1 | postgres:17-alpine | 5432 | scanopy_scanopy | ✅ |
| scanopy-server-1 | ghcr.io/scanopy/scanopy/server:latest | 60072 | scanopy_scanopy | ✅ |
| arcane | ghcr.io/getarcaneapp/arcane:latest | 3552 | arcane_default | ✅ |
| actual-budget actual_server-1 | actualbudget/actual-server:latest | 5006 | actual-budget_default | ⚠️ unhealthy |

### Stopped / Down Services

| Service | Compose File | Reason |
|---|---|---|
| Jellyfin | `/home/npburney/dev/homelab/docker/jellyfin/compose.yaml` | Container not running |
| Servarr stack (gluetun, qbittorrent, sonarr, radarr, lidarr, prowlarr, flaresolverr, seerr) | `/home/npburney/dev/homelab/docker/servarr/compose.yaml` | Container not running |
| Homepage | `/opt/docker/homepage/compose.yaml` | Container not running (port conflict with Karakeep on 3000) |
| LLDAP | `/opt/docker/lldap/docker-compose.yaml` | Container not running |
| Cannery | `/home/npburney/dev/homelab/docker/cannery/compose.yaml` | Container not running |
| RackPeek | `/home/npburney/dev/homelab/docker/rackpeek/compose.yaml` | Container not running |
| LLMeter | `/home/npburney/dev/homelab/docker/llmeter/compose.yaml` | Container not running |
| Docker Socket Proxy | `/home/npburney/dev/homelab/docker/socket-proxy/compose.yaml` | Exited |
| MakersVault | `/opt/docker/makersvault/compose.yaml` | Container not running |
| Scrutiny | `/opt/docker/scrutiny/` | No compose found, container not running |
| Termix | — | No compose found |
| Stash | — | No compose found, data at `/opt/docker/stash/` |

### Source of Truth

The canonical Docker compose files live in `/home/npburney/dev/homelab/docker/`. The `/opt/docker/` directory contains duplicates and stale configurations. The repo versions:
- Pin image versions (not `:latest`)
- Bind to 127.0.0.1 instead of 0.0.0.0
- Use environment variables for secrets

### Servarr Stack

- **Config**: `/home/npburney/dev/homelab/docker/servarr/compose.yaml`
- **VPN**: gluetun with AirVPN via WireGuard
- **qBittorrent**: network_mode "service:gluetun" (routes through VPN)
- **Media mount**: `/data/pool/burntv/media` and `/data/pool/burntv/torrents`
- **Config directories**: `/opt/docker/servarr/{lidarr,sonarr,radarr,prowlarr,qbittorrent,seerr}/config/`
- **gluetun config**: `/opt/docker/servarr/gluetun/`

### Security Issue: Hardcoded Secrets

The following files contain hardcoded secrets that should use environment variables:
- `/opt/docker/servarr/compose.yaml` (old version) — hardcoded WireGuard keys
- `/opt/docker/arcane/docker-compose.yaml` — hardcoded ENCRYPTION_KEY and JWT_SECRET
- `/opt/docker/makersvault/compose.yaml` — default admin password

The repo versions in `/home/npburney/dev/homelab/docker/` correctly use `$(ENV_VAR)` references.

### Port Map

| Port | Service | Bind |
|---|---|---|
| 80, 443 | Caddy | host network |
| 2283 | Immich | 0.0.0.0 |
| 3000 | Karakeep | 0.0.0.0 |
| 3456 | Vikunja | 0.0.0.0 |
| 3552 | Arcane | 0.0.0.0 |
| 5006 | Actual Budget | 0.0.0.0 |
| 60072 | Scanopy | 0.0.0.0 |
| 8080 | llama-server | 127.0.0.1 only |
| 2375 | Docker Socket Proxy | 192.168.1.50 only |
| 514 | rsyslog | 0.0.0.0 (TCP+UDP) |

---

## 7. Kubernetes

### burndev k3s (Current — 11 days old)

- **Version**: v1.36.1+k3s1
- **Single node**: burndev (control-plane + etcd)
- **API**: https://127.0.0.1:6443
- **Kubeconfig**: `/etc/rancher/k3s/k3s.yaml`

**Running pods** (only system):
- coredns-6648f7576f-k4rzp
- local-path-provisioner-58d557dc48-dhd55
- metrics-server-7c86f97b8d-mn2tg

**No application workloads deployed.** No namespaces beyond `default` and `kube-system`.

### Old 3-Node Cluster (homelab-local context)

- **Kubeconfig**: `/home/npburney/.kube/homelab-local.yaml`
- **Context name**: homelab-local
- **Nodes**: k8s-cp-01 (192.168.1.60), k8s-worker-01 (192.168.1.61), k8s-worker-02 (192.168.1.62)
- **Status**: k8s-worker-01 is DOWN. Context certificates do not match burndev k3s. This cluster appears retired.

### Kubernetes Manifests (in repo, not deployed)

`/home/npburney/dev/homelab/kubernetes/apps/`:
- code-server.yml, homepage.yml, kanboard.yml, termix.yml, trilium.yml, omni-tools.yml
- immich.yml.disabled (Immich was moved to Docker)

`/home/npburney/dev/homelab/kubernetes/monitoring/`:
- kube-prometheus-stack-values.yml
- blackbox-values.yml
- grafana.yml, grafana-dashboards.yml
- alert-rules.yml, prometheus-additional-scrape.yml

**None of these are deployed** to the current burndev k3s.

### Deployment Workflow

The `make up` workflow:
1. Bootstrap (Ansible)
2. Platform (cert-manager, NFS provisioner, Prometheus stack, Blackbox)
3. Create secrets
4. Sync homepage
5. Deploy K8s apps
6. Health checks

This workflow has not been run against the current 11-day-old k3s cluster.

---

## 8. Synology Storage and NFS Layout

- **Host**: 192.168.1.11 (NAS)
- **NFS export**: `/volume1/immich` → mounted at `/mnt/immich` on burndev
- **immich upload location**: `/mnt/immich` (NFS)
- **immich DB location**: Docker named volume (local)
- **Synology DNS**: `synology.lan` resolves to 192.168.2.1 (wrong — that is the MGMT VLAN gateway IP)

**Backup mount**: `/mnt/syn` uses autofs (on-demand mounting). Not currently mounted. Backup scripts check for it and exit if absent.

**Backup directories on synology** (`/mnt/syn/backups/homelab/`):
- `docker-volumes/` — Docker volume data
- `postgres-dumps/` — pg_dump output
- `caddy/` — certs and data
- `k8s-pvcs/` — local-path PV data

**Last backup**: Unknown. `/mnt/syn` was not mounted during audit.

---

## 9. Backup and Recovery Systems

### Backup Scripts

| Script | What It Backs Up | Destination |
|---|---|---|
| `/home/npburney/dev/homelab/scripts/backup.sh` | Entire homelab repo | `/mnt/syn/backups/homelab/` |
| `/home/npburney/dev/homelab/scripts/backup-app-data.sh` | Docker volumes, Postgres DBs, Caddy certs, K8s PVCs | `/mnt/syn/backups/homelab/` |

### Backup Coverage

| Data | Method | Status |
|---|---|---|
| OPNsense config | Unknown | ❓ Not verified |
| /opt/docker (volumes) | rsync to /mnt/syn | ⚠️ Requires /mnt/syn mounted |
| Immich DB | pg_dump from container | Scripted (backup-app-data.sh) |
| Vikunja DB | pg_dump from container | Scripted |
| Scanopy DB | pg_dump from container | Scripted |
| Cannery DB | pg_dump from container | Scripted |
| Caddy certs/config | rsync to /mnt/syn | Scripted |
| K8s PVCs | rsync from /var/lib/rancher/k3s/storage | Scripted |
| Home Assistant | Unknown | ❓ Not verified |
| UniFi DB | Unknown | ❓ Not verified |
| Proxmox VMs | Cron job at 2 AM | `/home/npburney/dev/homelab-pm/scripts/backup.sh` |
| Synology critical data | Unknown | ❓ Not verified |
| Git repos | Part of backup.sh | Scripted |

### Restore

`scripts/restore-app-data.sh` supports `--dry-run` (default) and `--force`. Postgres restores require manual steps. No restore test has been verified.

### Cron

Only one cron job is configured (user npburney):
```
0 2 * * * /home/npburney/dev/homelab-pm/scripts/backup.sh >> /home/npburney/dev/homelab-pm/scripts/backup.log 2>&1
```

---

## 10. Monitoring, Metrics, and Network Visibility

### Active

| Component | Location | Status |
|---|---|---|
| Scanopy | burndev, port 60072 | ✅ Running (Postgres backend) |
| llama-server health | burndev, port 8080 | ✅ /health returns ok |
| nvidia-smi | burndev | ✅ RTX 3080 Ti, 7164 MiB VRAM used |

### Down / Not Deployed

| Component | Expected Location | Status |
|---|---|---|
| Prometheus | k3s monitoring namespace | ❌ Not deployed |
| Grafana | k3s monitoring namespace | ❌ Not deployed |
| Blackbox Exporter | k3s monitoring namespace | ❌ Not deployed |
| OPNsense Exporter | 192.168.1.1:9273 | ❌ Not reachable |
| Uptime Kuma | Unknown | ❓ Not found |
| Scrutiny | /opt/docker/scrutiny | ❌ Not running |
| ntopng | 192.168.1.1:3000 | ❌ Not reachable |
| Glances | Part of homepage compose | ❌ Not running |

**Grafana Cloud**: Organization `burneypromod` was reportedly deleted. No active references found during audit.

---

## 11. Centralized Logging

### rsyslog on burndev

- **Service**: active (running)
- **Listening**: TCP 514, UDP 514
- **Config**: `/etc/rsyslog.d/10-remote-listener.conf`
- **Template**: `/var/log/remote/%HOSTNAME%/%PROGRAMNAME%.log`
- **Log directory**: `/var/log/remote/` exists but is empty

**No remote hosts are forwarding logs yet.** The rsyslog receiver is configured and listening, but no log sources are sending data.

### Log Sources Not Yet Forwarding

- OPNsense
- kws-rpi-1 (UniFi OS)
- Home Assistant
- Proxmox nodes
- Synology

### Agent Configuration

The Pi agent's AGENTS.md references `/var/log/remote` for centralized log inspection, anticipating logs from OPNsense and UniFi.

---

## 12. Home Assistant and IoT Projects

### Host

- **IP**: 192.168.1.129
- **URL**: https://homeassistant.lan:8123 (confirmed responding)
- **Installation type**: Unknown (HA OS VM, container, or bare metal; not on burndev)
- **SSH alias**: `homeassistant` → homeassistant.lan, user root, key `/home/npburney/.ssh/homeassistant_ed25519`

### What Could Not Be Verified

Home Assistant is up but was only checked externally. The following are unverified:
- Backup process and Git repository
- Nabu Casa/Home Assistant Cloud usage
- Google OAuth integration
- OPNsense integration and API permissions
- Music Assistant state
- ESPHome setup
- Emporia Vue 3 configuration
- BroadLink RM4 Pro
- Hunter Skyflow fan integration
- Home Assistant MCP server
- Dashboard configuration and custom cards

### IoT VLAN

Gateway 192.168.99.1 was not pingable during audit. IoT VLAN connectivity needs verification.

---

## 13. Proxmox Platform

**Status**: DNS broken for both Proxmox hosts.

- `proxmox1.lan` → <WAN-IP> (public WAN IP)
- `proxmox2.lan` → 10.8.0.1 (VPN tunnel address)

Neither host responded on port 8006 (Proxmox API/web UI). Direct IP addresses unknown.

**Backup cron**: `0 2 * * * /home/npburney/dev/homelab-pm/scripts/backup.sh`

The Proxmox backup script exists at `/home/npburney/dev/homelab-pm/scripts/backup.sh` (separate repo from homelab).

**Recommended**: Fix DNS records. Determine if Proxmox nodes are still online and if VMs/containers are still needed.

---

## 14. Homelab Repository and Infrastructure Automation

### Repository

- **Path**: `/home/npburney/dev/homelab`
- **Active branch**: `local`
- **Other branches**: `main`, `dev`, `backup-main-before-dev-overwrite`
- **Last commit**: `2909e74 feat: homepage discovery for docker services`

### Structure

```
homelab/
├── AGENTS.md
├── Makefile
├── ansible/           # Ansible playbooks, inventory, roles
├── config/
│   └── homepage/      # Homepage dashboard config
├── docker/            # Canonical Docker compose files
│   ├── actual-budget/
│   ├── caddy/
│   ├── cannery/
│   ├── immich/
│   ├── jellyfin/
│   ├── karakeep/
│   ├── llmeter/
│   ├── rackpeek/
│   ├── scanopy/
│   ├── servarr/
│   ├── socket-proxy/
│   └── vikunja/
├── docs/
├── kubernetes/
│   ├── apps/           # K8s application manifests
│   ├── cert-manager/
│   ├── monitoring/
│   ├── namespaces/
│   └── policies/
├── scripts/            # Deployment, backup, restore scripts
├── secrets/            # Environment files (not in version control)
└── vikunja-import.csv
```

### Makefile Targets

| Target | Description |
|---|---|
| `validate` | Run validation script |
| `bootstrap` | Ansible playbook |
| `platform` | cert-manager, NFS provisioner, Prometheus, Blackbox |
| `up` | Full deployment (6 steps) |
| `deploy-k8s` | Apply K8s manifests |
| `deploy-docker` | Start all Docker compose services |
| `backup` | Run backup + backup-app-data |
| `restore-dry-run` | Show what restore would do |
| `restore` | Full restore (--force) |

**Note**: `make deploy-docker` does NOT include karakeep, llmeter, or socket-proxy.

### Security Concerns

- Hardcoded secrets in some `/opt/docker/*/compose.yaml` files (not in repo versions)
- The repo's `secrets/` directory should contain `.env` files excluded from Git
- WireGuard keys in old compose file at `/opt/docker/servarr/compose.yaml`

---

## 15. Agent, MCP, and Local AI Integrations

### Pi Coding Agent

- **Launcher**: `/home/npburney/bin/pi-local`
- **Kubeconfig**: `$HOME/.kube/homelab-local.yaml` (points to old cluster)
- **AGENTS.md**: `/home/npburney/.pi/agent/AGENTS.md` (global policy)
- **Skills**: `/home/npburney/.pi/agent/skills/`

### Local LLM

- **Engine**: llama.cpp (llama-server)
- **Model**: qwen3-8b-local (Qwen3 8B, Q4_K_M quantization)
- **VRAM usage**: 7164 MiB on RTX 3080 Ti
- **Endpoint**: http://127.0.0.1:8080/v1
- **Context window**: 16384 tokens
- **CUDA**: Available (NVIDIA driver 550.163.01, CUDA 12.4)

### Pi Models Config

`/home/npburney/.pi/agent/models.json`:
- Provider: llama-cpp
- Model: qwen3-8b-local
- API: openai-completions
- No reasoning/thinking support

### MCP Servers

**Available MCP tools observed**:
- home-assistant (18 tools) — direct tools, not through MCP gateway
- vikunja (53 tools) — via MCP gateway
- ha-mcp (27 tools) — via MCP gateway

### Homelab Inventory Skill

- Location: `/home/npburney/.pi/agent/skills/homelab-inventory/`
- References: `burndev.md`, `kws-rpi-1.md`, `synology.md` (3 of many hosts)
- Missing entries: Home Assistant, Proxmox, OPNsense, kwsdisplay

---

## 16. Lower-Priority Projects

### kwsdisplay Rack Dashboard

- **Status**: Active
- **IP**: 192.168.1.168
- **URL**: http://kwsdisplay.lan
- **Configuration**: Unknown

### RTX 3080 Ti Local Inference

- **Status**: Active
- **GPU**: NVIDIA GeForce RTX 3080 Ti, 12 GB VRAM
- **Engine**: llama.cpp server
- **Model**: Qwen3 8B Q4_K_M
- **Port**: 8080 (localhost only)
- **Caddy proxy**: `burndev.lan` → localhost:8080

### YouTube Transcription/Whisper Pipeline

- **Status**: Skill available (`transcribe` skill)
- **Location**: Not verified

### WireGuard Travel-Router Access

- **Status**: Unknown
- **Related**: gluetun is configured for AirVPN WireGuard but container is down

### Project Fika Server/NAT

- **Status**: Unknown
- OPNsense port forwards could not be verified (SSH blocked)

### StatTrak Clock

- **Status**: Unknown

### Breaker Mapping and Emporia Energy Monitoring

- **Status**: Unknown
- Emporia Vue 3 reportedly connected via ESPHome

### Home Assistant Floor-Plan/Dashboard

- **Status**: Unknown (HA is running but dashboard not inspected)

---

## Immediate Actions Recommended

1. **Fix DNS**: proxmox1.lan, proxmox2.lan, and synology.lan resolve to wrong IPs
2. **Enable OPNsense SSH**: Required for configuration verification and log forwarding
3. **Start down services**: servarr stack, jellyfin, homepage (on different port)
4. **Fix UniFi proxy**: Update Caddyfile to point to kws-rpi-1 instead of localhost
5. **Deploy K8s apps**: Run `make platform` then `make deploy-k8s` on the new k3s cluster
6. **Mount /mnt/syn**: Run backup and verify backup integrity
7. **Configure remote logging**: Set up OPNsense, kws-rpi-1, HA to forward to rsyslog on burndev
8. **Remove stale configs**: Clean up /opt/docker/{unifi,unifi-bak,unifiosserver,uniosserver,nginx,stash}
9. **Fix port conflict**: Karakeep on 3000 vs Homepage. Move one to different port.
10. **Update homelab inventory**: Add missing host entries (Home Assistant, Proxmox, OPNsense, kwsdisplay)
11. **Test restore**: Run restore-app-data.sh --dry-run, then test actual restore of one service
12. **Rotate exposed secrets**: WireGuard keys and JWT secrets found in old compose files
