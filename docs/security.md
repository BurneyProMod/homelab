# Security & Secrets Management

Comprehensive security policies for the homelab — secrets management, network policies, TLS, git hygiene, and audit findings.

## Secrets Policy

**Never commit secrets to the repository.** All secrets are excluded via `.gitignore`.

### Secrets That Must Never Be Committed

| Category | Examples | Where They Live |
|---|---|---|
| SSH private keys | `id_ed25519_npburney_burndev`, deploy keys | `~/.ssh/` (not in repo) |
| TLS private keys | `*-key.pem`, `privkey.pem` | Docker volumes, not in repo |
| API keys / tokens | FACEIT_API_KEY, Cloudflare tokens | `.env` files (gitignored) |
| Database passwords | postgres, redis passwords | `.env` files or Docker secrets |
| WireGuard keys | private key, preshared key | `.env` files, never in compose.yaml |
| OAuth credentials | Google, Nest, GitHub tokens | `.storage/` (gitignored) |
| ACME account keys | Let's Encrypt account private keys | Docker volumes |
| HA auth database | `.storage/auth` | gitignored |
| Cloud auth tokens | Nabu Casa, cloud connections | `.cloud/` (gitignored) |

## Kubernetes Secrets

1. Copy the example file: `cp kubernetes/apps/immich-secret.example.yml kubernetes/apps/immich-secret.yml`
2. Edit with real values
3. Apply: `kubectl apply -f kubernetes/apps/immich-secret.yml`
4. The real secret file is gitignored (`*secret.yml`)

Available examples:
- `code-server-secret.example.yml` — `PASSWORD`, `SUDO_PASSWORD`
- `immich-secret.example.yml` — `DB_USERNAME`, `DB_PASSWORD`, `DB_DATABASE_NAME`

## Docker .env Files

1. Copy the example: `cp docker/vikunja/.env.example docker/vikunja/.env`
2. Edit with real values
3. `.env` is gitignored

## .gitignore Strategy

### Docker stacks

The homelab repo uses this pattern for Docker directories:

```gitignore
/docker/**
!/docker/**/
!/docker/**/compose.yaml
!/docker/**/.env.example
```

This ignores everything under `/docker/`, then selectively re-includes:
- Directory structure (`!/docker/**/`)
- Compose files (`compose.yaml`)
- Example env files (`.env.example`)

What's blocked: `.env` files, certs, ACME keys, data directories, and any other runtime artifacts under `/docker/`.

**However**: Compose files themselves must never contain secrets because they ARE included by this pattern. If a compose.yaml has hardcoded passwords or WireGuard keys, those secrets will be committed.

### Home Assistant config

See the [Home Assistant Git Backup](home-assistant-git-backup.md) guide for the HA-specific `.gitignore`.

### General rules

- Secrets go in `.env` files or environment variables, never in committed YAML/JSON/config files
- `.env.example` files should show the structure with placeholder values
- Actual `.env` files are gitignored
- Docker certs and data directories are gitignored via the `/docker/**` rule
- If in doubt, `git add -n <path>` to see what would be staged before committing

## NetworkPolicy (Default-Deny)

Both `tools` and `monitoring` namespaces default to denying all ingress:

```yaml
# kubernetes/policies/tools/default-deny.yml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: tools
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

Egress is intentionally **unrestricted** for DNS, metrics export, and API calls.

### Allow Rules

**tools namespace**:
- `allow-ingress.yml` — permits traffic from `ingress-nginx` namespace (allows web traffic to reach pods)
- `allow-monitoring.yml` — permits traffic from `monitoring` namespace (allows Prometheus scraping)

**monitoring namespace**:
- Only `default-deny.yml` — monitoring pods are not exposed via ingress in the tools namespace; Prometheus/Grafana are accessed through their own ingress resources.

Any new app in `tools` namespace must have an ingress allow rule or it will be unreachable.

## TLS

### Internal CA

cert-manager creates a self-signed CA (`homelab-ca`) using ECDSA P-256. All `*.homelab.lan` certs are issued by this CA:

```bash
kubectl apply -f kubernetes/cert-manager/ca-issuer.yml
```

Export CA cert for browser trust:
```bash
kubectl get secret homelab-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > homelab-ca.crt
```

### External (Caddy)

Caddy handles Let's Encrypt / ZeroSSL certificates for `*.burndev.lan`. Certificates are stored in `docker/caddy/data/` and `docker/caddy/certs/`.

## Docker Socket Proxy

Homepage discovers Docker services via a read-only socket proxy at `192.168.1.50:2375`:

```yaml
# docker/socket-proxy/compose.yaml
services:
  dockerproxy:
    image: ghcr.io/tecnativa/docker-socket-proxy:latest
    container_name: homepage-dockerproxy
    environment:
      CONTAINERS: 1   # Only allow container listing
      POST: 0         # Deny POST (mutations)
    ports:
      - "192.168.1.50:2375:2375"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped
```

Key security properties:
- Binds to `192.168.1.50` only (not `0.0.0.0`) — LAN-only access
- `CONTAINERS: 1` — only allows listing containers (no exec, no create)
- `POST: 0` — denies all write operations
- Socket mounted read-only (`:ro`)

## Codebase Audit Findings (Historical)

Issues found during the initial homelab codebase audit that have been or should be addressed:

### CRITICAL: WireGuard keys in compose.yaml

`docker/servarr/compose.yaml` had hardcoded WireGuard private key, preshared key, and VPN address inside the gluetun service config. Since compose files ARE tracked by git, these would have been committed.

**Fix**: Move all secrets to a `.env` file in the servarr directory (which is gitignored by the `/docker/**` pattern).

### CRITICAL: TLS certificates and private keys

`docker/caddy/certs/` and `docker/caddy/data/caddy/acme/` contain TLS private keys and ACME account keys. These are properly gitignored by `/docker/**` but must never be explicitly added to git.

### HIGH: Default passwords in compose files

Some compose files had hardcoded passwords like `POSTGRES_PASSWORD=postgres` or `POSTGRES_PASSWORD=changeme`. While these are defaults, they should be externalized to `.env` files.

### HIGH: Identity exposure in configuration

`configuration.yaml` (Home Assistant) and similar config files contain:
- Mobile device names (e.g., `mobile_app_pixel_8_pro`)
- Entity names that reveal room layout
- Integration names indicating what services are running

For a public-facing repo: review and sanitize these. Consider using generic names instead of personal device names.

### MEDIUM: Third-party code licensing

Custom JavaScript files in `www/` (like `threedy-card.js`) should be verified for license compatibility if the repo is public. HACS-managed components (in `www/community/`) are auto-gitignored.

## Git Hygiene for Public Repos

### Before making a repo public

1. **Audit commit history** — secrets in old commits are still accessible:
   ```bash
   git log --all --full-history -- '**/secrets.yaml' '**/*-key.pem' '**/.env'
   ```
2. **If secrets found**: nuke history entirely (delete remote, re-init local, force-push clean history)
3. **Rotate all credentials** that were ever in the repo
4. **Verify `.gitignore`** by doing a dry-run:
   ```bash
   git add -n .   # what would be staged?
   ```

### Nuking git history

The only reliable way to guarantee secrets are gone:

```bash
# 1. Delete the GitHub repo via web UI
# 2. Remove local git history
rm -rf .git
# 3. Fresh init
git init
git add .
git commit -m "Initial clean commit"
# 4. Create new remote and push
git remote add origin <url>
git push -u origin main --force
```

Force-pushing an orphan branch keeps the repo URL but GitHub may retain old commits as dangling objects (accessible by hash) for days/weeks. Deleting and recreating the repo is safer.

### Ongoing safety

- `git add -u` not `git add -A` in automated scripts — never auto-stage new untracked files
- Periodically run `git status` to catch untracked files
- Review diffs before pushing: `git diff --cached`
- Use separate repos for public and private configs

## Terraform Secrets (deprecated, Proxmox removed)

The `terraform/` directory has been removed (Proxmox VMs no longer used). If reintroduced, pass API tokens via environment variables: `TF_VAR_proxmox_api_token`.
