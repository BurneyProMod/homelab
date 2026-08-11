# Home Assistant Integrations

Notes on specific integrations, their quirks, and setup details.

## Emporia Vue 3 (via ESPHome)

Whole-home energy monitoring with 8-16 circuit-level CT clamps.
Integrated through ESPHome (not the cloud-based Emporia integration).

### ESPHome Config Tips

- Use `substitutions` for leg/circuit friendly names — makes them reusable
  across the config
- The `total_power` and per-phase power sensors may read 0 if the mains CT
  clamps aren't properly mapped. Check that `power_sensor` IDs for legs
  are correctly referenced in the ESPHome YAML
- Entities must be **exposed to Assist** to be visible through the
  Home Assistant MCP tools. Go to Settings → Voice assistants → Expose

### ESPHome YAML structure

```yaml
esphome:
  name: emporiavue3
  friendly_name: "${display_name}"

substitutions:
  display_name: "Emporia Vue 3"
  leg_1: "Phase R"
  leg_2: "Phase L"
  cir_1: "Circuit 1"
  # ... cir_2 through cir_16
```

### Debugging ESPHome sensors

If sensors show unexpected values (e.g., per-circuit power works but
total/phase power reads 0):

1. Check ESPHome device logs in Home Assistant for warnings
2. Enable debug logging in the ESPHome device config:
   ```yaml
   logger:
     level: DEBUG
   ```
3. Validate CT clamp assignments — each circuit CT must be mapped to the
   correct phase (leg)

## HA-MCP Server

The Home Assistant Model Context Protocol integration (`ha-mcp`) enables
AI agents to query HA state and control devices through a structured API.

### Startup failure: Python 3.14 KeyError

**Symptom**: ha-mcp add-on fails to start with:
```
KeyError: '__editable__.homeassistant-2026.7.2.finder.__path_hook__'
```

**Root cause**: Home Assistant 2026.7.2 is installed in editable/development
mode on Python 3.14. The `importlib.invalidate_caches()` call in
`embedded_server.py` walks all registered finders and hits a KeyError on
an editable-install finder that's not fully registered.

**Fix**: The error is transient — retrying 5 minutes later typically works.
A permanent fix would require wrapping the `invalidate_caches()` call in
`try/except KeyError` in the ha-mcp source.

**Timeline example**:
- 16:41 — config entry re-added
- 21:30:28 — bring-up failed with KeyError
- 21:35:10 — bring-up succeeded (5 min later, after partial cache invalidation)

### MCP tool limitations

- MCP tools operate through HA's REST/WebSocket API — they cannot read
  raw YAML files from the filesystem
- To read files like `automations.yaml` or `configuration.yaml`, use SSH
  to the HA host instead
- Entities must be exposed to Assist to appear in MCP queries
- After adding entities to Assist, the MCP server may need a moment to
  refresh its entity cache

## Exposing Entities to Assist

Required for entities to be visible through MCP/voice:

1. Home Assistant → Settings → Voice assistants
2. Click "Expose" (or "Expose entities")
3. Find the entities you want to expose
4. Toggle them on

Entities not exposed to Assist are invisible to MCP queries even if they
exist and are active in Home Assistant.
