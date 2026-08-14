# Homelab Backup Layout (Synology `homelab` share)

Mount: `192.168.1.11:/volume1/homelab`
- burndev: `/mnt/syn`
- PVE nodes: `/mnt/synology/homelab`

## Structure

```
repo/                          # git mirror of the homelab repo (BurneyProMod/homelab)
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
  homelab/                     # host-aware app-data backup (runner = ops LXC 115)
    docker/<label>/<src-slug>/ # compose project dirs (bind-mounted data + configs)
    docker/<label>/volumes/    # named docker volumes (_data)
    native/<label>/<src-slug>/ # native service data (/var/lib/jellyfin, /var/lib/sonarr, /etc/caddy ...)
    k8s/<node>/                # local-path PVC storage per k3s node (k3s-core/exu/gpu)
    postgres/<label>/          # pg_dumpall / pg_dump SQL dumps (retention: 7)
  archive/                     # old ad-hoc snapshots (08022026)
logs/
  rsyslog/                     # centralized syslog (pve-*, burndev, opnsense, legacy)
```

The old `backups/services/` layout (docker/kubernetes/immich/klipper/step-ca) was
retired 2026-08-11 in favor of the host-aware `backups/homelab/` tree below.

## Scheduling

burndev crontab:
- repo: Sun 03:00
- burndev host: daily 01:00
- kwsdisplay host: daily 01:30
- grafana: daily 01:45
- home-assistant: daily 02:15

ops LXC 115 crontab (daily 04:00):
- `bash /mnt/synology/homelab/repo/scripts/backup-app-data.sh`

PVE vzdump jobs (`/etc/pve/jobs.cfg`): daily 02:00, keep-last 2, per-node storage.

The retired pve-exu `/etc/cron.d/homelab-backups` schedule (docker services 04:00,
kubernetes 05:00) was removed when the host-aware runner moved to LXC 115.

## Restore notes

- Repo/secrets: rsync `/mnt/syn/repo/` back; `--delete` safe.
- vzdump: restore via Proxmox UI or `vzdump --restore`.
- Home Assistant: restore tar via the HA UI (Settings > Backups > Upload).
- App data: `scripts/restore-app-data.sh` — manual only, never scheduled,
  dry-run default, requires `--force` + interactive confirmation. As of
  2026-08-13 actual restores are HARD-DISABLED pending review of the
  ownership/Caddy/k3s fixes (the script exits 1 on `--force`).

## App-data backup (host-aware, runner = ops LXC 115)

Since 2026-08-11 the per-service app-data backup is host-aware and runs from
the **operations LXC 115** (192.168.1.65) via a dedicated SSH key
(`~/.ssh/id_ed25519_backup`) distributed to the docker/native LXCs and k3s
nodes. It writes to `backups/homelab/` on the Synology.

- Script: `scripts/backup-app-data.sh` (runs from the repo on the NAS mount).
- Schedule: LXC 115 crontab, daily 04:00
  (`bash /mnt/synology/homelab/repo/scripts/backup-app-data.sh`).
- Guest access: direct SSH to LAN guests; media VLAN (10.30.0.0/24) guests via
  the caddy LXC 101 (192.168.1.40) as ProxyJump; k3s PVCs rsync with
  `--rsync-path="sudo rsync"` (npburney).
- Consistency (2026-08-13): docker guests without a postgres dump are stopped
  (`docker compose stop`) before copying and started after, so SQLite/file data
  is consistent; k3s app workloads (default+tools) are scaled to 0 during the
  PVC rsync and scaled back to their original replica counts afterwards.
- Ownership (2026-08-13): each data dir carries a `.owners` manifest
  (`uid|gid|type|relpath`) captured at backup time; the unprivileged runner
  (uid 100000 on the NAS) cannot chown on the NFS mount. Restore applies the
  manifest as root on the guest side.
- Backup root owned by the runner UID (100000) so the unprivileged LXC can write.
