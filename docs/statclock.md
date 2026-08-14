# StatClock — ESP32 CS2 Stat Tracking Display

A CS2 stat-tracking display that fetches player stats from the FACEIT API (and eventually Leetify/Twitch) and shows them on a physical ESP32-driven display.

Repository: `~/dev/statclock/`

## Architecture

```
┌─────────────┐     FACEIT API      ┌──────────────┐
│  Go CLI     │ ◄────────────────── │  open.faceit  │
│  (main.go)  │                     │  .com/data/v4 │
└──────┬──────┘                     └──────────────┘
       │ stdout (ELO, matches, etc.)
       ▼
┌─────────────┐
│  ESP32-C3   │  ◄── ESPHome (esp32.yaml)
│  Display     │
└─────────────┘
```

## Project Structure

| Path | Purpose |
|------|---------|
| `main.go` | Go CLI — fetches FACEIT data (ELO, matches, account age, win/loss) |
| `leetify.go` | Go data models for Leetify API (not yet wired up) |
| `esp32.yaml` | ESPHome top-level config — selects display profile |
| `display/` | Display profiles: `max7219_7seg.yaml`, `max7219_dotmat.yaml`, `tm1637.yaml` |
| `images/` | Showcase photos |
| `.env.example` | Template for API keys |

## Setup

### Prerequisites

```bash
# For Go CLI
sudo apt install -y golang

# For ESPHome / ESP32 flashing
sudo apt install -y pipx
pipx install esphome
```

### Go CLI

```bash
cd ~/dev/statclock

# Initialize module (if go.mod doesn't exist)
go mod init statclock
go mod tidy

# Set up API credentials
cp .env.example .env
# Edit .env with your FACEIT API key and nickname

# Run checks
go vet ./...
go build ./...

# Query stats
go run . -metric elo        # Current ELO
go run . -metric matches    # Total matches
go run . -metric age        # Account age in days
go run . -metric wl         # Win/Loss
```

### ESP32 Flashing

```bash
# Validate config
esphome config esp32.yaml

# Compile check (no flash)
esphome compile esp32.yaml

# Flash to ESP32
esphome run esp32.yaml
```

## Display Profiles

Edit `esp32.yaml` line: `substitutions.display_profile: <profile>`

| Profile | Display Type | File |
|---------|-------------|------|
| `max7219_7seg` | MAX7219 8-digit 7-segment | `display/max7219_7seg.yaml` |
| `max7219_dotmat` | MAX7219 32x8 dot matrix | `display/max7219_dotmat.yaml` |
| `tm1637` | TM1637 4-digit | `display/tm1637.yaml` |

### Wiring (MAX7219)

| ESP32 GPIO | MAX7219 Pin |
|-----------|-------------|
| GPIO4 (MOSI) | DIN |
| GPIO5 (SCLK) | CLK |
| GPIO6 | CS |
| 3V3/5V | VCC |
| GND | GND |

### Wiring (TM1637)

| ESP32 GPIO | TM1637 Pin |
|-----------|------------|
| GPIO4 | DIO |
| GPIO5 | CLK |
| 3V3/5V | VCC |
| GND | GND |

## FACEIT API

- API base: `https://open.faceit.com/data/v4`
- Auth: Bearer token in `FACEIT_API_KEY`
- Endpoints used:
  - `GET /players?nickname=...&game=cs2` — player lookup
  - `GET /players/{player_id}/stats/cs2` — detailed stats

## TODO (from README)

- Fix font scaling / look into different displays
- Store local variables in SQLite
- Display extended FaceIT stats
- Leetify API integration
- Twitch API integration
- Edit case .stl to fit under 3D Printed AWP Asiimov

## Environment Variables

```bash
FACEIT_API_KEY=your_key_here       # Required
FACEIT_NICKNAME=username_here      # Required (or FACEIT_NAME)
FACEIT_GAME=cs2                    # Default: cs2
FACEIT_METRIC=elo                  # Default: elo
```
