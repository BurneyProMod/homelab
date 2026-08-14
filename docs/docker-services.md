# Docker Services & Caddy Reverse Proxy

## Architecture

All homelab web services are fronted by a **two-node HA Caddy pair** behind a keepalived VIP, serving `*.burney.network`. The front door replaced the old single burndev Caddy; workloads now run on the Proxmox cluster (see `proxmox-cluster.md`).

```
Internet → OPNsense (192.168.1.1)
             │
        keepalived VIP 192.168.1.10  (*.burney.network)
             │
   ┌─────────┴─────────┐
   │ caddy 103 (pve-core) │  keepalived master (prio 150)
   │ caddy 101 (pve-gpu)  │  keepalived backup (prio 100)
   └─────────┬─────────┘
             │
   ┌─────────┼──────────────┐
   │         │              │
 Docker LXCs   K3s NodePorts   Media LXCs
 (direct ports) (30080-30084)   (burney.tv)
```

### Domain Trees

Single TLS certificate domain tree `*.burney.network`, served by the HA pair:

| Domain Tree | Target | Notes |
|-------------|--------|-------|
| `*.burney.network` | VIP 192.168.1.10 | All migrated services (home, trilium, code, kanboard, omni, vikunja, actual, immich, lldap, openbao, karakeep, rackpeek, files, sonarr, radarr, lidarr, prowlarr, jellyfin, qbit, pi, pve) |

Access: LAN (192.168.1.0/24) + WireGuard (10.8.0.0/24) only; no WAN exposure. Certs via Cloudflare DNS-01. Config source of truth: `burndev:~/dev/homelab/config/caddy/Caddyfile`, deployed identically to both nodes.

## Service Inventory (current, *.burney.network)

Live Caddy routes (source: Trilium, 2026-08-07). Front door is the HA caddy pair at VIP 192.168.1.10.

| Domain | Backend | Service |
|--------|---------|---------|
| home.burney.network | 192.168.1.72:30080 | Homepage dashboard |
| trilium.burney.network | 192.168.1.70:30081 | Notes |
| code.burney.network | 192.168.1.72:30082 | code-server |
| kanboard.burney.network | 192.168.1.71:30083 | Kanban |
| omni.burney.network | 192.168.1.71:30084 | Utilities |
| vikunja.burney.network | 192.168.1.62:3456 | Tasks |
| actual.burney.network | 192.168.1.62:5006 | Budget |
| immich.burney.network | 192.168.1.61:2283 | Photos |
| lldap.burney.network | 192.168.1.60:17170 | LDAP |
| openbao.burney.network | 192.168.1.60:8200 | Secrets |
| karakeep.burney.network | 192.168.1.63:3000 | Bookmarks |
| rackpeek.burney.network | 192.168.1.62:3001 | Monitoring |
| files.burney.network | 192.168.1.64:8085 | FileBrowser Quantum |
| sonarr.burney.network | 10.30.0.11:8989 | Sonarr |
| radarr.burney.network | 10.30.0.12:7878 | Radarr |
| lidarr.burney.network | 10.30.0.13:8686 | Lidarr |
| prowlarr.burney.network | 10.30.0.14:9696 | Prowlarr |
| jellyfin.burney.network | 192.168.1.187:8096 | Jellyfin |
| qbit.burney.network | 10.30.0.15:8889 | qBittorrent |
| pi.burney.network | 10.31.0.2:43121 | Pi agent (basic-auth, LAN only) |
| pve.burney.network | https://192.168.1.30:8006 | Proxmox UI |

Pending: links.burney.network → 192.168.1.63:3010 (Linkwarden, LXC 113).

## Immich on pve-exu

Immich runs on pve-exu LXC 111 (192.168.1.61), not on burndev.
The stack is defined in `docker/immich/` and deployed with `scripts/deploy-immich.sh`.

Key facts:

- Photo and video data lives on NFS at `/mnt/immich` inside the LXC (Synology export `192.168.1.11:/volume1/immich`).
- PostgreSQL runs on the LXC root disk at `./data/postgres`. Never store the database on NFS.
- The edge route `http://immich.pve.lan` is served directly on the LXC; the public route is `immich.burney.network` via the HA caddy pair.
- Nightly DB dumps are written by Immich to `/mnt/immich/backups/`.
- Restore the newest nightly dump with `scripts/deploy-immich.sh --restore`.

Verify the deployment:

```bash
curl http://immich.pve.lan/api/server/ping
```

## Caddy Configuration

- Config source of truth: `config/caddy/Caddyfile` (in the repo), deployed identically to both HA nodes (caddy 103 on pve-core, caddy 101 on pve-gpu).
- Two-node keepalived pair, VIP 192.168.1.10, failover ~8s.
- Certificates: Let's Encrypt via Cloudflare DNS-01 (no public A records).
- Access: LAN (192.168.1.0/24) + WireGuard (10.8.0.0/24) only; 403 otherwise.

### Caddy Verification

```bash
# Check the HA pair (caddy 103 on pve-core, caddy 101 on pve-gpu)
ssh pve-core 'pct status 103'
ssh pve-gpu  'pct status 101'

# Watch Caddy logs on a node
ssh pve-core 'pct exec 103 -- journalctl -u caddy -f'

# Test routes (VIP must answer)
curl -k https://home.burney.network
curl -k https://trilium.burney.network
```

### Caddy Failure = All Routing Down

If the HA caddy pair fails, no service is reachable via `*.burney.network`. Fix the active node first; keepalived fails over ~8s. The Caddyfile is identical on both nodes.
```bash
# Fix the Caddyfile in the repo, then push to both nodes
vim config/caddy/Caddyfile
# restart caddy on the active node
ssh pve-core 'pct exec 103 -- systemctl restart caddy'
# verify VIP still answers
curl -k https://home.burney.network
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
