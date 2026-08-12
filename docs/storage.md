# Storage Architecture

## Current architecture (2026-08-07)

Workloads run on the 3-node Proxmox cluster backed by a single Synology NFS4 export `/volume1/homelab` mounted at `/mnt/synology/homelab` on all three nodes (fstab: vers=4.1, _netdev, nofail, x-systemd.automount). A second export `/volume1/immich` is mounted at `/mnt/synology/immich` on pve-core and pve-exu.

### Proxmox storage definitions (cluster-wide `/etc/pve/storage.cfg`)

| Storage | Path | Content | Purpose |
|---------|------|---------|---------|
| synology-ha | `/mnt/synology/homelab/proxmox-ha` | images, rootdir | LXC rootfs |
| synology-k8s | `/mnt/synology/homelab/proxmox-k8s` | images | future k3s CSI |
| syn-backups-core | `/mnt/synology/homelab/backups/hosts/proxmox/pve-core` | backup | vzdump target (daily 02:00, keep-last 2) |
| syn-backups-gpu | `/mnt/synology/homelab/backups/hosts/proxmox/pve-gpu` | backup | vzdump target (daily 02:00, keep-last 2) |
| syn-backups-exu | `/mnt/synology/homelab/backups/hosts/proxmox/pve-exu` | backup | vzdump target (daily 02:00, keep-last 2) |
| local | `/var/lib/vz` | iso, backup, import, vztmpl | local boot/template |
| local-lvm | lvmthin `data` | rootdir, images | VM root disks |

### K3s cluster PVCs

- **StorageClass**: `local-path` (rancher.io/local-path, WaitForFirstConsumer, Delete).
- **Data path** on each VM: `/var/lib/rancher/k3s/storage/`.
- PVCs (4d13h, 2026-08-03): homepage-images (k3s-gpu), code-server-data (k3s-gpu), kanboard-data (k3s-exu), trilium-data (k3s-core).
- **Warning**: local-path provisions hostPath volumes on the node where the pod is first scheduled. A PV has nodeAffinity to that node, so the pod cannot move. Not HA — CSI migration is a known issue.

## Historical (burndev single-node k3s, decommissioned)

### Storage Classes

| Storage Class | Backend | Access Mode | Use Case |
|--------------|---------|-------------|----------|
| `nfs` | Synology NAS (192.168.1.11) via NFS provisioner | ReadWriteMany | Shared configs, code-server workspaces, Grafana dashboards, Kanboard data |
| `local-path` | Local node disk (/var/lib/rancher/k3s) | ReadWriteOnce | App data that doesn't need to survive node failure |
| `immich-upload-manual` | Synology NAS (manual PV, `/volume1/immich`) | ReadWriteMany | Immich photo/video uploads |

### PVC Migration Notes (burndev-era)

| Old PVC | New PVC | Old SC | New SC |
|---------|---------|--------|--------|
| `termix-data-proxmox` | `termix-data` | `proxmox-local` | `local-path` |
| `trilium-data-proxmox` | `trilium-data` | `proxmox-local` | `local-path` |
| `immich-postgres-data` | `immich-postgres-data` | `proxmox-local` | `local-path` |

## Backup storage layout

See `backup-layout.md`. Synology `homelab` share mounted on burndev at `/mnt/syn` and on PVE nodes at `/mnt/synology/homelab`.

## Per-user service content on the homelab share (2026-08-12)

The Synology `homelab` share hosts only **content** for these services under
`homes/npburney/<service>/` (exposed to guests as `homes/`). Application state
(configs, databases) stays on the default storage: LXC rootfs / docker volumes
for LXCs, `local-path` PVCs for k3s.

| Service | Host | Content on share | App state location | Mount |
|---------|------|------------------|--------------------|-------|
| stash | pve-exu LXC 123 | `homes/npburney/stash/` (media library) | `./config,./blobs,./cache,./generated,./metadata` in compose dir (LXC) | LXC `mp1` -> `/srv/stash`; `STASH_STASH=/srv/stash` |
| paperless | pve-exu LXC 119 | `homes/npburney/paperless/` (media: `documents/`) | named volumes `data`,`pgdata`,`redisdata`; `./consume`,`./export` | LXC `mp1` -> `/srv/paperless-data` -> `/usr/src/paperless/media` |
| manyfold | k3s | `homes/npburney/manyfold/models`, `plugins` | `manyfold-config` PVC (local-path, 1Gi) -> `/config` (sqlite) | NFS PV `manyfold-data` subPath `models` -> `/models`, `plugins` -> `/usr/src/app/plugins` |

Notes:
- NFS ownership is checked server-side with the client's mapped uid. LXC subuid base is 100000
  (container uid 0 -> host 100000; uid 1000 -> 101000; uid 999 -> 100999). k3s VMs have no
  idmapping, so pod uid 1000 == share uid 1000.
- The `homelab` share has Synology snapshot protection (`@sharesnap/homelab`), which covers
  this content directory directly. App state on LXC rootfs / local-path is covered by
  vzdump / the k8s backup job.
