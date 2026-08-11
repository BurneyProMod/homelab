# Home Assistant — Device & Integration Management

Best practices for managing Home Assistant devices, integrations, and dashboards based on real troubleshooting sessions.

## Removing Stale Devices & Integrations

### Identifying Stale Integrations

Check Home Assistant logs for recurring connection errors:

1. **Settings → System → Logs** — look for repeated connection failures
2. Common stale patterns:
   - `Error connecting to <ip>:<port>` — device unreachable
   - `Python <version> incompatibility` — integration needs update/removal
   - `Failed to set up` / `Setup failed` — integration config broken

### Safe Removal Process

```yaml
# In configuration.yaml, remove or comment out the integration
# Then restart HA: Settings → System → Restart
```

Or use the UI: **Settings → Devices & Services → (integration) → ⋮ → Delete**

**Note**: When removing devices, choose **"Delete"** rather than "Ignore" so that the device can be re-discovered later if it comes back online.

### Example Session: Cleaned Integrations

| Integration | Issue | Action |
|---|---|---|
| Pi-hole (`192.168.1.2`) | Unreachable, can't connect or determine API version | Removed |
| hikvision_next | Python 3.14 incompatibility | Kept (pending update) |
| Sovol SV08 (moonraker) | Printer no longer in use | Removed |
| Additional stale device | No longer present | Removed |

## Dashboard Management

### Dashboard Types

Home Assistant supports two dashboard storage modes:

1. **UI-created** — stored in `.storage/lovelace*`, managed through the HA UI
2. **YAML-defined** — declared in `configuration.yaml` via `lovelace:` key, or in separate YAML files

UI-created dashboards show up in the API and can be read by MCP tools. YAML-defined dashboards may not show up in API queries.

### Reading Dashboards

The HA MCP (`ha-mcp` server) can read dashboards created through the UI:
- `ha_get_dashboard` — get dashboard configuration
- `ha_get_overview` — system overview including dashboard list

**Limitation**: Dashboards defined in YAML (`configuration.yaml` or `ui-lovelace.yaml`) may not appear in API results. Full filesystem access (SSH) is needed to read those.

### Editing Dashboards

The MCP tools **cannot** edit dashboards. Options:
1. **HA UI** — drag-and-drop editor at `http://<ha-ip>:8123`
2. **Manual YAML** — edit `ui-lovelace.yaml` or the raw config via SSH
3. **API** — POST to `/api/lovelace/config` with a long-lived access token

## Automation Design

When designing automations, consider:

1. **Triggers** — what starts the automation (state change, time, event, MQTT)
2. **Conditions** — when should it NOT run (time range, state checks, presence)
3. **Actions** — what to do (notify, control devices, call services)

### Useful Automation Patterns

| Pattern | Example |
|---|---|
| Motion → Light | Motion sensor triggers lights, auto-off after N minutes |
| Package Delivery → Notification | Mail sensor change → phone notification |
| Door/Window → Alert | Contact sensor open while away → notification |
| Device Offline → Alert | Integration unavailable → notification |
| Time-based | Turn off all lights at midnight |
| Presence-based | Away mode when all phones leave |

### Automation Tips

- Set `mode: single` for most automations (prevents parallel runs)
- Use `initial_state: true` to ensure automations are enabled on restart
- Test with **Run** button in UI before relying on triggers
- Check logs after HA restart for automation setup errors

## Entity Management

### Finding Entities

```yaml
# In configuration.yaml, get the full entity list via:
# Settings → Devices & Services → Entities
```

Or use MCP: `GetLiveContext` with domain filter, or `ha_mcp_ha_get_overview`.

### Entity Naming Convention

Entities exposed to Assist need friendly names. Rename in:
**Settings → Devices & Services → Entities → (entity) → ⋮ → Rename**

### Troubleshooting Unknown Entities

| Cause | Fix |
|---|---|
| Device offline | Check device power/network |
| Integration removed | Re-add integration |
| Companion app killed | Disable battery optimization for HA app |
| GPS permission denied | Grant "Always" location permission |
| Entity renamed | Update all references (automations, scripts, dashboards) |
