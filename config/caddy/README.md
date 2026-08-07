# HA Caddy front-end — config source of truth

Reverse proxy config for the two-node HA Caddy pair that fronts all homelab
web services on the PVE cluster.

## Nodes

| Node | LXC | IP | keepalived priority |
|---|---|---|---|
| pve-core | 103 | 192.168.1.42 | 150 (preferred master) |
| pve-gpu | 101 | 192.168.1.40 | 100 |

Both serve the identical `Caddyfile`. keepalived shares virtual IP
**192.168.1.10** between them, so one front-facing IP serves all services.

## Deployment

1. Copy `Caddyfile` to `/etc/caddy/Caddyfile` on both nodes.
2. Copy `env.example` to `/etc/caddy/.env` on both nodes and fill in values.
   Load it in the caddy unit via `EnvironmentFile=/etc/caddy/.env`.
3. Deploy the same `keepalived.conf` to both nodes (see `keepalived.conf`).
4. `systemctl restart caddy keepalived` on both nodes.

## Sources

Captured 2026-08-06 from live instances:

- `caddy 116` (pve-exu, 192.168.1.41) — `*.pve.lan` tree. Caddyfile was NOT on
  disk; reconstructed from the admin API at `127.0.0.1:2019` (server srv0 = :443
  openbao with internal TLS; server srv1 = :80 plain HTTP for the rest).
- `caddy 101` (pve-gpu, 192.168.1.40) — `*.lan` arr/jellyfin/qbit tree, all `http://`.
- `caddy 103` (pve-core, 192.168.1.42) — `pi.lan`, internal TLS, basic auth,
  LAN/WireGuard (10.8.0.0/24) only.

Protocol behavior preserved from the sources (HTTP-only sites stay on `http://`;
TLS sites use `tls internal`). Moving sites to HTTPS via the single step-ca root
is a deliberate later migration (Phase 3).

`pve.lan` -> Proxmox web UI (192.168.1.30:8006, upstream TLS not verified) is a
new addition for the one-front-IP goal.

## DNS before-state (OPNsense Unbound, 2026-08-06)

- Wildcard `*.pve.lan` -> 192.168.1.41 (caddy 116) — retarget to 192.168.1.10 at cutover.
- `pve.lan` -> 192.168.1.41 — retarget to 192.168.1.10.
- `stepca.pve.lan` -> 192.168.1.41 (wildcard) — will get a dedicated record to the step-ca LXC.
- `sonarr.lan`, `radarr.lan`, `lidarr.lan`, `prowlarr.lan`, `jellyfin.lan`, `qbit.lan`
  -> 192.168.1.40 (caddy 101) — retarget to 192.168.1.10.
- `pi.lan` -> 192.168.1.157 (a physical Pi — NOT the caddy 103 proxy; mismatch to resolve).
- `homeassistant.lan` -> .129, `kwsdisplay.lan` -> .168, `burndev.lan` -> .50,
  `opnsense.lan` -> 192.168.1.1 (OK). `synology.lan` does not resolve (broken).
