# GitOps / IaC Plan — Commit-to-Live Configuration Deployment

Status: DRAFT (2026-08-11)
Owner: npburney
Related: best-practices.md, runbook.md, service-inventory.md, docker-services.md, security.md

## 1. Goal

The homelab repository becomes the **single source of truth** for configuration.
An edit committed to the repo changes the live environment without manual
deploy commands. Rollback is a revert.

Definition of done ("one place to edit configs"):

- Edit a config file or manifest in the repo, commit on pve-core, live
  environment changes within ~1 minute, no manual apply step (Phase 2).
- Pushing from any machine to GitHub also deploys (Phase 3).
- Rollback = `git revert` of the offending commit.
- Adding a service = add manifest/config to the repo + one line in the host
  map. No other manual wiring.

## 2. Current state (verified 2026-08-11)

The repo is a **passive source-of-truth mirror**. It does not drive anything.

| Item | State |
|---|---|
| Trigger from commit to apply | **None** — no CI, no git hooks, no watchers, no Flux/ArgoCD, no webhooks |
| Deploy mechanism | Manual: `make deploy-k8s` → `scripts/deploy-k8s.sh` (kubectl apply); `make deploy-docker` → per-dir `docker compose up -d`; `scripts/sync-homepage.sh` → rsync to NAS |
| Runner capability | pve-core has **no kubectl, no kubeconfig**; cluster access today is `ssh k3s-exu` + `sudo kubectl`. Docker stacks run inside LXCs on pve-core/pve-exu/pve-gpu/caddy pair |
| Platform types | k3s manifests (`kubernetes/`), Docker Compose on LXCs (`docker/`), Ansible (`ansible/`) |
| Storage classes live | `local-path` only (cluster rebuilt ~8d ago) |
| GitOps tooling | None present |

## 3. Drift inventory — repo vs live (reconcile BEFORE automation)

### 3.1 Kubernetes (`kubernetes/apps/`)

| Manifest | Live status | Action |
|---|---|---|
| `homarr.yml` | **Live, but untracked in repo** | Commit |
| `changedetection.yml`, `homebox.yml`, `manyfold.yml`, `code-server.yml`, `kanboard.yml`, `omni-tools.yml`, `trilium.yml` | Live, tracked | Keep; verify content matches live after reconcile |
| `homepage.yml`, `homepage-rbac.yml` | **Not live** (homepage retired; replaced by Homarr) | Archived to docs/archive/ (2026-08-11) |
| `termix.yml` | **Not live** (no deployment, no PVC) | Archived to docs/archive/ (2026-08-11) |
| `immich.yml` | Deleted in working tree; Immich moved to Docker (pve-exu CT 111) | Keep deleted |
| `kubernetes/monitoring/*`, `kubernetes/namespaces/monitoring.yml`, `kubernetes/policies/monitoring/*` | **Staged, not applied** — no monitoring namespace on live cluster | Archived to docs/archive/ (2026-08-11) |
| `kubernetes/cert-manager/*` | **Staged, not applied** — no cert-manager namespace live | Archived to docs/archive/ (2026-08-11) |

### 3.2 Docker (`docker/`)

| Item | Status | Action |
|---|---|---|
| Compose stacks | Run on LXCs: pve-core (110, 114, 115), pve-exu (111, 112, 113, 119, 123, 124), pve-gpu (100, 201-205), caddy (103/101) | Host mapping exists only in docs (`service-inventory.md`, `docker-services.md`) — make machine-readable |
| `cannery/`, `linkwarden/` | Decommissioned, dirs remain | Deleted (2026-08-11) |
| `ollama/` | Contains 7.8 GB LLM-model copy + ~80 MB Python venv (ignored, but bloat on the Synology share) | Deleted (2026-08-11); compose.yaml now tracked |
| `.env` files | Present, gitignored, not committed | Keep pattern |

### 3.3 Ansible

`ansible/inventory/hosts.ini` still describes the **legacy burndev single-node
k3s** (`control_plane = burndev`). The current cluster is 3-node on PVE VMs.
Archived to docs/archive/ansible (2026-08-11). Decision was to archive, not rewrite for current infra, or drop the Ansible
layer entirely (most bootstrapping now happens via scripts + manifests).

### 3.4 Homepage config

`config/homepage/config/*` targets the retired Homepage service. Homarr (the
live dashboard) is **database-driven** (`homarr-data` PVC, `homarr-config`
ConfigMap, managed via UI/API/import-export) — it does not read files.
Action (done 2026-08-11): retired — `config/homepage/` deleted; treat Homarr config as backup/restore data,
not repo-driven files.

## 4. Target architecture

```
Synology share repo (pve-core mount)  ──canonical──▶  GitHub (BurneyProMod/homelab)
        │                                                    │
        │ git hook / watcher                                 │ GitHub Actions (optional)
        ▼                                                    ▼
   scripts/deploy.sh  ◀──────────────────────────────  webhook receiver (pve-core)
        │  reads config/hosts.yaml (service → host, method, dir)
        ├──▶ k3s cluster      : kubectl apply -f kubernetes/  (kubeconfig on pve-core)
        ├──▶ Docker LXC hosts : ssh <host> docker compose up -d -f <dir>/compose.yaml
        └──▶ file configs     : rsync config/<name>/ → target, then reload (caddy, step-ca)
```

Components:

1. **Source**: repo on the Synology share (mounted on pve-core) is the
   canonical working copy. GitHub is the remote mirror — enables off-box
   editing and the optional webhook trigger. Branch strategy TBD (Section 7).
2. **Deploy runner**: pve-core (the hub — has the repo mount, SSH to every
   host, Synology access). Needs two additions:
   - `kubectl` binary + kubeconfig (extract `k3s-exu:/etc/rancher/k3s/k3s.yaml`,
     rewrite `server:` to `https://192.168.1.71:6443`; keep perms 0600, root).
   - SSH keys to the Docker LXCs (verify existing keys cover all target hosts).
3. **Host map**: new `config/hosts.yaml` — machine-readable
   `service → {host, dir, method: kubectl|docker|rsync}`. `deploy.sh`
   consumes it; the docs stay as the human reference.
4. **Single entrypoint**: `scripts/deploy.sh <scope>` where scope is
   `k8s` | `docker/<stack>` | `config/<name>` | `all`. Every run:
   validate (`scripts/validate.sh`) → dry-run → backup if destructive →
   apply → verify (rollout status / healthcheck). Log to `~/deploy.log`.
5. **Secrets**: unchanged policy — gitignored `.env` on hosts, k8s Secrets
   created out-of-band, `{{VAR}}` indirection in committed files, committed
   `.env.example` placeholders. No secrets in the repo (verified clean by
   2026-08-11 deep scan).

## 5. Phases

### P0 — Reconcile drift (make repo = live)
- Commit `homarr.yml`; remove/archive `homepage.yml`, `homepage-rbac.yml`,
  `termix.yml`; keep `immich.yml` deleted.
- Decide + execute on: monitoring manifests, cert-manager manifests, Ansible
  inventory, decommissioned docker dirs, `docker/ollama/` venv, retiring
  `config/homepage/`.
- Settle branch strategy; land a clean commit on the deploy branch.
- **Exit criteria**: `git status` clean; repo describes live state.

### P1 — Single-command deploy (no triggers yet)
- Install kubectl + kubeconfig on pve-core; verify direct cluster access.
- Write `config/hosts.yaml`; write `scripts/deploy.sh`; rewire Makefile.
- Manual end-to-end verification of each scope (`k8s`, `docker/<stack>`,
  `config/<name>`) with dry-run + apply + verify.
- **Exit criteria**: `make deploy-k8s` and `make deploy-docker` work from
  pve-core with correct host targeting and live verification.

### P2 — Local trigger (commit on pve-core → live)
- Git `post-commit`/`post-merge` hook in the repo + systemd path unit
  watching the repo (fallback for external pulls).
- Hook calls `deploy.sh --auto <changed-scope>` (validate, non-interactive,
  log to `~/deploy.log`).
- **Exit criteria**: edit file → commit on pve-core → live changes, no manual
  command.

### P3 — Remote trigger (optional; push from anywhere → live)
- GitHub Actions workflow on push to the deploy branch → webhook to a
  Cloudflare Tunnel on pve-core → `deploy.sh`.
- Requires tunnel endpoint, receiver service, and a deploy token (GitHub
  secret; never in the repo).

### P4 — Optional: Flux/ArgoCD for k8s
- Cluster-native reconciliation for `kubernetes/` only. Runner still handles
  Docker + file configs. Only pursue if P2/P3 prove insufficient.

## 6. Safety and guardrails

- Dry-run by default; apply requires explicit `--apply`/confirmation.
- `scripts/validate.sh` gates every apply.
- Backups before destructive ops (`scripts/backup.sh`,
  `scripts/backup-app-data.sh` already exist).
- Scoped deploys only — no full-environment blast radius.
- Post-apply verification (rollout status, healthcheck) required.
- Every deploy logged with timestamp, scope, actor, result.
- Secrets never enter the repo; leak → rotate (existing policy).

## 7. Open decisions (need input)

1. **Branch strategy**: deploy from `main`? The `local` branch is 15 commits
   ahead of `main`, 18 ahead of `dev`. Merge into `main`, or rebase `local`
   onto `main`?
2. **Monitoring + cert-manager**: deploy the staged manifests to the current
   cluster, or archive them?
3. **Ansible**: rewrite inventory for current infra, or drop the layer?
4. **Decommissioned docker dirs** (`cannery`, `linkwarden`): delete or archive?
5. **`config/homepage/`**: retire entirely? Homarr config handled as data
   (backup/restore), not files?
6. **Trigger scope**: P2 (local only) or P2 + P3 (GitHub webhook)?
7. **kubeconfig**: root-only on pve-core at `/etc/rancher/k3s/k3s.yaml`?

## 8. Acceptance criteria

- P2 done: commit on pve-core → live change in ~1 minute, no manual steps.
- P3 done (if chosen): push from any machine → live change.
- Rollback = revert commit; backups taken before every destructive apply.
- New service = repo manifest/config + one `config/hosts.yaml` entry.
- `git status` clean on the deploy branch after every cycle.
