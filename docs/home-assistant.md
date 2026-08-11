# Home Assistant

## Setup & Access

- **URL**: `http://homeassistant.lan:8123`
- **SSH alias**: `homeassistant` → `homeassistant.lan` as root with key `~/.ssh/homeassistant_ed25519`
- **Version**: 2026.7.2 (as of July 2026)
- **MCP Server**: `ha-mcp` (27 tools) — connects through the MCP gateway

## MCP Tools Available

The `ha-mcp` server provides configuration management tools. Key capabilities:

### Read Operations
- `ha_mcp_ha_config_get_dashboard` — List dashboards, get config, search for cards
- `ha_mcp_ha_config_get_automation` — Retrieve automation config by entity_id or unique_id
- `ha_mcp_ha_search` — Search entities, automations, scripts, scenes, helpers, dashboard cards
- `ha_mcp_ha_get_overview` — System summary with entity counts, domain stats
- `ha_mcp_ha_get_entity` — Get detailed state and attributes of a specific entity
- `ha_mcp_ha_config_get_calendar_events` — Retrieve calendar events

### Write Operations
- `ha_mcp_ha_config_set_dashboard` — Create/update dashboards (config replacement or Python transforms)
- `ha_mcp_ha_config_set_automation` — Create/update automations
- `ha_mcp_ha_manage_config_entry` — Delete integration config entries
- `ha_mcp_ha_manage_helper` — Delete helpers (entities, automations, etc.)

## Dashboard Management

### Access

Dashboards are managed via the HA storage API:
```python
# Get a dashboard
ha_mcp_ha_config_get_dashboard(url_path="lovelace")

# List all dashboards
ha_mcp_ha_config_get_dashboard(list_only=True)
```

### Editing with Python Transforms (Recommended)

Python transforms are preferred over full config replacement for surgical edits:

```python
# Replace all cards in a view
config['views'][0]['cards'] = [...]

# Delete a specific card
del config['views'][0]['cards'][1]

# Add a card
config['views'][0]['cards'].append({...})
```

**Important**: After delete/add operations, indices shift. Always fetch a fresh `config_hash` before subsequent transforms.

### Dashboard Tips

- Use `grid` cards for layouts rather than manual CSS
- `square: true` for uniform icon grids (lights, person chips)
- `sections` view type for organization with headings
- Weather entities: `weather.forecast_burney_home`

## Stale Integration Cleanup

When integrations go offline, their config entries leave orphaned entities behind.

### Identifying stale entries
```python
# Check system logs
ha_mcp_ha_config_get_logs(source="system")

# Search for orphaned entities
ha_mcp_ha_get_orphaned_entities()
```

### Removing config entries
```python
ha_mcp_ha_manage_config_entry(action="delete", entry_id="...")
```

### Removing orphaned automations
```python
ha_mcp_ha_manage_helper(action="delete", target="automation.washing_machine_monitor_nfc_registration")
```

## Known Issues & Fixes

### Emporia Vue 3 Power Monitoring

When branch CTs are installed backwards, using `*pos` (positive-only) filter silently zeros out the readings. Use `*abs` (absolute value) instead to reveal hidden loads. Check circuit configuration in the Emporia Vue integration settings.

### Person Tracking (Companion App)

If person entities show `unknown`, the device tracker (phone) isn't sending GPS coordinates. Required on each phone:
1. Home Assistant Companion App installed
2. Location permission set to "Always allow"
3. Battery optimization disabled for the HA app

### Broken Custom Integrations

`hikvision_next` is incompatible with Python 3.14 due to `urllib3.contrib.appengine` removal. Keep if still partially functional, but expect entities to be unavailable.

### Stale Entities After Removal

Deleting a config entry does NOT automatically remove its entities. Run orphan detection after cleanup:
```python
ha_mcp_ha_get_orphaned_entities()
```

## Useful Automations (Template Ideas)

Based on available devices:

1. **Climate setback when away** — person entities leave → set thermostat to eco
2. **Motion-activated lights** — Aqara P1 motion → turn on room lights, turn off after N minutes
3. **Doorbell notification** — front/garage doorbell → TTS announcement on speakers
4. **Power anomaly alert** — Emporia Vue circuit > threshold → notification
5. **Printer complete notification** — moonraker print status → TTS/speaker announcement
6. **Leak detection alarm** — water sensor triggered → all speakers announce
7. **UPS power loss** — NUT sensor on battery → shutdown non-critical devices
