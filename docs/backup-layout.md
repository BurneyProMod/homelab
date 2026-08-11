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
