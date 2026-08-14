# HA Caddy front-end — config source of truth

Reverse proxy config for the two-node HA Caddy pair that fronts all homelab
web services. Live as of 2026-08-07.

## Architecture

- **Nodes**: caddy 103 (pve-core, 192.168.1.42, keepalived prio 150) + caddy 101
  (pve-gpu, 192.168.1.40, prio 100), both Debian 13, caddy 2.11.4 (built with
  `caddy-dns/cloudflare`), identical `Caddyfile`.
- **VIP**: keepalived shares **192.168.1.10** (VRRPv3, unicast, no auth).
  Failover ~8s verified both directions.
- **Names**: all services live on `*.burney.network`. LE certs via Cloudflare
  DNS-01 (TXT only — no public A records, no WAN exposure). Both nodes issue and
  renew independently.
- **Access**: LAN `192.168.1.0/24` + WireGuard `10.8.0.0/24` + loopback only;
  Caddy returns 403 for anything else. OPNsense allows no WAN -> VIP.
- **TLS resolvers**: the DNS challenge uses `1.1.1.1` so certmagic can find the
  zone SOA (OPNsense has no SOA for burney.network) and see Cloudflare writes.

## Deployment

1. Build caddy with the cloudflare module (both nodes):
   `xcaddy build --with github.com/caddy-dns/cloudflare`, install to `/usr/bin/caddy`.
2. Copy `Caddyfile` to `/etc/caddy/Caddyfile` on both nodes.
3. Copy `env.example` to `/etc/caddy/.env` on both nodes; fill
   `CLOUDFLARE_API_TOKEN` and `PI_BASIC_AUTH_HASH`. Load via
   `EnvironmentFile=/etc/caddy/.env` in the caddy unit (chmod 600).
4. Deploy `keepalived.conf` per node (see `keepalived.conf.example` for the four
   per-node lines) + `check_caddy.sh` to `/usr/local/sbin/`.
5. Deploy `crossroutes.sh` + `crossroute.service` (systemd oneshot) so each node
   reaches the sibling node's isolated net during failover. Requires
   `net.ipv4.ip_forward=1` on pve-core.
6. `systemctl enable --now caddy keepalived crossroute` on both nodes.

## DNS

Internal (OPNsense Unbound): single wildcard override `*` / `burney.network` ->
192.168.1.10 (split-horizon). Do NOT add other host overrides inside
`burney.network` — Unbound crashes on a record inside a wildcard redirect zone.

Public (Cloudflare): no A records needed for service names (DNS-01 uses TXT
only). Existing `trilium.burney.network -> <WAN-IP>` A record predates this
setup and should be removed to keep the no-WAN guarantee airtight.

## Notes

- `pve.burney.network` -> Proxmox web UI (192.168.1.30:8006, upstream TLS not
  verified). `pi.burney.network` -> pi-agent (10.31.0.2:43121) with basic auth.
- OpenBao is served on both :80 and :443.
- Previously used a step-ca internal CA (Burney Home CA, retired) with a
  master->backup cert-sync timer; superseded by the public-cert architecture.
- App base URLs: most apps serve on the request host, so no per-app renames were
  needed. Fix any app that redirects back to a `.lan` name reactively.
