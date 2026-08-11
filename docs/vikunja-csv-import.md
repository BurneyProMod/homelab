# Vikunja CSV Import Format

How to generate a Vikunja-compatible CSV for bulk import of projects and tasks.

## CSV Format

```csv
title,description,project_title,priority,labels,due_date,done
```

### Columns

| Column | Required | Description |
|--------|----------|-------------|
| `title` | Yes | Task title |
| `description` | No | Task description (Markdown supported, can include URLs) |
| `project_title` | No | Project name — tasks with the same project_title are grouped. If empty, task goes to "Inbox" |
| `priority` | No | 0=None, 1=Low, 2=Medium, 3=High, 4=Urgent |
| `labels` | No | Comma-separated label names |
| `due_date` | No | Format: `YYYY-MM-DD` |
| `done` | No | `true` or `false` (default: false) |

## Example

```csv
title,description,project_title,priority,labels,due_date,done
Set up QoS on router,[Guide link](https://example.com/qos),Homelab Infrastructure,3,networking,,
Configure DNS filtering,"[Article 1](https://example.com/dns1) [Article 2](https://example.com/dns2)",Homelab Infrastructure,4,networking,dns,,
Research ESP32 smart home,https://example.com/esp32,Home Automation,2,esp32,hardware,,
```

## Usage

1. Create the CSV file
2. In Vikunja, go to project list → Import
3. Select the CSV file
4. Vikunja will:
   - Create projects for any `project_title` values that don't exist
   - Create tasks under those projects
   - Set priority, labels, and due dates as specified

## Notes

- Multiple URLs in description: Use Markdown links or plain URLs
- One task can have multiple links if there's enough topic overlap
- Tasks without a `project_title` go to the default "Inbox" project
- Labels are created automatically if they don't exist
- The import is additive — it won't delete existing tasks

## Scripting Bulk Import

Since Vikunja's CSV import only supports tasks (not nested subtasks or bucket assignment), for more complex imports use the Vikunja API directly. A generated CSV at `~/dev/homelab/vikunja-import.csv` contains ~298 tasks across 14 projects organized from saved bookmarks.
