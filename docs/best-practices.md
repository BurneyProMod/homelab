# Homelab Best Practices

## Repository Structure

```
~/dev/homelab/
├── AGENTS.md              # AI agent instructions (deployment order, secrets, gotchas)
├── README.md              # Human-readable overview
├── Makefile               # Common operations (deploy, validate)
├── ansible/               # K3s bootstrap playbooks
│   ├── inventory/
│   │   ├── hosts.ini       # Server inventory (burndev only)
│   │   ├── group_vars/     # Global vars (k3s_version, ansible_user)
│   │   └── host_vars/      # Per-host overrides
│   ├── roles/
│   │   ├── common/         # Kernel modules, sysctl, UFW, packages
│   │   ├── control_plane/  # K3s server install
│   │   └── worker/         # K3s agent install (preserved for future scale-out)
│   └── site.yml            # Top-level playbook
├── config/homepage/        # Homepage dashboard config (synced to NAS)
├── docker/                 # Per-service Docker compose stacks
│   ├── caddy/              # Edge proxy (deploy FIRST)
│   ├── immich/             # Photo backup
│   ├── jellyfin/           # Media server
│   ├── servarr/            # Sonarr/Radarr/Lidarr/Prowlarr/qBittorrent
│   ├── actual-budget/      # Budgeting
│   ├── vikunja/            # Task management
│   ├── scanopy/            # Network device discovery
│   ├── cannery/            # Pantry management
│   ├── rackpeek/           # Server monitoring
│   └── socket-proxy/       # Docker API proxy for Homepage
├── kubernetes/
│   ├── apps/               # K8s app manifests (Deployments, Services, Ingresses)
│   ├── cert-manager/       # CA issuer + install script
│   ├── monitoring/         # Grafana, Prometheus rules, Blackbox config
│   ├── namespaces/         # Namespace definitions
│   └── policies/           # NetworkPolicy (default-deny per namespace)
├── scripts/
│   ├── backup.sh           # Rsync repo to NAS
│   ├── sync-homepage.sh    # Sync homepage config to NAS NFS share
│   └── deploy-k8s.sh       # Apply all K8s manifests in order
└── docs/                   # This documentation
```

## Git Hygiene

### What to commit
- All YAML manifests, playbooks, scripts, configs
- Example secret files (`*secret.example.yml`, `.env.example`)
- Documentation

### What NEVER to commit
- `.env` files (real secrets)
- `*secret.yml` (real K8s secrets)
- `*.pem`, `*.key`, `.crt` (TLS private keys)
- `*.log` (log files)
- Docker volume data (in `docker/*/data/`, `docker/*/config/`)
- Terraform `.tfstate`, `.tfvars` (if reintroduced)

### Docker directory whitelist

`.gitignore` uses an inverse pattern — everything under `docker/` is ignored EXCEPT `compose.yaml` and `.env.example`:

```gitignore
/docker/**
!/docker/**/
!/docker/**/compose.yaml
!/docker/**/.env.example
```

This prevents accidental commits of large volume data (Jellyfin cache, Sonarr media covers, Immich database).

## Deployment Order

**Strictly ordered. Each step depends on the previous.**

1. **K3s bootstrap**: `ansible-playbook -i ansible/inventory/hosts.ini ansible/site.yml`
2. **Cert-manager**: `bash kubernetes/cert-manager/install-cert-manager.sh && kubectl apply -f kubernetes/cert-manager/ca-issuer.yml`
3. **nginx-ingress**: `kubectl apply -f <nginx-ingress-manifest-url>`
4. **K8s manifests**: namespaces → policies → apps → monitoring
5. **Caddy (Docker)**: `cd docker/caddy && docker compose up -d`
6. **Remaining Docker stacks**: Immich, Jellyfin, arr stack, tools

## Troubleshooting Order

When something breaks, investigate in this order:

1. **Caddy** — if edge proxy is down, nothing routes
2. **DNS** — verify `*.burndev.lan` and `*.homelab.lan` resolve to `192.168.1.50`
3. **NAS mount** — NFS being down breaks all NFS-backed PVCs
4. **K3s** — `kubectl get nodes`, check if API server is responding
5. **nginx-ingress** — `kubectl -n ingress-nginx get pods`
6. **cert-manager** — certificate renewal failures show as TLS errors

## Common Gotchas

### nginx-ingress not installed
Symptom: All Ingress resources fail with webhook errors.
Fix: Install nginx-ingress (k3s disabled Traefik, doesn't include nginx).

### Wrong ansible_user
Symptom: `Permission denied (publickey,password)` for `debian@192.168.1.50`.
Fix: Change `ansible_user: npburney` and `ansible_connection: local` when running on burndev itself.

### prometheus scrape configs applied with kubectl
Symptom: YAML parse errors on `blackbox-values.yml` or `prometheus-additional-scrape.yml`.
Fix: These are Helm inputs, not manifests. They're consumed by the kube-prometheus-stack chart.

### Storage class mismatch
Symptom: PVCs stuck in Pending after migrating from Proxmox.
Fix: Old `proxmox-local` PVCs were renamed to use `local-path` or `nfs`. Verify storage classes exist: `kubectl get storageclass`.

### DNS hairpin
Symptom: Internal clients can't reach homelab services by domain.
Fix: Enable NAT reflection in OPNsense, or ensure internal DNS resolves directly to `192.168.1.50`.

## AI Agent Conventions (AGENTS.md)

The `AGENTS.md` file at the repo root governs AI agent behavior:

- **Vikunja**: Read-only by default; mutations require explicit request
- **Secrets**: Never commit; use example files
- **Deployment**: Strictly ordered; must follow sequence
- **Homelab inventory**: Load skill before homelab operations
- **Context**: Use explicit `--context default` for all kubectl commands targeting burndev
- **Architecture**: burndev is single-node k3s + Docker; no Proxmox VMs
