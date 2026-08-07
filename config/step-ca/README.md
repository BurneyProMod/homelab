# step-ca — Burney Home CA

Single internal certificate authority for the whole homelab. Root: **Burney Home CA**
(valid 2026-08-07 → 2036-08-04, SHA256 fingerprint
`A7:C4:B5:44:3F:9C:0C:70:71:E4:2D:87:80:89:39:36:13:FF:12:BC:1D:03:33:13:50:2A:8B:9F:5A:A0:05:52`).
Every Caddy instance (and future services) signs certificates from this one CA, so
clients trust the root once and the whole homelab is trusted.

## Instance

- LXC 117, hostname `stepca`, on **pve-exu**, Debian 13, 192.168.1.43 (vmbr0/LAN).
- URL: `https://stepca.pve.lan:443` (also serves `192.168.1.43` as SAN).
- ACME directory: `https://stepca.pve.lan/acme/acme/directory` (provisioner `acme`).

## Layout

| Path | Contents |
|---|---|
| `/etc/step-ca/config/ca.json` | CA config (paths, provisioners, claims) |
| `/etc/step-ca/certs/` | `root_ca.crt` (public, distribute), `intermediate_ca.crt` |
| `/etc/step-ca/secrets/` | `intermediate_ca_key`, `root_ca_key`, `password` (32-byte CA password) |
| `/etc/step-ca/db/` | Badger v2 certificate/ACME-account database |

- Provisioners: `admin` (JWK, admin), `acme` (ACME, used by Caddy).
- Secrets live in git-ignored `config/step-ca/.env` (`STEPCA_PASSWORD`), also on
  Synology at `backups/step-ca/`.
- Service: systemd `step-ca.service`, runs as root, `STEPPATH=/etc/step-ca`
  (`/etc/default/step-ca`), `--password-file /etc/step-ca/secrets/password`.

## Backups

One-shot backup on Synology: `pve-exu:/mnt/synology/homelab/backups/step-ca/step-ca-YYYYMMDD.tar.gz`.
Restore drill and scheduled backup are Phase 7 work. To back up cleanly, stop
`step-ca` before tarring the badger DB, then start it.

## Operations

- Health: `step ca health --ca-url https://192.168.1.43:443 --root /etc/step-ca/certs/root_ca.crt`
- Add a provisioner by editing `ca.json` directly (the step CLI in 0.30 defaults
  to `/root/.step` unless a context is configured) and `systemctl restart step-ca`.
- Client trust: install `config/step-ca/root_ca.crt` into each device's trust store.

## DNS

`stepca.pve.lan` must resolve to 192.168.1.43 (currently covered by the
`*.pve.lan` wildcard → 192.168.1.41; a specific override is required).
