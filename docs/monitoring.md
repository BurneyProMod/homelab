# Monitoring Stack

## Current architecture

Monitoring runs on the **kwsdisplay** rack kiosk (192.168.1.168) as Docker Compose at `/opt/docker/monitoring/`.
The old kube-prometheus-stack on the burndev single-node k3s is decommissioned; the k3s cluster is scraped via kube-state-metrics.

## Services (kwsdisplay)

| Service | Port |
|---------|------|
| Prometheus | 127.0.0.1:9090 |
| node-exporter | 127.0.0.1:9100 |
| blackbox-exporter | 9115 |
| snmp-exporter | 127.0.0.1:9116 |
| Grafana | 3000 |
| Uptime-Kuma | 3001 |

## Scrape targets

- **blackbox-icmp** (11): gateway .1, internet 1.1.1.1, synology .11, pve-core .30, pve-exu .31, pve-gpu .32, immich LXC .61, k3s-core .70, k3s-exu .71, k3s-gpu .72, kwsdisplay .168
- **blackbox-http** (9): homeassistant.lan:8123, 192.168.1.61:2283 (immich), 192.168.1.168:3001, jellyfin.lan, sonarr.lan, radarr.lan, lidarr.lan, prowlarr.lan, qbit.lan
- **kube-state-metrics** (3): 192.168.1.70/.71/.72:30100 (scrape all three nodes so one down does not kill the job)
- **opnsense**: 192.168.1.1:9100 (os-node_exporter; Network Interface Statistics must be enabled; WAN interface igc0)
- **node**: node-exporter:9100 (kwsdisplay itself)

Scrape interval 15s, retention 30d. Config: `/opt/docker/monitoring/prometheus/prometheus.yml`.

## Kiosk

- Chromium → Grafana "Homelab Overview" dashboard (uid `homelab-overview`), 1280×400 banner.
- Recovery: `sudo systemctl restart getty@tty1`. Do NOT pkill chromium (`~/.xinitrc` execs it as the X session leader).
- Failure-code scheme, anti-flap windows, and query patterns are documented in the Trilium "Homelab Overview dashboard" note.

## Deploy procedure

```
cd /opt/docker/monitoring
cp -a . ~/backups/monitoring.bak-$(date +%Y%m%d-%H%M%S)   # backup first
# edit prometheus.yml and/or provisioning/dashboards/*.json
docker exec prometheus promtool check config /etc/prometheus/prometheus.yml   # only if prometheus.yml changed
docker kill -s HUP prometheus                             # only if prometheus.yml changed
# Grafana provisioning hot-reloads dashboard JSON on its own; allow ~30-60s
```

- Validate exprs on kwsdisplay: `curl -s "http://127.0.0.1:9090/api/v1/query" --data-urlencode 'query=...'`
- Grafana API is readable anonymously: `curl -s http://127.0.0.1:3000/api/dashboards/uid/homelab-overview`
- Admin: username `admin`. Password changed in the UI on 2026-08-04 (not stored in Trilium); `grafana-admin-pass.txt` is stale.

## Notes

- Monitoring config is not tracked in the homelab repo (a total rebuild is planned).
- kube-state-metrics manifest is hand-written, not in the repo.
- Backed up to Synology by `backup-kwsdisplay-host.sh` (daily 01:30) and `backup-grafana.sh` (daily 01:45).

Last verified: 2026-08-07
