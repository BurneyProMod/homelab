# Vikunja Task Management

Vikunja is the source of truth for projects and chores.

## Access

- URL: `http://localhost:3456` (Docker, no public route — per AGENTS.md)
- The agent may read and analyze Vikunja freely but must not create, edit, move, complete, archive, or delete anything without explicit request.

## CSV Import Format

Vikunja accepts CSV imports with these columns:

```csv
title,description,project_title,priority,labels,due_date,done
```

| Column | Required | Description |
|--------|----------|-------------|
| `title` | Yes | Task title |
| `description` | No | Task description (Markdown supported, can include URLs) |
| `project_title` | No | Project name — tasks with the same project_title are grouped. Empty = Inbox |
| `priority` | No | 0=None, 1=Low, 2=Medium, 3=High, 4=Urgent, 5=DO NOT USE (see note) |
| `labels` | No | Comma-separated label names (auto-created if new) |
| `due_date` | No | Format: `YYYY-MM-DD` |
| `done` | No | `true` or `false` (default: false) |

> **Priority note**: The Vikunja API scales 0–4 (0=None, 4=Urgent). The CSV import may accept 1–5 mapping. Test with a small import first. If Vikunja rejects priority=0 in CSV, use 1–5 scale (1=Lowest, 5=Highest).

### Example CSV

```csv
title,description,project_title,priority,labels,due_date,done
Set up QoS on router,[Guide link](https://example.com/qos),Homelab Infrastructure,2,networking,,
Configure DNS filtering,"[Article 1](https://example.com/dns1) [Article 2](https://example.com/dns2)",Homelab Infrastructure,3,"networking,dns",,
Research ESP32 smart home,https://example.com/esp32,Home Automation,1,"esp32,hardware",,
```

### Usage

1. Create the CSV file
2. In Vikunja, go to project list → Import
3. Select the CSV file
4. Vikunja auto-creates projects/labels that don't exist
5. Tasks without `project_title` go to "Inbox"
6. Import is additive — never deletes existing tasks

### Bulk Import

A generated CSV at `~/dev/homelab/vikunja-import.csv` contains ~298 tasks across 14 projects organized from saved bookmarks. For complex imports (nested subtasks, bucket assignment), use the Vikunja API directly.

### Best Practices for Import CSVs

1. **Use broad projects, narrow tags** — Instead of "3D Printing - Voron", "3D Printing - SV08", use one "3D Printing" project with `voron`, `sv08`, `prusa` tags. Same for "Homelab" with `network`, `docker`, `kubernetes`, `monitoring`, etc.

2. **Merge overlapping links** — Multiple bookmarks on the same topic → one task with multiple links in the description.

3. **Use priority for triage, labels for complexity** — e.g., `complexity-3`, `complexity-5`, `complexity-8` as labels. Priority (1-3) is for urgency.

4. **Avoid over-splitting** — Before creating a project, ask: "Would this be better as a tag under an existing project?" Two tasks under "3D Printing" with `voron` and `sv08` tags is better than two separate projects.

## Project Organization (Current)

| Project | Typical Tags |
|---------|-------------|
| Homelab | network, docker, kubernetes, monitoring, automation, dashboard, proxmox, storage, security, auth, media, home-automation, ai |
| 3D Printing | sv08, voron, prusa, filament, slicer, calibration |
| Projects & Making | hardware, project, dev-tools, electronics |
| Tools & Utilities | dev-tools, windows, linux, cli |
| Reading & Learning | personal, dev-tools, reference |
| Shopping | shopping |
| Gaming | gaming |
| Media | watching, reading |
