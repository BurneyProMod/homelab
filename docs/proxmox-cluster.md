# Proxmox Cluster & Service Topology

Current-state reference for the 3-node Proxmox VE cluster that replaced burndev as the homelab workload host.
Derived from the Trilium migration project note and service inventory (2026-08-07).

## Cluster Nodes

| Node | IP | Role | CPU | RAM | Storage | Status |
|------|-----|------|-----|-----|---------|--------|
| pve-core | 192.168.1.30 | HA primary, ID 1 | 6c | 15.5G | 68G | Online |
| pve-exu | 192.168.1.31 | HA primary, ID 3 | 6c | 15.5G | 94G | Online |
| pve-gpu | 192.168.1.32 | Quorum/K3s only, ID 2 | 8c | 14.6G | 94G | Online |

Proxmox VE 9.2.x, kernel 6.17.2-1-pve. Cluster: `pve-cluster` (corosync, 3-node quorum).

## Shared Storage (Synology)

Single NFS4 export `/volume1/homelab` mounted at `/mnt/synology/homelab` on all 3 nodes.

| Storage | Path | Content | Purpose |
|---------|------|---------|---------|
| synology-ha | `/mnt/synology/homelab/proxmox-ha` | images, rootdir | LXC rootfs |
| synology-k8s | `/mnt/synology/homelab/proxmox-k8s` | images | future k3s CSI |
| syn-backups-core | `/mnt/synology/homelab/backups/hosts/proxmox/pve-core` | backup | vzdump target (daily 02:00, keep-last 2) |
| syn-backups-gpu | `/mnt/synology/homelab/backups/hosts/proxmox/pve-gpu` | backup | vzdump target (daily 02:00, keep-last 2) |
| syn-backups-exu | `/mnt/synology/homelab/backups/hosts/proxmox/pve-exu` | backup | vzdump target (daily 02:00, keep-last 2) |

## Docker LXCs (rootfs on synology-ha, unprivileged, nesting=1, keyctl=1, onboot=1)

| ID | Name | Host | IP | vCPU | RAM | Disk | Services |
|----|------|------|----|------|-----|------|----------|
| 110 | identity | pve-core | 192.168.1.60 | 1c | 384M | 4G | LLDAP, OpenBao |
| 111 | immich | pve-exu | 192.168.1.61 | 4c | 6G | 32G | Immich |
| 112 | docker-apps | pve-exu | 192.168.1.62 | 2c | 3G | 32G | Vikunja, Actual Budget, RackPeek |
| 113 | archives | pve-exu | 192.168.1.63 | 4c | 4G | 32G | Karakeep (+chrome, meilisearch) |
| 114 | files | pve-core | 192.168.1.64 | 1c | 512M | 4G | FileBrowser Quantum |
| 115 | operations | pve-core | 192.168.1.65 | 2c | 2G | 16G | Scanopy (+postgres, daemon) |
| 116 | caddy | pve-exu | 192.168.1.41 | 1c | 512M | 4G | retired 2026-08-07 |
| 102 | pi-agent | pve-core | — | — | — | — | coding agent |
| 103 | caddy | pve-core | 192.168.1.42 | — | — | — | HA caddy master (keepalived prio 150) |
| 101 | caddy | pve-gpu | 192.168.1.40 | — | — | — | HA caddy backup (keepalived prio 100) |
| 100 | jellyfin | pve-gpu | 192.168.1.187 | — | — | — | Jellyfin (burney.tv) |
| 201–205 | servarr | pve-gpu | 10.30.0.11–15 | — | — | — | Sonarr/Radarr/Lidarr/Prowlarr/qBittorrent |

## K3s Cluster VMs (local-lvm, Debian 13 genericcloud)

| ID | Name | Host | IP | vCPU | RAM | Disk |
|----|------|------|----|------|-----|------|
| 120 | k3s-core | pve-core | 192.168.1.70 | 2c | 4G | 31G |
| 121 | k3s-exu | pve-exu | 192.168.1.71 | 2c | 4G | 31G |
| 122 | k3s-gpu | pve-gpu | 192.168.1.72 | 2c | 4G | 31G |

K3s v1.36.1+k3s1, all nodes control-plane+etcd, `--disable traefik --disable servicelb`.
Services via NodePort: Trilium 30081 (k3s-core), Kanboard 30083 (k3s-exu), Homepage 30080 (k3s-gpu), code-server 30082 (k3s-gpu), omni-tools 30084 (k3s-exu).
PVCs use `local-path` (node-affinity); not HA.

## Front Door (HA Caddy pair)

keepalived VIP **192.168.1.10**, serves `*.burney.network`. See `docker-services.md`.

| Node | IP | Role |
|------|-----|------|
| caddy 103 (pve-core) | 192.168.1.42 | keepalived master (prio 150) |
| caddy 101 (pve-gpu) | 192.168.1.40 | keepalived backup (prio 100) |

Access: LAN (192.168.1.0/24) + WireGuard (10.8.0.0/24) only; no WAN exposure.
Certs via Cloudflare DNS-01. Config source of truth: `burndev:~/dev/homelab/config/caddy/Caddyfile`.

## Migration Status

burndev → Proxmox migration in progress (started 2026-08-02). Migrated: Trilium, Homepage, code-server, Kanboard, omni-tools, LLDAP, Vikunja, Actual Budget, RackPeek, Karakeep, Scanopy, FileBrowser Quantum. Remaining: Linkwarden (links.burney.network, LXC 113).

## Known Issues

1. Trilium PVC is local-path (node-affinity k3s-core), not HA.
2. RAM overcommit — total Docker LXC + k3s VM allocation (~16.4 GiB) can exceed a surviving 15.5G host during failover. 32GB host RAM upgrade recommended.
3. Scanopy daemon has no host networking (unprivileged LXC limitation).
4. Ollama not migrated (needs GPU; pve-gpu not in HA scope).
5. Proxmox CSI for k3s PVC HA not yet installed.
