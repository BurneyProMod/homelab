# HA Caddy front-end — config source of truth

Reverse proxy config for the two-node HA Caddy pair that fronts all homelab
web services on the PVE cluster. Live as of 2026-08-07.

## Nodes

| Node | LXC | IP | keepalived priority |
|---|---|---|---|
| pve-core | 103 | 192.168.1.42 | 150 (preferred master) |
| pve-gpu | 101 | 192.168.1.40 | 100 |

Both serve the identical `Caddyfile`. keepalived shares virtual IP
**192.168.1.10** between them (VRRPv3, unicast peers, no auth). Verified:
VIP failover to the standby in ~8s when the master's caddy stops, and failback.

## Deployment

1. Copy `Caddyfile` to `/etc/caddy/Caddyfile` on both nodes.
2. Copy `env.example` to `/etc/caddy/.env` on both nodes and fill in values.
   Load it in the caddy unit via `EnvironmentFile=/etc/caddy/.env`.
3. Copy `root_ca.crt` (step-ca root, from `../step-ca/`) to `/etc/caddy/root_ca.crt`.
4. Deploy `keepalived.conf` per node (see `keepalived.conf.example` for the
   four per-node lines) + `check_caddy.sh` to `/usr/local/sbin/`.
5. Deploy `crossroutes.sh` + `crossroute.service` (systemd oneshot) so each
   node reaches the sibling node's isolated net during failover. Requires
   `net.ipv4.ip_forward=1` on pve-core (pve-gpu already forwards).
6. On the backup (caddy 101) only: `sync-caddy-certs.sh` +
   `caddy-cert-sync.timer` (5 min) mirror the master's cert store; SSH key
   `/root/.ssh/id_ed25519_root_caddy-gpu` -> caddy-core authorized_keys.
7. `systemctl enable --now caddy keepalived crossroute` on both nodes.

## TLS / step-ca

HTTP-only sites stay on `http://`. The three TLS sites (`openbao`, `pi`,
`pve.lan`) are issued by the single step-ca "Burney Home CA"
(`config/step-ca/root_ca.crt`) via the global `acme_ca` block.

Only the keepalived VIP holder can pass step-ca's tls-alpn-01 validation,
because step-ca probes the DNS name which points at the VIP. The master
renews; the backup mirrors the cert store (`sync-caddy-certs.sh`). To change
the CA, edit the `acme_ca`/`acme_ca_root` global options.

`pve.lan` -> Proxmox web UI (192.168.1.30:8006, upstream TLS not verified) is a
new addition for the one-front-IP goal.

## Sources

Captured 2026-08-06 from live instances:

- `caddy 116` (pve-exu, 192.168.1.41) — `*.pve.lan` tree. Caddyfile was NOT on
  disk; reconstructed from the admin API at `127.0.0.1:2019` (server srv0 = :443
  openbao with internal TLS; server srv1 = :80 plain HTTP for the rest).
- `caddy 101` (pve-gpu, 192.168.1.40) — `*.lan` arr/jellyfin/qbit tree, all `http://`.
- `caddy 103` (pve-core, 192.168.1.42) — `pi.lan`, basic auth, LAN/WireGuard only.

`caddy 116` is retired (Phase 5): its whole `*.pve.lan` tree now runs on the pair.

## DNS (OPNsense Unbound, live 2026-08-07)

- Wildcard `*.pve.lan` -> 192.168.1.10 (VIP). All pve.lan services served by the pair.
- `pve.lan` -> 192.168.1.10, `pi.lan` -> 192.168.1.10.
- `sonarr.lan`, `radarr.lan`, `lidarr.lan`, `prowlarr.lan`, `jellyfin.lan`, `qbit.lan`
  -> 192.168.1.10.
- `stepca.pve.lan` intentionally does NOT exist: Unbound cannot have a host
  override inside a wildcard redirect zone (it crashes the resolver). step-ca is
  reached at https://192.168.1.43 directly (its serving cert has the IP SAN).
- `homeassistant.lan` -> .129, `kwsdisplay.lan` -> .168, `burndev.lan` -> .50,
  `opnsense.lan` -> 192.168.1.1 (OK). `synology.lan` does not resolve (broken).
