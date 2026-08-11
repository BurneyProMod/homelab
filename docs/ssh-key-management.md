# SSH Key Management for Homelab

Patterns for managing SSH access across homelab servers, including Pi agent access and deploy keys for automated git operations.

## Current SSH Aliases

| Alias | Host | User | Key | Status |
|-------|------|------|-----|--------|
| `homeassistant` | `homeassistant.lan` | `root` | `~/.ssh/homeassistant_ed25519` | ✅ Working |
| `kws-rpi-1` | (Klipper printer) | — | — | Configured |
| `synology` | (NAS) | — | — | Server file exists, SSH not yet configured |

## Server Access Keys

Each server should have its own SSH key pair. Keys are stored in `~/.ssh/` with a naming convention:

```
~/.ssh/
├── id_ed25519_npburney_burndev              # default personal key
├── homeassistant_ed25519   # HA Pi
├── pi_agent_ed25519        # dedicated Pi agent key (least-privilege)
├── synology_ed25519        # NAS
└── ...
```

### Adding a new server

**Part 1: SSH Config (`~/.ssh/config`)**

Generate a key:
```bash
ssh-keygen -t ed25519 -f ~/.ssh/<keyfile>_ed25519 -C "server-name" -N ""
```

Copy to server:
```bash
ssh-copy-id -i ~/.ssh/<keyfile>_ed25519 user@host
```

Add an SSH config entry:
```
Host <alias>
    HostName <hostname-or-ip>
    User <username>
    IdentityFile ~/.ssh/<keyfile>_ed25519
    IdentitiesOnly yes
```

Test:
```bash
ssh <alias> hostname
```

**Part 2: Homelab Inventory**

Create a server file at `~/.pi/agent/skills/homelab-inventory/references/servers/<alias>.md` following the format of existing files (see `burndev.md` or `synology.md`).

Then update `references/INDEX.md` with a lookup entry mapping user-facing terminology to the host alias.

### Key hardening

In SSH config entries:
- `IdentitiesOnly yes` — prevents ssh from trying all keys in the agent
- `StrictHostKeyChecking accept-new` — for automated connections

## Pi Agent Access

Per AGENTS.md policy, Pi should use a dedicated, least-privileged key.

### Current Pi SSH aliases

```
Host homeassistant
    HostName homeassistant.lan
    User root
    IdentityFile ~/.ssh/homeassistant_ed25519
```

The AGENTS.md recommends a separate key (`~/.ssh/pi_agent_ed25519`) specifically for Pi, distinct from personal keys. This provides:
- Audit trail (which connections came from Pi vs manual)
- Ability to revoke Pi access without affecting personal access
- Least privilege principle

## Deploy Keys (GitHub)

Deploy keys provide read/write access to a single GitHub repository without tying to a user account. Used for automated git push (e.g., HA config backups).

### Creating a deploy key

```bash
ssh-keygen -t ed25519 -C "description" -f /path/to/key -N ""
```

Add the public key to the repo:
GitHub → Repository → Settings → Deploy Keys → Add deploy key
Check "Allow write access" if the key needs to push.

### Deploy key gotchas

- A deploy key can only be used on **one** repository. If "Key is already in use", delete it from the old repo or generate a new key.
- Deploy keys survive repo deletion (they're tied to the key, not the repo).
- For Home Assistant: store the key inside `/config/.ssh/` so it persists across add-on restarts (the `/config` directory is mounted, not ephemeral).

## Home Assistant SSH Access

Home Assistant runs on a dedicated Pi (`homeassistant.lan`). SSH access goes through the **SSH add-on** (`core_ssh`), which provides an Alpine container with `/config` mounted.

```bash
ssh homeassistant
# Lands in /root (add-on container)
# /config is the HA config directory
```

The add-on's `authorized_keys` must include your public key. Configure in HA UI: **Settings → Add-ons → Terminal & SSH → Configuration → Authorized Keys**.

The add-on container is ephemeral — installed packages (like `git`, `crond`) must be re-installed after add-on restarts unless persisted via `init_commands`.

### Why SSH is needed (vs MCP tools)

The Home Assistant MCP tools operate through the REST/WebSocket API — they **cannot** read raw YAML files from the filesystem. For tasks like reading `automations.yaml` or `configuration.yaml`, SSH access is required.

| Tool | Server | What it can do |
|------|--------|---------------|
| `ha_config_get_automation` | ha-mcp | Get single automation config by entity_id |
| `ha_search` | ha-mcp | Search for automation entities |
| `ha_get_overview` | ha-mcp | System overview with entity listing |
| `GetLiveContext` | home-assistant | Real-time state of entities |
| `HassTurnOn`/`HassTurnOff` | home-assistant | Control devices |

### HA Filesystem Layout

Key paths inside the HA environment:

| Path | Contents |
|------|----------|
| `/config/automations.yaml` | Automation definitions |
| `/config/configuration.yaml` | Main HA configuration |
| `/config/scenes.yaml` | Scene definitions |
| `/config/scripts.yaml` | Script definitions |
| `/config/secrets.yaml` | Secrets (gitignored, not in repo) |
| `/config/.ssh/` | Deploy keys for git backup |
| `/config/backup.sh` | Auto-backup script (git push) |
| `/config/www/` | Web assets (HACS, custom cards) |

## Synology NAS

The Synology (192.168.1.11) is the primary backup destination. SSH access is not yet configured (as of last audit). To set up:

1. Enable SSH on Synology DSM (Control Panel → Terminal & SNMP)
2. Add public key to `/var/services/homes/<user>/.ssh/authorized_keys`
3. Add SSH config entry

## Best Practices

1. **One key per purpose** — don't reuse personal keys for automation
2. **Deploy keys for git** — more secure than personal access tokens
3. **`IdentitiesOnly yes`** — prevents ssh agent from trying wrong keys
4. **Rotate keys** after any suspected compromise (e.g., key accidentally pushed to a public repo)
5. **Audit `~/.ssh/authorized_keys`** on each server periodically
6. **Never commit private keys** — verify `.gitignore` covers `.ssh/` and any key directories
