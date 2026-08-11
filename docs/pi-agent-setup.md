# Pi Coding Agent — Setup & Configuration

How Pi is configured for the homelab environment, including AGENTS.md policies, skills, and session management.

## Session Storage

Pi stores all chat sessions as JSONL files at:

```
~/.pi/agent/sessions/
```

Organization: sessions are grouped into subdirectories by working directory (CWD):

| Directory | CWD |
|-----------|-----|
| `--home-npburney--/` | `~` (home directory) |
| `--home-npburney-dev--/` | `~/dev` |
| `--home-npburney-dev-homelab--/` | `~/dev/homelab` |
| `--home-npburney-dev-homelab-docker-caddy--/` | `~/dev/homelab/docker/caddy` |
| `--home-npburney-dev-statclock--/` | `~/dev/statclock` |

### Session File Format

Each file is a JSONL (one JSON object per line) with these types:

| type | Description |
|------|-------------|
| `session` | Session metadata (id, timestamp, cwd) |
| `model_change` | Model/provider selection |
| `thinking_level_change` | Thinking level setting |
| `message` | User/assistant/tool messages |

### Session Commands

| Command | Action |
|---------|--------|
| `/session` | Show current session (file, ID, tokens, cost) |
| `/resume` | Pick from previous sessions |
| `/new` | Start new session |
| `/name <name>` | Set session display name |
| `/fork` | Create new session from a past message |
| `/clone` | Duplicate current branch to new session |
| `/export [file]` | Export to HTML or JSONL |
| `/import <file>` | Resume from exported JSONL |
| `/tree` | Jump to any point in session history |

## AGENTS.md Configuration

Location: `~/.pi/agent/AGENTS.md`

Key policies:

### Vikunja
- Vikunja is the source of truth for projects and chores
- Read/analyze freely; no mutations without explicit request

### Homelab Change Policy
- All state-changing homelab actions require explicit confirmation
- Must identify exact host, service, environment before acting
- Must show exact command, expected effect, and rollback plan

### Homelab Inventory
- Load `homelab-inventory` skill before any homelab work
- Treat inventory as reference; verify live state read-only

### Diagnosis vs Implementation
- Read-only investigation only for inspection/diagnosis requests
- Separate evidence, inference, recommendation, and action

## Skills Directory

Skills are loaded from two locations:

1. `~/.pi/agent/skills/` — Private skills (homelab-inventory)
2. `~/dev/.pi/skills/pi-skills/` — Shared skills (brave-search, browser-tools, gccli, gdcli, gmcli, transcribe, vscode, youtube-transcript)

### Available Skills

| Skill | Purpose |
|-------|---------|
| `homelab-inventory` | Maps hosts, services, storage, backups, dependencies |
| `brave-search` | Web search and content extraction |
| `browser-tools` | Interactive browser automation via CDP |
| `gccli` | Google Calendar CLI |
| `gdcli` | Google Drive CLI |
| `gmcli` | Gmail CLI |
| `transcribe` | Local speech-to-text (Apple Silicon) |
| `vscode` | VS Code diff viewing |
| `youtube-transcript` | YouTube transcript fetching |

## MCP Servers

Connected MCP servers:

| Server | Tools | Purpose |
|--------|-------|---------|
| `vikunja` | 53 | Task/project management |
| `ha-mcp` | 27 | Home Assistant API access |

### Vikunja MCP Notes
- CSV import supported for bulk task creation
- See `vikunja-import.csv` in the homelab repo

### Home Assistant MCP Notes
- Cannot read raw filesystem files (no YAML file access)
- Can read entity state, control devices, get automation config by entity_id
- For filesystem access, SSH is needed (see [ssh-key-management.md](ssh-key-management.md))

## Models

Default model: DeepSeek v4 Pro (high thinking)

Fast forks (mechanical tasks) use lower effort. The AGENTS.md routes:
- Fast forks for narrow, mechanical, read-only tasks
- Balanced/deep for architecture, security, implementation
- Parent agent owns clarification, coordination, final review
