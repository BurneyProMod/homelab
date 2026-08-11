# Homelab Documentation

Technical reference for the Burney homelab — setup procedures, best practices,
troubleshooting guides, and security policies.

## Documents

### Core Infrastructure

| Document | Description |
|----------|-------------|
| [proxmox-cluster.md](proxmox-cluster.md) | Current 3-node Proxmox topology, LXCs/VMs, storage, HA caddy pair, migration status |
| [service-inventory.md](service-inventory.md) | Live service inventory (media, apps, k3s) |
| [backup-layout.md](backup-layout.md) | Synology backup structure and scheduling |
| [runbook.md](runbook.md) | Recovery, clean install, rollback, backup/restore procedures |
| [k3s-single-node-setup.md](k3s-single-node-setup.md) | K3s cluster architecture, bootstrap, Ansible details, storage classes |
| [k3s-troubleshooting.md](k3s-troubleshooting.md) | CrashLoopBackOff, NotReady nodes, CNI issues, kubectl contexts, etcd recovery |
| [docker-services.md](docker-services.md) | Caddy reverse proxy architecture, service inventory, port bindings, deploy order |
| [networking.md](networking.md) | DNS, OPNsense config, hairpin NAT, port map, NetworkPolicy |
| [storage.md](storage.md) | Storage classes, NFS provisioner, PVC migration, data survival |
| [monitoring.md](monitoring.md) | Prometheus/Grafana/Blackbox setup, alert rules |
| [best-practices.md](best-practices.md) | Repo structure, deployment/troubleshooting order, common gotchas |

### Security & Access

| Document | Description |
|----------|-------------|
| [security.md](security.md) | Secrets policy, gitignore strategy, NetworkPolicy, TLS, socket proxy, audit findings |
| [ssh-key-management.md](ssh-key-management.md) | SSH keys, deploy keys, Pi agent access, HA filesystem layout and MCP tools |

### Home Assistant

| Document | Description |
|----------|-------------|
| [home-assistant-git-backup.md](home-assistant-git-backup.md) | Config version control, GitHub deploy keys, .gitignore, security audit, public repo prep |
| [home-assistant.md](home-assistant.md) | HA overview (MCP tools, dashboards, Python transforms) |
| [home-assistant-energy-monitoring.md](home-assistant-energy-monitoring.md) | Emporia Vue 3, ESPHome config, CT clamp debugging |
| [home-assistant-integrations.md](home-assistant-integrations.md) | ESPHome/Emporia Vue, HA-MCP server, Assist exposure |
| [home-assistant-management.md](home-assistant-management.md) | Device cleanup, dashboard editing, automation design |

### Tools

| Document | Description |
|----------|-------------|
| [pi-agent-setup.md](pi-agent-setup.md) | Pi coding agent configuration, sessions, skills, MCP servers |
| [vikunja-management.md](vikunja-management.md) | Vikunja project organization, CSV import, best practices |

### Projects

| Document | Description |
|----------|-------------|
| [statclock.md](statclock.md) | ESP32 CS2 stat-tracking display, Go CLI, FACEIT API |

## Quick Reference

### Servers

| Host | IP | Role |
|------|----|------|
| pve-core | 192.168.1.30 | Proxmox node 1 — HA primary (identity, files, operations, caddy 103) |
| pve-exu | 192.168.1.31 | Proxmox node 3 — HA primary (immich, docker-apps, archives) |
| pve-gpu | 192.168.1.32 | Proxmox node 2 — quorum/K3s, GPU (jellyfin, servarr, caddy 101) |
| k3s VMs | 192.168.1.70/71/72 | 3-node k3s cluster (k3s-core/exu/gpu) |
| burndev | 192.168.1.50 | NFS media share + Ollama (workloads migrated off) |
| synology | 192.168.1.11 | NAS — NFS storage, backups |
| homeassistant | homeassistant.lan | Home Assistant (dedicated Pi) |
| opnsense | 192.168.1.1 | Gateway — DNS, DHCP, routing, firewall |
| kwsdisplay | 192.168.1.168 | Display kiosk + monitoring (Grafana) |

See [proxmox-cluster.md](proxmox-cluster.md) for the full Proxmox topology and [service-inventory.md](service-inventory.md) for all live services.

### Devices

| Device | IP | Notes |
|--------|----|-------|
| Emporia Vue 3 | 192.168.1.139 | Energy monitoring (ESPHome) |
| statclock ESP32 | DHCP | CS2 stat-tracking display |
| kws-rpi-1 | DHCP | Klipper 3D printer controller |

### Key Commands

```bash
# Health check (run on a k3s VM, e.g. ssh npburney@192.168.1.71)
sudo kubectl get nodes && sudo kubectl get pods -A

# Proxmox backups (per-node storage, daily 02:00, keep-last 2)
#   pve-core -> backups/hosts/proxmox/pve-core/dump/
#   pve-gpu  -> backups/hosts/proxmox/pve-gpu/dump/
#   pve-exu  -> backups/hosts/proxmox/pve-exu/dump/

# Backup homelab repo to NAS
bash scripts/backup.sh

# Host/service backups (run from burndev crontab):
#   backup-burndev-host.sh, backup-kwsdisplay-host.sh, backup-grafana.sh,
#   backup-home-assistant.sh, sync-rsyslog.sh
# pve-exu host: /usr/local/sbin/backup-docker-services.sh, backup-kubernetes.sh

# Preview restore from NAS (safe, no changes)
bash scripts/pull-from-nas-backup.sh --dry-run

# Validate all manifests
make validate
```

### Important Paths

| Path | Purpose |
|------|---------|
| `~/dev/homelab/` | Infrastructure repo |
| `~/dev/homelab/docker/` | Docker compose stacks |
| `~/dev/homelab/docker/caddy/certs/` | Caddy TLS certificates (runtime) |
| `~/dev/homelab/docker/caddy/data/` | Caddy ACME data (runtime) |
| `~/dev/homelab/config/caddy/Caddyfile` | HA caddy pair config source of truth |
| `~/dev/homelab/kubernetes/` | K8s manifests |
| `~/dev/homelab/ansible/` | Ansible playbooks |
| `~/dev/homelab/scripts/` | Backup, deploy, restore scripts |
| `/mnt/syn/` | Synology NAS mount point on burndev |
| `/mnt/syn/repo/` | Repo mirror |
| `/mnt/syn/backups/` | Backup destination (hosts/, services/, archive/) |
| `/mnt/syn/logs/rsyslog/` | Centralized syslog |
| `~/.ssh/config` | SSH aliases for all servers |

### Service Map

```
                          internet
                              |
                     +--------+--------+
                     |   OPNsense      |
                     | 192.168.1.1     |
                     | DNS + NAT       |
                     +--------+--------+
                              |
                  keepalived VIP 192.168.1.10  (*.burney.network)
                              |
                     +--------+--------+
                     | HA Caddy pair   |
                     | 103 + 101       |
                     +--------+--------+
                              |
         +--------------------+--------------------+
         |                    |                    |
  Proxmox cluster      Synology NAS        Home Assistant
  pve-core/gpu/exu     .1.11 NFS          homeassistant.lan
  LXCs + k3s VMs       backups
```
