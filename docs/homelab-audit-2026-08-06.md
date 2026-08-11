# Homelab Infrastructure Audit — 2026-08-06

Verified live state against the homelab repo and the opencode inventory. Read-only inspection.
No changes were made.

---

## 1. Executive Summary

The homelab is mid-migration. The documented architecture (burndev as the central Docker +
single-node k3s server, `*.burndev.lan` / `*.homelab.lan` reverse proxy trees) no longer matches
live state. Live workloads now run on a 3-node Proxmox cluster with LXC containers and a 3-node
k3s cluster, and burndev is reduced to NFS + Ollama + Samba.

Key findings:

- **The repo is not in a clean, tracked state.** Working on branch `local` with ~70 changed
  files (17 modified, 12 deleted, 30 untracked). The `docs/` directory is entirely **untracked**
  (`git ls-files docs/` = 0). None of the documentation, including this report, is under version
  control yet.
- **The inventory lags live state.** Several undocumented LXCs exist: `identity` (110),
  `files` (114), `operations` (115) on pve-core; `caddy` (101) and `qbit` (205) on pve-gpu;
  `caddy` (103) on pve-core. The servarr stack moved to the isolated `10.30.0.0/24` network.
- **Documentation is outdated.** `README.md`, `docker-services.md`, `runbook.md`, `storage.md`,
  `monitoring.md`, and the k3s guides describe the old burndev-centric layout and the old
  single-node k3s. They need a rewrite against the new topology.
- **DNS records are partially broken.** `synology.lan` and `proxmox1/2.lan` do not resolve;
  `opnsense.lan` resolves to the WAN IP (<WAN-IP>) instead of 192.168.1.1.
- **Everything live is up.** All 20 guests running, k3s NodePorts serving, reverse proxies
  responding, NAS exporting NFS, HA and OPNsense reachable.

---

## 2. Repo and Tracking State

- Location: `/home/npburney/dev/homelab` on burndev (canonical).
- Remote: `git@github.com:BurneyProMod/homelab.git`.
- Branches: `local` (checked out), `main`, `dev`, `backup-main-before-dev-overwrite`.
  Remotes: `origin/main`, `origin/dev`, `origin/backup-main-before-dev-overwrite`.
- Working tree: 17 modified, 12 deleted, 4 added, 6 added+modified, 2 added+deleted, 30 untracked.
- `terraform/` staged for deletion (9 files).
- `docs/` — **completely untracked**. The whole documentation set (including
  `homelab-docs-master.md` and the previous `homelab-audit-2026-07-19.md`) is not committed.
- `docker/` is mostly ignored via `.gitignore` (`/docker/**` allow-listed to
  `compose.yaml` / `.env.example`).
- `secrets/homelab.env` is git-ignored; `secrets/` is otherwise untracked. No secrets are tracked.

Tracking implication: before docs can be reliably updated and tracked, the `docs/` tree should be
committed on a clean branch.

---

## 3. Topology Summary (Live)

### Hosts

| Host | IP | Role | Status |
|---|---|---|---|
| burndev | 192.168.1.50 | NFS (`burntv`), Ollama, Samba | Active |
| pve-core | 192.168.1.30 | PVE hypervisor (node 1) | Active, PVE 9.2.6 |
| pve-gpu | 192.168.1.32 | PVE hypervisor (node 2, GPU) | Active, PVE 9.2.6 |
| pve-exu | 192.168.1.31 | PVE hypervisor (node 3) | Active, PVE 9.1.1 (older) |
| kwsdisplay | 192.168.1.168 | Rack display kiosk + monitoring | Active |
| homeassistant | 192.168.1.129 | Home Assistant OS | Active |
| opnsense | 192.168.1.1 | Gateway / firewall | Active |
| synology | 192.168.1.11 | NAS, NFS exports, backups | Active (DS420+) |
| kws-rpi-1 | mDNS | UniFi controller | Not re-verified this audit |
| pi-agent | 192.168.1.198 / 10.31.0.2 | LXC 102 on pve-core, coding agent + pi-livecraft | Active |

### PVE Cluster

- Cluster name: `pve-cluster`, 3 nodes, quorate.
- Node versions: pve-core and pve-gpu on `pve-manager/9.2.6` (kernel `7.0.14-8-pve`);
  pve-exu still on `pve-manager/9.1.1` (kernel `6.17.2-1-pve`) — needs update.
- Networks: `vmbr0` (192.168.1.0/24 LAN) on all nodes; `vmbr1` (10.30.0.0/24, isolated) and
  `vmbr2` (10.31.0.0/24, isolated) on pve-gpu / pve-core respectively.

---

## 4. Guest Inventory (Live, 2026-08-06)

All guests are running.

### pve-core (192.168.1.30)

| VMID | Name | Type | IP | Role |
|---|---|---|---|---|
| 102 | pi-agent | LXC | 192.168.1.198 (dhcp), 10.31.0.2 | Coding agent, pi-livecraft on 10.31.0.2:43121 |
| 103 | caddy | LXC | 192.168.1.42 | Proxy `pi.lan` → 10.31.0.2:43121 (basic auth) |
| 110 | identity | LXC | 192.168.1.60 | Docker: OpenBao 2.6.1 (:8200), LLDAP (:17170) |
| 114 | files | LXC | 192.168.1.64 | No service listening; purpose unknown |
| 115 | operations | LXC | 192.168.1.65 | Docker: Scanopy server (:60072) + daemon + postgres |
| 120 | k3s-core | VM | 192.168.1.70 | k3s node (Trilium NodePort 30081) |

### pve-gpu (192.168.1.32)

| VMID | Name | Type | IP | Role |
|---|---|---|---|---|
| 100 | jellyfin | LXC | 192.168.1.187 | Jellyfin 10.11.11 (native), NFS ro mount of `burntv/media` |
| 101 | caddy | LXC | 192.168.1.40 | Proxy `*.lan` → arr stack + jellyfin + qbit |
| 201 | sonarr | LXC | 10.30.0.11 | NFS rw mount of `burntv` root |
| 202 | radarr | LXC | 10.30.0.12 | NFS rw mount of `burntv` root |
| 203 | lidarr | LXC | 10.30.0.13 | NFS rw mount of `burntv` root |
| 204 | prowlarr | LXC | 10.30.0.14 | No NFS mount |
| 205 | qbit | LXC | 10.30.0.15 | Docker qbittorrent + gluetun VPN, NFS `/torrents`, Web UI :8889 |
| 122 | k3s-gpu | VM | 192.168.1.72 | k3s node (homepage 30080, code 30082) |

### pve-exu (192.168.1.31)

| VMID | Name | Type | IP | Role |
|---|---|---|---|---|
| 111 | immich | LXC | 192.168.1.61 | Immich v3.1.0 (server, ML, postgres, valkey), :2283 |
| 112 | docker-apps | LXC | 192.168.1.62 | Docker: Vikunja (:3456), RackPeek (:3001), Actual (:5006) |
| 113 | archives | LXC | 192.168.1.63 | Docker: Karakeep, meilisearch, chrome, ollama-proxy (:3000) |
| 116 | caddy | LXC | 192.168.1.41 | Main reverse proxy, `*.pve.lan` on :80/:443 |
| 121 | k3s-exu | VM | 192.168.1.71 | k3s node (kanboard 30083, omni 30084) |

---

## 5. Reverse Proxy Map (Live)

### caddy 116 on pve-exu (192.168.1.41) — `*.pve.lan`

| Host | Backend |
|---|---|
| openbao.pve.lan | 192.168.1.60:8200 |
| kanboard.pve.lan | 192.168.1.71:30083 |
| karakeep.pve.lan | 192.168.1.63:3000 |
| rackpeek.pve.lan | 192.168.1.62:3001 |
| trilium.pve.lan | 192.168.1.70:30081 |
| vikunja.pve.lan | 192.168.1.62:3456 |
| actual.pve.lan | 192.168.1.62:5006 |
| immich.pve.lan | 192.168.1.61:2283 |
| lldap.pve.lan | 192.168.1.60:17170 |
| home.pve.lan | 192.168.1.72:30080 |
| code.pve.lan | 192.168.1.72:30082 |
| omni.pve.lan | 192.168.1.71:30084 |

Note: the running Caddyfile is not on disk (`/etc/caddy/Caddyfile` missing); the live config was
read from the admin API on 127.0.0.1:2019. The source file should be restored so the config is
reproducible.

### caddy 101 on pve-gpu (192.168.1.40)

| Host | Backend |
|---|---|
| sonarr.lan | 10.30.0.11:8989 |
| radarr.lan | 10.30.0.12:7878 |
| lidarr.lan | 10.30.0.13:8686 |
| prowlarr.lan | 10.30.0.14:9696 |
| jellyfin.lan | 192.168.1.187:8096 |
| qbit.lan | 10.30.0.15:8889 |

### caddy 103 on pve-core (192.168.1.42)

| Host | Backend |
|---|---|
| pi.lan | 10.31.0.2:43121 (basic-auth, LAN only) |

---

## 6. k3s Cluster (Live)

- 3 VMs, all roles control-plane+etcd: k3s-core (120), k3s-exu (121), k3s-gpu (122).
- API server :6443 not reachable externally (firewalled); kubectl access from the VMs only.
- All NodePort services verified responding:

| Service | NodePort | Node | HTTP |
|---|---|---|---|
| trilium | 30081 | k3s-core | 302 (login) |
| kanboard | 30083 | k3s-exu | 302 |
| homepage | 30080 | k3s-gpu | 200 |
| code-server | 30082 | k3s-gpu | 302 |
| omni-tools | 30084 | k3s-exu | 200 |

---

## 7. burndev — Reduced Role (Live)

- NFS export: `/data/pool/burntv` → 192.168.1.0/24 (rw, fsid=0, no_root_squash).
- mergerfs pool `1:2:3:4:5` mounted at `/data/pool`; 87 TiB total, 22 TiB used (27%).
- Pool dirs: `Burney`, `call-transcript`, `media`, `music-work`, `torrents`, `usenet`,
  `yt-dlp`, `ytdlp`.
- Samba share `[pool]` → `/data/pool` (SMB active on 445/139 — not recorded in inventory).
- Ollama (11434) models: `qwen3.5:27b`, `qwen3.5:9b`, `qwen3.6:35b-a3b`.
- Docker daemon: **not running**. k3s: **inactive**. Listening: NFS, SMB, Ollama, rsyslog (514),
  node_exporter (9100).
- Consumers confirmed: jellyfin ro mount, servarr rw mount, qbit `/torrents` mount.

---

## 8. Storage, NAS, and Other Hosts

### synology (192.168.1.11)

- DS420+, DSM, volume1 16 TiB (9.7 TiB used, 62%).
- NFS exports: `/volume1/homelab`, `/volume1/immich` (both 192.168.1.0/24).
- pve-exu storage: `synology-backups`, `synology-ha`, `synology-k8s` (NFS dir storage,
  ~15.7 TiB each reported, 9.64 TiB used).

### kwsdisplay (192.168.1.168)

- Kiosk + monitoring stack up: prometheus, node-exporter, blackbox-exporter, grafana (200),
  uptime-kuma, snmp-exporter.
- Grafana admin password was changed in UI; `grafana-admin-pass.txt` is stale (known).

### homeassistant / opnsense

- HA responding on :8123 (200).
- OPNsense web UI responding (200) at https://192.168.1.1; SSH blocked (as documented).

### DNS (from burndev, OPNsense resolver)

| Name | Resolution | Status |
|---|---|---|
| homeassistant.lan | 192.168.1.129 | OK |
| kwsdisplay.lan | 192.168.1.168 | OK |
| burndev.lan | 192.168.1.50 | OK |
| pve.lan | 192.168.1.41 | OK |
| opnsense.lan | <WAN-IP> (WAN) | **Broken** |
| synology.lan | none | **Broken** |
| proxmox1.lan / proxmox2.lan | none | **Broken** (no longer relevant) |

---

## 9. Documentation vs Live State (Discrepancy List)

| Doc | Stale content |
|---|---|
| `README.md` (repo + docs) | Server table lists burndev as "k3s + Docker" primary; service map shows burndev central with old `.burndev.lan`/`.homelab.lan` trees; k3s reinstall commands reference burndev single node |
| `docker-services.md` | Entire architecture section (Caddy on burndev host network, domain trees, burndev service inventory) is obsolete; Portainer, UniFi, Cannery, Downtify, Linkwarden, FileBrowser entries no longer deployed |
| `runbook.md` | Recovery/clean-install steps assume burndev Docker + single-node k3s |
| `k3s-single-node-setup.md` | Describes single-node k3s on burndev with nginx-ingress; live is 3-node PVE k3s, no ingress (NodePorts + caddy) |
| `k3s-troubleshooting.md` | Node names/IPs are the old burndev cluster |
| `storage.md` | Storage classes / NFS provisioner based on burndev k3s (single-node) |
| `monitoring.md` | kube-state-metrics on old k3s; OPNsense exporter details |
| `networking.md` | Port map and domain trees are stale; `10.30.0.0/24` (vmbr1) and `10.31.0.0/24` (vmbr2) undocumented |
| `security.md` | Old burndev socket-proxy / NetworkPolicy assumptions |
| `home-assistant-*.md` | Not re-verified this audit; HA itself is up |
| `pi-agent-setup.md` | pi-agent LXC 102 verified live (matches) |
| `vikunja-management.md` | Vikunja now runs on pve-exu LXC 112, not burndev |

### Inventory vs Live State

- pve-core: docs list only LXC 102. Live also has 103 (caddy), 110 (identity), 114 (files),
  115 (operations), 120 (k3s-core). PVE now 9.2.6 (docs said 9.1.1 needing update).
- pve-gpu: docs list 100, 201–204. Live also has 101 (caddy), 205 (qbit), 122 (k3s-gpu).
  Servarr CTs are on `10.30.0.x` (vmbr1), not the LAN — not reflected in docs.
- pve-exu: docs match (111, 112, 113, 116, 121). PVE still 9.1.1.
- burndev: add Samba (`[pool]` share) and pool dirs `Burney`, `call-transcript`, `ytdlp`.
- burndev inventory note: "Jellyfin CT 100, Sonarr/Radarr/Lidarr CTs 201–203" live — confirmed,
  plus prowlarr 204 and qbit 205.

---

## 10. Recommendations

1. **Tracking first**: commit `docs/` (and the migration work on `local`) so documentation is
   actually under version control, then base all doc updates on a tracked tree.
2. **Rewrite the core topology docs** (`README.md`, `docker-services.md`, `networking.md`,
   `runbook.md`, `storage.md`, `monitoring.md`) for the PVE cluster layout in sections 4–6.
3. **Update the opencode inventory** for pve-core, pve-gpu, pve-exu, and burndev (add the new
   LXCs, qbit, caddy instances, networks, Samba).
4. **Fix DNS**: `opnsense.lan` should resolve to 192.168.1.1; add/repair `synology.lan`;
   drop stale `proxmox1/2.lan` records.
5. **Restore the caddy 116 Caddyfile** so its config is reproducible (currently admin-API only).
6. **Update pve-exu** to PVE 9.2.6 to match the other two nodes.
7. Clarify the purpose of LXC 114 `files` (no service listening).

---

*Audited from openbench on 2026-08-06. Hosts probed via SSH aliases; k3s status verified via
NodePort HTTP probes and caddy admin API.*
