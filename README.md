# Homelab

Self-sufficient Kubernetes homelab running on a single bare-metal host, provisioned with Ansible.

## Server Inventory

| Host | IP | Role | Notes |
|------|----|------|------------------|
| burndev | 192.168.1.50 | k3s server + worker | MSI X470 GAMING PLUS desktop — single-node cluster |
| Synology NAS | 192.168.1.11 | NFS storage | NAS |
| OPNsense | 192.168.1.1 | Gateway | Firewall/router |
| kwsdisplay | - | - | Raspberry Pi 4 Model B Rev 1.5 |
| kws-rpi-1 | - | - | Raspberry Pi 4 Model B Rev 1.5 |

## Running Services

### Kubernetes

| App | URL | Description |
|-----|-----|-------------|
| Homepage | `home.homelab.lan` | Dashboard |
| VS Code | `code.homelab.lan` | Browser-based IDE |
| Trilium | `trilium.homelab.lan` | Notes |
| Kanboard | `kanboard.homelab.lan` | Kanban board |
| Omni-Tools | `tools.homelab.lan` | Utility suite |
| Prometheus | `prometheus.homelab.lan` | Metrics |
| Grafana | `grafana.homelab.lan` | Dashboards |

### Docker

| App | URL | Description |
|-----|-----|-------------|
| Immich | `immich.pve.lan` | Photo/video backup |
| Vikunja | `vikunja.burndev.lan` | Task management |
| Linkwarden | `linkwarden.burndev.lan` | Bookmark manager |
| KaraKeep | `karakeep.burndev.lan` | Read-later / bookmarking |
| LLDAP | `lldap.burndev.lan` | Lightweight LDAP |
| Actual Budget | `actual.burndev.lan` | Budgeting |
| Scanopy | `scanopy.burndev.lan` | Document scanning |
| Rackpeek | `rackpeek.burndev.lan` | Rack monitoring |
| DownTify | `downtify.burndev.lan` | Download tracker |
| LLMeter | `llmeter.burndev.lan` | LLM monitoring |
| Ollama | — | LLM serving (API only) |
| FileBrowser Quantum | `files.burndev.lan` | Web file manager |

Homepage auto-discovers Docker services from the `docker/*/compose.yaml` stacks through a read-only Docker socket proxy at `192.168.1.50:2375`.

## Stack

- **Platform**: Bare-metal single-node
- **Config management**: Ansible
- **Kubernetes**: k3s v1.36.1 (Traefik & ServiceLB disabled, embedded etcd)
- **Ingress**: Caddy in `network_mode: host` (sole edge proxy, owns ports 80/443) — K8s services exposed via NodePort (30080-30088)

## Prerequisites

- Ansible >= 2.14 with `community.general` collection
- kubectl
- SSH key at `~/.ssh/id_ed25519_npburney_burndev`
- Synology NAS with NFS exported at `/volume1/homelab/k8s/`

## Deployment Order

### 1. Bootstrap Kubernetes — Ansible

```bash
cd ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i inventory/hosts.ini site.yml
```

This runs the full bootstrap:
- `common` role: disables swap, loads kernel modules, sets sysctl, installs dependencies, configures UFW firewall
- `control_plane` role: installs k3s server with `--cluster-init` (embedded etcd) for future scale-out

### 2. Install Cert-Manager (for TLS)

```bash
bash kubernetes/cert-manager/install-cert-manager.sh
kubectl apply -f kubernetes/cert-manager/ca-issuer.yml
```

TLS is handled by Caddy at the edge (ports 80/443) using pre-provisioned certificates.
K8s cert-manager provides the `homelab-ca-issuer` ClusterIssuer for internal K8s certificate needs.

To trust certs in your browser, export the CA certificate:

```bash
kubectl get secret homelab-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > homelab-ca.crt
```

Import `homelab-ca.crt` into your OS/browser trust store.

### 3. Install Platform Components

```bash
bash scripts/install-nfs-provisioner.sh
bash scripts/install-kube-prometheus-stack.sh
bash scripts/install-blackbox-exporter.sh
```

### 4. Deploy K8s Apps — kubectl

```bash
# Dry-run full deployment (safe validation)
bash scripts/deploy-k8s.sh --dry-run

# Apply manifests
bash scripts/deploy-k8s.sh
```

Notes:
- `scripts/deploy-k8s.sh` applies `kubernetes/policies/` recursively.
- Example secret manifests (`*.example.yml`) are intentionally excluded from deploy.
- `kubernetes/monitoring/blackbox-values.yml`, `kube-prometheus-stack-values.yml`, and `prometheus-additional-scrape.yml` are Helm values/snippets, not standalone Kubernetes resources.

### 5. Deploy Docker Stacks

```bash
make deploy-docker
```

## Operations

### Quick Reference (Makefile)

```bash
make validate          # Pre-flight checks (syntax, secrets, mounts, dry-runs)
make bootstrap         # Ansible + platform installs
make deploy-k8s        # Apply all K8s manifests
make deploy-docker     # Start all Docker stacks
make backup            # Full backup (repo + app data)
make restore-dry-run   # Preview restore from NAS (no changes)
make restore           # Restore app data from NAS (requires --force)
```

### Validate Before Deploying

```bash
make validate
```

Checks shell syntax, YAML lint, unpinned images, missing .env files, NAS mount,
Docker compose config, kubectl dry-runs, and secrets in tracked files.

### Restore from Backup

The NAS backup at `/mnt/syn/backups/homelab` contains a full copy of this repo.
To restore on a new machine:

```bash
# 1. Preview repo restore from NAS (no changes)
bash scripts/pull-from-nas-backup.sh --dry-run

# 2. Pull backup into local repo
bash scripts/pull-from-nas-backup.sh --apply

# 3. Preview app-data restore
bash scripts/restore-app-data.sh --dry-run

# 4. Restore app data (Docker volumes, databases, Caddy certs)
bash scripts/restore-app-data.sh --force

# 5. Re-run Ansible (idempotent, checks cluster health)
cd ~/dev/homelab/ansible
ansible-playbook site.yml

# 6. Re-apply all K8s manifests (idempotent)
bash ~/dev/homelab/scripts/deploy-k8s.sh
```

Full recovery procedures are in [docs/runbook.md](docs/runbook.md).

## K8s Storage Classes

| Name | Provisioner | Backend |
|------|------------|---------|
| `local-path` | rancher.io/local-path | Node-local storage (default) |
| `nfs` | nfs-subdir-external-provisioner | Synology NAS |
