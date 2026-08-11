# Homelab Backup Layout (Synology `homelab` share)

Mount: `192.168.1.11:/volume1/homelab`
- burndev: `/mnt/syn`
- PVE nodes: `/mnt/synology/homelab`

## Structure

```
repo/                          # mirror of ~/dev/homelab (excludes live docker data)
backups/
  hosts/
    burndev/                   # config backup (crontab, /opt/docker, /etc, ~/.ssh, opencode)
    kwsdisplay/                # monitoring stack + uptime-kuma
    opnsense/                  # OPNsense config exports
    burnbox/                   # windows/ + software/ (legacy)
    legacy/                    # machines/, truenas/ (legacy)
    proxmox/
      pve-core/dump/           # vzdump backups (daily 02:00, keep-last 2)
      pve-gpu/dump/
      pve-exu/dump/
  services/
    grafana/                   # grafana.db + provisioning
    home-assistant/            # HA snapshot tars (keep 14)
    docker/                    # LXC 112 app data (daily 04:00)
    kubernetes/                # k8s manifests + PVCs (daily 05:00)
    immich/                    # legacy immich data
    klipper/                   # legacy klipper data
    step-ca/                   # legacy step-ca data
  archive/                     # old ad-hoc snapshots (08022026)
logs/
  rsyslog/                     # centralized syslog (pve-*, burndev, opnsense, legacy)
```

## Scheduling

burndev crontab:
- repo: Sun 03:00
- burndev host: daily 01:00
- kwsdisplay host: daily 01:30
- grafana: daily 01:45
- home-assistant: daily 02:15
- rsyslog sync: daily 03:30

pve-exu `/etc/cron.d/homelab-backups`:
- docker services: daily 04:00
- kubernetes: daily 05:00

PVE vzdump jobs (`/etc/pve/jobs.cfg`): daily 02:00, keep-last 2, per-node storage.

## Restore notes

- Repo/secrets: rsync `/mnt/syn/repo/` back; `--delete` safe.
- vzdump: restore via Proxmox UI or `vzdump --restore`.
- Home Assistant: restore tar via the HA UI (Settings > Backups > Upload).

## App-data backup (host-aware, runner = ops LXC 115)

Since 2026-08-11 the per-service app-data backup is host-aware and runs from
the **operations LXC 115** (192.168.1.65) via a dedicated SSH key
(`~/.ssh/id_ed25519_backup`) distributed to the docker/native LXCs and k3s
nodes. It writes to `backups/homelab/` on the Synology:

```
backups/homelab/
  docker/<label>/            compose project dirs (bind-mounted data + configs)
  docker/<label>/volumes/    named docker volumes (_data)
  native/<label>/            native (non-docker) service data (/var/lib/jellyfin, /var/lib/sonarr, /etc/caddy ...)
  k8s/<node>/                local-path PVC storage per k3s node (k3s-core/exu/gpu)
  postgres/<label>/          pg_dumpall / pg_dump SQL dumps (retention: 7)
```

- Script: `scripts/backup-app-data.sh` (runs from the repo on the NAS mount).
- Schedule: LXC 115 crontab, daily 04:00
  (`bash /mnt/synology/homelab/repo/scripts/backup-app-data.sh`).
- Guest access: direct SSH to LAN guests; media VLAN (10.30.0.0/24) guests via
  the caddy LXC 101 (192.168.1.40) as ProxyJump; k3s PVCs rsync with
  `--rsync-path="sudo rsync"` (npburney).
- Restore: `scripts/restore-app-data.sh` — **manual only, never scheduled**,
  dry-run default, requires `--force` + interactive confirmation.
- Backup root owned by the runner UID (100000) so the unprivileged LXC can write.
