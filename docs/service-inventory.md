# Service Inventory (current)

Live inventory from the 2026-08-06 audit, cross-referenced with the Trilium service inventory note (2026-08-07). All services up.

## Media (pve-gpu)

| Service | Host | URL / Port | Notes |
|---------|------|-----------|-------|
| Jellyfin | pve-gpu CT 100 | 192.168.1.187:8096 (jellyfin.lan) | burney.tv, VA-API |
| Sonarr | pve-gpu CT 201 | 10.30.0.11:8989 (sonarr.lan) | NFS rw |
| Radarr | pve-gpu CT 202 | 10.30.0.12:7878 (radarr.lan) | NFS rw |
| Lidarr | pve-gpu CT 203 | 10.30.0.13:8686 (lidarr.lan) | NFS rw |
| Prowlarr | pve-gpu CT 204 | 10.30.0.14:9696 (prowlarr.lan) | no media mount |
| qBittorrent | pve-gpu CT 205 | 10.30.0.15:8889 (qbit.lan) | gluetun VPN |

## Applications

| Service | Host | URL |
|---------|------|-----|
| Immich | pve-exu CT 111 | immich.pve.lan |
| Karakeep | pve-exu CT 113 | karakeep.pve.lan |
| Vikunja | pve-exu CT 112 | vikunja.pve.lan |
| RackPeek | pve-exu CT 112 | rackpeek.pve.lan |
| Actual Budget | pve-exu CT 112 | actual.pve.lan |
| Scanopy | pve-core CT 115 | 192.168.1.65:60072 / scanopy.burney.network | SSO-protected via Caddy (added 2026-08-16) |
| OpenBao | pve-core CT 110 | openbao.pve.lan |
| LLDAP | pve-core CT 110 | lldap.pve.lan |
| FileBrowser Quantum | pve-core CT 114 | files.burney.network |

## Cluster (k3s via NodePort)

| Service | NodePort | Node |
|---------|----------|------|
| Trilium | 30081 | k3s-core |
| Kanboard | 30083 | k3s-exu |
| Homepage | 30080 | k3s-gpu |
| code-server | 30082 | k3s-gpu |
| omni-tools | 30084 | k3s-exu |

## Decommissioned (no longer running)

- burndev Docker stacks: Caddy, Immich, Vikunja, Arcane, Downtify, Actual Budget, Scanopy, Portainer, UniFi.
- burndev single-node k3s: Trilium, code-server, Kanboard, Omni-tools.
- Cannery, Linkwarden (repo dirs remain, not deployed).

Last verified: 2026-08-07
