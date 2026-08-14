# Home Assistant — Energy Monitoring (Emporia Vue 3)

Notes from setting up and troubleshooting an Emporia Vue 3 energy monitor via ESPHome in Home Assistant.

## Hardware

- **Device**: Emporia Vue 3 (16-circuit energy monitor)
- **Connection**: ESPHome firmware (replaces stock firmware)
- **Communication**: I2C between ESP32 and energy monitoring ICs
- **IP**: 192.168.1.139 (static, on LAN)

## ESPHome Configuration Tips

### CT Clamp Orientation

**Critical finding**: If CT clamps are installed backwards, the `*pos` filter will silently zero out the readings. Using `*abs` is safer for initial setup because it shows power regardless of clamp orientation.

```yaml
# Problem: Only shows positive power, zeroes out reversed clamps
filters:
  - &throttle_avg
    throttle_average: 5s
  - &pos
    lambda: return max(0.0f, x);

# Fix: Show absolute power (reveals backwards clamps)
filters:
  - &throttle_avg
    throttle_average: 5s
  - &abs
    lambda: return std::abs(x);
```

Once clamps are oriented correctly, switch back to `*pos` for accurate directional readings.

### YAML Anchors & Indentation

ESPHome YAML is sensitive to indentation. When using YAML anchors for shared filter chains, ensure each anchor is a separate list item, not nested:

```yaml
# ❌ WRONG — abs/invert/pos nested under throttle
.filters:
  - &throttle_avg
    throttle_average: 5s
    - &abs
      lambda: return std::abs(x);

# ✅ CORRECT — each anchor is a separate list item
.filters:
  - &throttle_avg
    throttle_average: 5s
  - &abs
    lambda: return std::abs(x);
```

### Logging & Debugging

ESPHome log levels for the emporia_vue component:

- `INFO` — connection status, I2C reads
- `DEBUG` — raw I2C hex bytes
- `VERBOSE` — full I2C transaction details

**Limitation**: The `emporia_vue` component does **not** log decoded CT values at any log level — only raw I2C bytes. This makes it hard to debug per-CT-port readings from logs alone.

To change log level for a specific component:

```yaml
logger:
  level: INFO
  logs:
    emporia_vue: DEBUG
    i2c: DEBUG
```

### Flashing & OTA

To pull device logs after flashing, use the ESPHome add-on in Home Assistant:
**Settings → Add-ons → ESPHome → (device) → Logs**

OTA updates are supported — no physical access needed after initial flash.

### Substitutions for Readability

Use substitutions to give circuits meaningful names:

```yaml
substitutions:
  display_name: "Emporia Vue 3"
  leg_1: "Phase R"
  leg_2: "Phase L"
  cir_1: "Furnace"
  cir_2: "Living Room"
  cir_3: "Kitchen"
  # ... etc
```

### 240V Appliances

Larger 240V appliances (HVAC, water heater, dryer, range, EV charger) may not have individual CT clamps if the panel's breaker layout doesn't accommodate 16+ clamps. These show up as the gap between the phase totals and the sum of monitored branch circuits:

```
Phase Total Power - Sum(Branch Circuit Power) = Unmonitored Load
```

## HA Entity Exposure

ESPHome entities are not automatically exposed to Assist. To make them available:

1. Go to **Settings → Voice Assistants → Assist**
2. Expose the ESPHome entities you want accessible via voice/Assist
3. Or use the `assist_pipeline` integration settings

## Useful Entities

After successful setup, the device exposes ~21 entities:
- Phase voltage (L, R)
- Phase power (L, R)  
- Total power
- Per-circuit power (1-16, depending on configuration)
- Daily energy (total and per-phase)
- Device status (RSSI, uptime, etc.)
