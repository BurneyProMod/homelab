# Networking & DNS

## Architecture Overview

```
Internet -> OPNsense (192.168.1.1)
             |
        keepalived VIP 192.168.1.10  (*.burney.network)
             |
   +---------+---------+
   | HA Caddy pair     |  caddy 103 (pve-core, prio 150) + caddy 101 (pve-gpu, prio 100)
   +---------+---------+
             |
   +---------+--------------+
   |         |              |
 Docker LXCs   K3s NodePorts   Media LXCs
 (direct ports) (30080-30084)   (burney.tv)
```

The Proxmox cluster (pve-core/gpu/exu) hosts the workloads; burndev (192.168.1.50) is reduced to NFS media + Ollama.
See `proxmox-cluster.md` for the full topology.

## DNS Resolution

### Internal resolution

All web services use `*.burney.network`, which resolves to the keepalived VIP **192.168.1.10** on the HA caddy pair.

### OPNsense Configuration

For internal clients to resolve homelab domains, add a wildcard DNS override in OPNsense:

1. **Unbound DNS -> Overrides -> Domain Overrides**
   - Domain: `burney.network`, IP: `192.168.1.10` (wildcard)

2. **Hairpin NAT** (NAT reflection): Required for internal clients to reach services via the public/WAN IP. Enable in Firewall -> Settings -> Advanced -> NAT Reflection mode for port forwards.

### Without hairpin NAT

Internal clients trying to reach `*.burney.network` must resolve directly to the VIP `192.168.1.10`. If DNS resolves to the WAN IP and hairpin NAT isn't working, connections will fail.

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
