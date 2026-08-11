# AGENTS.md

Operating context for coding agents working in this repository. This file is a
pointer file, not an architecture copy. For depth, read the linked docs — they
are the current source of truth. If a doc here contradicts `docs/proxmox-cluster.md`,
`docs/backup-layout.md`, or live state, trust live state and fix the doc.

## Repo facts

- Branch: `main`. Remote: `git@github.com:BurneyProMod/homelab.git`.
- Canonical copy: Synology NAS, mounted on `pve-core` at
  `/mnt/synology/homelab/repo`. Edit it there. Off-site copy is the GitHub
  remote; `scripts/backup.sh` pushes it (warn-don't-fail, see below).
- Repo layout: `docker/` (compose stacks), `kubernetes/` (k3s manifests),
  `config/caddy/` + `config/step-ca/`, `scripts/`, `docs/`, `secrets/` (gitignored),
  `Makefile`.
- The repo is a passive source-of-truth mirror: nothing watches it, nothing
  auto-applies. Deploy is manual (`make deploy-k8s`, `make deploy-docker`).
  See `docs/gitops-plan.md`.

## Architecture (current, 2026-08)

- Proxmox cluster: `pve-core` (.30), `pve-exu` (.31), `pve-gpu` (.32). Guest
  inventory: `docs/proxmox-cluster.md`.
- Docker stacks run in LXCs across the PVE nodes — NOT on burndev. Host map:
  `docs/service-inventory.md`.
- k3s: 3 VMs, all control-plane, `k3s-core` .70 / `k3s-exu` .71 / `k3s-gpu` .72.
  Services exposed via NodePort (30080+), no Ingress, no Traefik/ServiceLB.
- Edge: HA Caddy pair (LXC 103 core / LXC 101 gpu), keepalived VIP 192.168.1.10,
  `*.burney.network`, TLS via Let's Encrypt + Cloudflare DNS-01
  (`config/caddy/Caddyfile`).
- SSO: lldap (LXC 110) -> Authentik (LXC 118, `auth.burney.network`) -> OIDC +
  forward-auth on Caddy. Groups: `admins`, `family`.
- `burndev` (.50) runs ONLY the `burntv` NFS media share and the local LLM.
  Do not route repo, Docker, Kubernetes, or secret work through it.

## Paths

Single source: `scripts/lib-paths.sh` — source it, never hardcode NAS paths.
- `NAS_ROOT` (default `/mnt/synology/homelab`; burndev mounts the same share at `/mnt/syn`)
- `REPO_MIRROR` (`$NAS_ROOT/repo`)
- `BACKUP_ROOT` (`$NAS_ROOT/backups/homelab` — app-data backup root)

## Scripts

- `scripts/validate.sh` — pre-flight gate. Must pass before deploy. Known-fail
  image-pin checks are tracked in the audit; `make up` dies at step 1 if it fails.
- `scripts/deploy-k8s.sh` — applies namespaces/policies/apps + rollout checks.
  `--dry-run` first. Requires kubectl pointed at the homelab k3s cluster
  (`scripts/lib-context.sh` guard). kubectl is NOT on pve-core; run from a k3s
  node (`ssh npburney@<node>` + `sudo kubectl`) or a host with a kubeconfig.
- `scripts/create-secrets.sh` — creates k8s Secrets from `secrets/homelab.env`
  (gitignored; copy `secrets/homelab.env.example` first).
- `scripts/backup-app-data.sh` — app-data backup, runs on ops LXC 115
  (cron daily 04:00). `--dry-run` is local-only. Exits non-zero on any failure.
- `scripts/restore-app-data.sh` — MANUAL ONLY, never scheduled. Dry-run by
  default; `--force` + typed `yes` required.
- `scripts/backup.sh` — off-site repo backup: `git push origin main`.
  Warn-don't-fail: a push error logs WARN and exits 0, never blocking
  `make backup`'s app-data step. The canonical repo stays on the NAS either way.
- `scripts/check-k8s.sh` — rollout verification + failing pods + URL summary.
- Makefile targets that EXIST: `validate`, `up`, `deploy-k8s`, `deploy-docker`,
  `backup`, `backup-app`, `restore-dry-run`, `restore`. There is no
  `bootstrap`/`platform` target anymore.

## Secrets handling

- Never commit `*secret.yml`, `.env`, `.pem`, `.key`, `.crt`, or `.log` files.
- Real values: `secrets/homelab.env` (gitignored, chmod 600) and host-local
  `.env` files. k8s Secrets are created via `scripts/create-secrets.sh`.
- Compose files reference `${VAR}`; manifests use `secretKeyRef` or example
  templates. Rotate any credential that appears in the repo.

## Deprecated (do not resurrect)

- Ansible bootstrap, `ansible/` inventory, cert-manager + self-signed CA
  (`homelab-ca.crt`), Homepage, Docker socket proxy at .50:2375,
  `scripts/sync-homepage.sh` — archived under `docs/archive/`.
- `docs/runbook.md` and `docs/k3s-single-node-setup.md` are marked
  `Status: historical` at the top. Current recovery path:
  `docs/proxmox-cluster.md` + `docs/backup-layout.md`.

## Good-first-checks when something looks wrong

1. `git status` / `git log --oneline -5` — confirm which branch and how fresh.
2. `make validate` — run the gate before changing anything.
3. `bash -n` + `shellcheck -S warning` on any script you touch.
4. Confirm live state on the host before trusting a doc (docs drift).
