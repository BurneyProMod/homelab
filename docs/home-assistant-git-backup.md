# Home Assistant — Git Backup Configuration

Home Assistant configuration is backed up to a private GitHub repo at `github.com:BurneyProMod/homeassistant`.

## How It Works

A `backup.sh` script inside the HA environment auto-commits and pushes config changes. It runs via a cron job or HA automation (2am daily).

## Deploy Key

- Key file: `/config/.ssh/ha-git`
- SSH config uses `IdentitiesOnly=yes` and `StrictHostKeyChecking=accept-new`
- The deploy key must be added as a Deploy Key in the GitHub repo settings (Settings → Deploy Keys, with write access)

### Generating a Deploy Key

```bash
mkdir -p /config/.ssh
chmod 700 /config/.ssh
ssh-keygen -t ed25519 -C "ha-github-deploy" -f /config/.ssh/ha-github-deploy-key -N ""
```

### Deploy key gotchas

- A deploy key can only be used on **one** repository. If you see "Key is already in use", delete it from the old repo or generate a new key.
- Deploy keys survive repo deletion (they're tied to the key, not the repo).
- For Home Assistant: store the key inside `/config/.ssh/` so it persists across add-on restarts (the `/config` directory is mounted, not ephemeral).

## One-Time Setup Script (ha-git-init.sh)

Save as `/config/ha-git-init.sh` and run once to initialize git, SSH, and the cron job:

```bash
#!/bin/sh
apk add git openssh
mkdir -p ~/.ssh
cp /config/.ssh/ha-github-deploy-key ~/.ssh/
chmod 600 ~/.ssh/ha-github-deploy-key
cat > ~/.ssh/config << 'SSHEOF'
Host github.com
   HostName github.com
   User git
   IdentityFile ~/.ssh/ha-github-deploy-key
   IdentitiesOnly yes
   StrictHostKeyChecking accept-new
SSHEOF
chmod 600 ~/.ssh/config
cat > /etc/periodic/daily/ha-git-backup << 'CRONEOF'
#!/bin/sh
cd /config
git add -u
git commit -m "auto-backup $(date -Iseconds)" 2>&1 || true
git push origin main 2>&1 || true
CRONEOF
chmod +x /etc/periodic/daily/ha-git-backup
crond
```

Run once:
```bash
chmod +x /config/ha-git-init.sh
sh /config/ha-git-init.sh
```

## backup.sh (Fixed Version)

Key security fixes applied:

```bash
#!/bin/bash
set -eu

config_directory="/config"
ssh_directory="/config/.ssh"
deploy_key="${ssh_directory}/ha-git"
known_hosts="${ssh_directory}/known_hosts"

if [ ! -f "$deploy_key" ]; then
    echo "Deploy key not found: $deploy_key" >&2
    exit 1
fi

chmod 700 "$ssh_directory"
chmod 600 "$deploy_key"

export GIT_SSH_COMMAND="ssh -i $deploy_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$known_hosts"

cd "$config_directory"

git config user.name "Home Assistant"
git config user.email "home-assistant@localhost"

# CRITICAL: Use 'git add -u' NOT 'git add -A'
# -u only stages modifications/deletions to already-tracked files
# -A would stage everything, risking accidental exposure of new files
git add -u

if git diff --cached --quiet; then
    echo "No configuration changes to back up."
    exit 0
fi

git commit -m "auto-backup $(date '+%Y-%m-%dT%H:%M:%S%z')"
git push origin master

echo "Home Assistant configuration pushed successfully."
```

## HA Automation for Daily Backup

### shell_command

Add to `configuration.yaml`:

```yaml
shell_command:
  backup: "sh /config/backup.sh"
```

### Automation

Add to `automations.yaml`:

```yaml
- id: "daily-backup"
  alias: Daily Backup
  description: "Backup Home Assistant configuration folder"
  trigger:
    - platform: time
      at: "02:00:00"
  condition: []
  action:
    - service: shell_command.backup
      data: {}
      response_variable: backup_response
    - if:
        - condition: template
          value_template: "{{ backup_response['returncode'] == 0 }}"
      then:
        - service: notify.notify
          data:
            title: Backup successful
            message: "{{ backup_response['stdout'] }}"
      else:
        - service: notify.notify
          data:
            title: Backup failed
            message: "{{ backup_response['stderr'] }}"
  mode: single
```

## .gitignore

Critical entries to prevent secret leakage:

```gitignore
# Secrets
secrets.yaml
.cloud/

# SSH keys
.ssh/

# Home Assistant runtime data
.storage/
.ha_mcp/
home-assistant_v2.db*
home-assistant.log*
*.db-shm
*.db-wal
backups/
tmp/

# Cache & transient files
.cache/
tts/
www/community/
zigbee.db*
.ha_run.lock
.HA_VERSION
.shopping_list.json
custom_components/

# Python
__pycache__/
*.pyc

# ESPHome (managed separately)
esphome/
```

## Tracked Files (Safe to Commit)

| File | Purpose |
|------|---------|
| `automations.yaml` | Automation definitions |
| `configuration.yaml` | Main HA configuration |
| `scenes.yaml` | Scene definitions |
| `scripts.yaml` | Script definitions |
| `ui-lovelace.yaml` | Dashboard layout |
| `backup.sh` | Auto-backup script |
| `blueprints/` | Automation/script blueprints |

## CRITICAL: Files That Must NEVER Be Public

| File | Content | Risk |
|------|---------|------|
| `.ssh/ha-github-deploy-key` | SSH private key | Repo push access |
| `.cloud/remote_private.pem` | TLS private key | Nabu Casa remote access |
| `.cloud/production_auth.json` | Cloud auth tokens | Nabu Casa account takeover |
| `.storage/auth` | User database (hashed pws, tokens) | Account compromise |
| `.storage/application_credentials` | OAuth app credentials | Google/Nest/API access |
| `.storage/http.auth` | API access tokens | HA API access |
| `.storage/auth.session` | Active session tokens | Session hijacking |
| `.storage/mobile_app` | Push tokens + device data | Push notification spam |
| `.storage/cloud` | Cloud connection tokens | Nabu Casa access |
| `.cache/nest/event_media/` | Nest camera snapshots | Privacy breach |
| `home-assistant_v2.db-*` | SQLite WAL files | Entity state history |
| `home-assistant.log*` | Log files | May contain IPs, entity names |

## Pre-Public Checklist

Before making the HA repo public:

1. **Revoke all deploy keys** on GitHub
2. **Rotate Nabu Casa remote certs** — the private key in `.cloud/remote_private.pem` is compromised if ever pushed
3. **Rotate Cloud auth** — delete `.cloud/production_auth.json` and re-authenticate
4. **Rotate all OAuth credentials** — Google, Nest, etc.
5. **Audit `configuration.yaml`** — remove/redact device names, notification targets, mobile device names
6. **Regenerate HA auth** — force all users to re-login
7. **Delete repo history entirely** (not just add to .gitignore):

### How to Completely Wipe Git History

```bash
# Option A: Delete and recreate repo (SAFEST)
# 1. Delete repo on GitHub (Settings → Delete this repository)
# 2. Locally:
cd /config
rm -rf .git
git init
git add .
git commit -m "Initial clean backup"
git remote add origin git@github.com:USER/REPO.git
git push -u origin main

# Option B: Orphan branch force-push (keeps repo URL, less safe)
git checkout --orphan clean
git add .
git commit -m "Clean public backup"
git push -u origin clean:main --force
```

**Why Option A is safer**: Once a secret is in git history, `.gitignore` won't protect it. GitHub may cache old commits accessible by direct hash for days/weeks even after force-push. Option A (delete + recreate) is the only guaranteed way.

## Security Checklist

- [x] `git add -u` not `git add -A` — prevents untracked files from being committed
- [x] `secrets.yaml` in `.gitignore` — API keys, passwords not exposed
- [x] `.storage/` in `.gitignore` — TLS certs, internal state not exposed
- [x] `.ssh/` in `.gitignore` — deploy keys not exposed
- [x] `.cloud/` in `.gitignore` — ACME account keys not exposed
- [x] Third-party HACS components in `www/community/` gitignored
- [x] Deploy key file matches the `backup.sh` reference (`ha-git`)
- [x] `backup.sh` has `set -eu` for early exit on errors

## History

- Repo URL: `git@github.com:BurneyProMod/homeassistant.git`
- Initial commit: Jul 16, 2026 — 12 files, 729 lines
- First commit author fix needed: `git config --global user.name/email` + `git commit --amend --reset-author`
