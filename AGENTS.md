# AGENTS.md

## Runtime target guard

- This is the `local` branch. It describes the desired local deployment on `burndev`; it does not prove that the local deployment is currently installed or running.
- Git branch selection does not select a Kubernetes cluster.
- The `default` kubectl context points to burndev (the single-node k3s cluster). Always verify the current context before destructive operations:
  ```bash
  kubectl config current-context
  ```
- For scripts and automation, use `--context default` explicitly to avoid ambiguity.
- If `kubectl cluster-info` fails or the context points elsewhere, stop and ask.
- Treat Ansible inventory and this file as desired configuration. Verify live state separately.

## Secrets handling

- Never commit `*secret.yml`, `.env`, `.pem`, `.key`, `.crt`, or `.log` files (all in `.gitignore`).
- **K8s secrets**: Managed via `scripts/create-secrets.sh` which reads from `secrets/homelab.env` (git-ignored). Copy `secrets/homelab.env.example` to `secrets/homelab.env`, fill in values, then create-secrets.sh generates `tools/code-server-secret` and `default/homepage-secret`.
- **Docker `.env` files**: copy `.env.example` to `.env` per stack; never commit `.env`.

## Deployment is strictly ordered

One-command full deploy:
```
make up
```

Or run steps individually:

1. `make bootstrap` (Ansible: installs k3s on burndev)
2. `make platform` (cert-manager, NFS provisioner, Prometheus stack, Blackbox exporter)
3. `scripts/create-secrets.sh` (creates code-server and homepage K8s secrets from `secrets/homelab.env`)
4. `scripts/sync-homepage.sh` (syncs homepage images to NAS)
5. `scripts/deploy-k8s.sh` (namespaces, policies, apps, monitoring, rollout checks)
6. `scripts/check-k8s.sh` (rollout verification + failing pods + URL summary)

Must run in order. Each step depends on the previous.

## Architecture gotchas

- **burndev** (192.168.1.50) is the sole k3s node — single-node cluster. All K8s workloads run here.
- **Docker compose stacks** also run on burndev, not on the k3s cluster. Homepage auto-discovers them via a read-only Docker socket proxy at `192.168.1.50:2375`.
- **k3s runs without Traefik or ServiceLB** — both disabled at install. Caddy is the sole edge proxy (`network_mode: host`, owns ports 80/443).
- **K8s services are exposed via NodePort** (30080-30088). Caddy reverse-proxies to `localhost:<nodePort>`. There is no Ingress controller.
- **NetworkPolicy is default-deny** in the `tools` namespace. Any new app in tools needs an allow-ingress policy (IP-block based, 192.168.1.0/24) to receive traffic.
- **TLS is handled by Caddy** at the edge using pre-provisioned certificates. cert-manager is installed for internal K8s cert needs. Browsers need `homelab-ca.crt` imported for the self-signed CA.

## Prerequisites that agents may overlook

- Do not use SSH agent forwarding for agent access. Remote agent access must use a dedicated, least-privileged key configured specifically for Pi.
- The NAS (`/mnt/syn`) must be mounted for the backup script and NFS storage class to work.
- The backup script at `scripts/backup.sh` aborts if `/mnt/syn` is not mounted.

## Ansible specifics

- Run `ansible-galaxy collection install -r requirements.yml` before first playbook run.
- Inventory: `ansible/inventory/hosts.ini`. Group `k8s_cluster` includes `control_plane` (burndev only).
- The `common` role runs on burndev first, then the `control_plane` role installs k3s.
- Node labels (e.g. `gpu=nvidia` on burndev) are applied in `ansible/inventory/group_vars/all.yml`.

## Backup & restore

- `scripts/backup.sh` mirrors the entire repo to `/mnt/syn/backups/homelab/` via rsync.
- `scripts/sync-homepage.sh` syncs homepage images to `/mnt/syn/k8s/homepage/images/` (Homepage config files are embedded as ConfigMaps in `homepage.yml`; only images live on NFS).
- Full backup/restore and recovery procedures are in `docs/runbook.md`.

## Relevant config files

- `.openclaude/settings.local.json` — permissions for bash commands the agent is allowed to run.
- Full architecture and server inventory in `README.md`.
