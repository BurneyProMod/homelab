# Homelab Network

Canonical physical-network documentation. Single source of truth is this
directory in the homelab repo (`~/dev/homelab/network/` on openbench). It is
git-tracked and reviewed like any other change.

## Files

| File | Contents |
|------|----------|
| `topology.yaml` | **Physical links only** — which device plugs into which switch port. No transient data. |
| `devices.yaml` | Physical device inventory (hostname, IP, MAC, model, location, switch/port, speed, purpose, URL, PoE). |
| `ip-addresses.yaml` | IP plan: /24 classified into classes, current assignments, DHCP pool, future ranges. |
| `README.md` | This file — conventions, hostnames, labels, verification. |
| `baseline-2026-08-15/` | Dated baseline snapshot (UniFi APs/WiFi, LLDP, ARP/DNS). |

Physical vs logical are kept separate: `topology.yaml`+`devices.yaml` are
physical; VM/container placement lives in `ip-addresses.yaml` (guests) and the
logical/service diagram (see Trilium).

## Permanent hostnames (goal 6)

Model names are documentation; these are the operational names. Refer to these
everywhere (Trilium notes, labels, DNS, this repo).

| Hostname | Device | Model | Location |
|----------|--------|-------|----------|
| `fw-opnsense` | router | Shenzhen Zeroone mini PC (OPNsense) | Hallway |
| `sw-hall` | access switch | SODOLA 8-port (unmanaged) | Hallway |
| `sw-hall-core` | core switch | TP-Link TL-SG1024DE | Living Room (metal rack) |
| `sw-poe-ap` | PoE switch | TP-Link TL-SF1005P | Living Room |
| `sw-rack` | rack switch | Netgear GS308E | Living Room (KWS rack bottom) |
| `sw-rack-poe` | PoE rack switch | TP-Link tp-ls108 | Living Room (KWS rack top) |
| `sw-bedroom` | bedroom switch | yuanley ys25-0402 | Master Bedroom |
| `ap-hall` | access point | Ubiquiti U7 Pro | Hallway |
| `ap-u6-lr` | access point | Ubiquiti U6 LR | (offline) |

Existing hostnames (pve-core/exu/gpu, synology, burndev, kwsdisplay, kws-rpi-1,
homeassistant, pikvm, openbench, etc.) are kept as-is.

## Cable labels (goal 5)

Label **both ends** of every important cable. Format:

```
HALL-SW P06 ↔ LR-WALL
LR-WALL    ↔ TL1024 P??
TL1024 P24 ↔ RACK-GS308 P01
GS308 P07  ↔ RACK-POE P08
RACK-POE P01 ↔ KWS-RPI1
RACK-POE P02 ↔ HA
```

Priority: switch uplinks, Proxmox hosts, APs, NAS (Synology), OPNsense,
Home Assistant, PiKVM. Use the hostnames above (e.g. `SW-HALL P06`) — not the
raw model names.

## Verification workflow (goal 26)

Every entry carries a `Last verified` date. When you change a cable or device:

1. Update `topology.yaml` / `devices.yaml` / `ip-addresses.yaml`.
2. Bump the `Last verified` line to today.
3. Run the mapper (`scripts/retest-port.py` / `switch-port-mapper.sh verify`) to
   confirm, or note "physical cable trace".
4. Sync into homelabable (Phase 4 sync script) and update Trilium notes.

Current `Last verified: 2026-08-15`.

## How to regenerate a baseline

```bash
cd ~/dev/homelab
bash scripts/switch-discovery.sh --json > network/baseline-$(date +%F)/switch-discovery.json
# requires ~/.secrets/unifi and key-based SSH to pve-core
```
