# OPNsense Firewall & Routing — as-built

Captured live 2026-08-15 via OPNsense REST API (read-only key) + dnsmasq settings.
Source of truth for firewall state; physical topology lives in `topology.yaml`.

## Interfaces / VLANs

| Interface | Device | Subnet | Role |
|-----------|--------|--------|------|
| WAN  | igc0 | 76.72.56.0/24 (LUS Fiber, gw 76.72.56.1) | Internet |
| LAN  | igc1 | 192.168.1.1/24 | Main / trusted |
| MGMT | vlan01 (opt1) | 192.168.2.1/24 | Management VLAN |
| HomeVPN | wg0 (opt2) | (WireGuard) | VPN |
| MNTR | igc5 (opt3) | (unused range) | Monitoring |
| IOT99 | vlan02 (opt4) | 192.168.99.1/24 | IoT VLAN (mostly empty) |

## DHCP (dnsmasq, authoritative)

- LAN `192.168.1.100–199` (domain `lan`), IPv6 `::1000–::2000`
- MGMT `192.168.2.50–199` (domain `lan`)
- IOT99 `192.168.99.100–199`
- DNS registration off (`regdhcp=0`, `regdhcpstatic=0`)
- Static host bindings (dnsmasq `hosts`): burndev, TheWoober (.101), Jeff_PC (.102),
  DESKTOP-3U0M8BH (.100), hikvision, hibyr4_eva, pve-core/gpu/exu, pikvm, sodola
- Only IP reservation: DESKTOP-3U0M8BH = .100 (E8:9C:25:6D:4B:B2)

## DNS overrides (Unbound)

- `*.burndev.lan` → 192.168.1.50 (wildcard; Caddy on burndev)
- `*.pve.lan` → 192.168.1.10 (wildcard)
- `*.burney.network` → 192.168.1.10 (wildcard; "Entryway IP into Proxmox HA")

## Aliases

| Alias | Type | Content |
|-------|------|---------|
| GamingPCS | host | 192.168.1.100, .101, .102 |
| ACUnity_TCP / ACUnity_UDP | port | Assassin's Creed Unity port sets |
| STEAM_UDP | port | 27000:27050, 3478, 4379, 4380 |
| bogons / bogonsv6 / sshlockout / virusprot | external | built-in tables |

## Firewall rules (43 total: 37 automatic, 6+ user)

### Wide-open / temporary (security review targets)
- **opt2 → any** "Temporary allow HomeVPN clients" (TEMP)
- **opt1 → any** "Temporary allow MGMT net" (TEMP)
- **opt4 → any** "TEMP - Allow IoT everywhere" (TEMP)
- LAN → any (default allow, IPv4 + IPv6) — trusted-net default

### Port forwards (WAN → internal)
| Proto | Port | Target | Rule |
|-------|------|--------|------|
| TCP | 51820 | wanip | WireGuard HomeVPN inbound |
| TCP | 6969 | 192.168.1.114 | ~~Fika SPT Backend~~ **STALE** (dup of .101 set) |
| UDP | 25565 | 192.168.1.114 | ~~Fika Game~~ **STALE** (dup of .101 set) |
| TCP | 6969 | 192.168.1.101 | Tarkov Port Forward (TheWoober) |
| UDP | 25565 | 192.168.1.101 | Fika Game Networking (TheWoober) |
| TCP | ACUnity_TCP | 192.168.1.101 | AC Unity forward (TheWoober) |
| UDP | ACUnity_UDP | 192.168.1.101 | AC Unity forward (TheWoober) |

The `.114` rules are **stale duplicates** — leftover from when TheWoober (now
`.101`) hosted the Tarkov/SPT server on a different IP. Cleanup candidates:
delete the two `.114` forwards; verify the `.101` set is still wanted.

### Automatic (default posture)
- Block all IPv6, default deny / state violation, port-0 blocks
- sshlockout (22/443), virusprot overload table
- Bogon + private-network blocks on WAN
- DHCP server allows (LAN + MGMT), anti-lockout (22/80/443), outbound self

## Notes / TODOs
- **Stale port-forwards**: two rules target `192.168.1.114` (Fika SPT 6969, Fika Game 25565) — stale duplicates of the `.101` (TheWoober) set; delete them.
- TheWoober (.101) exposes 4 inbound port sets (Tarkov/SPT/AC Unity) for Kevin's game hosting — review whether still needed.
- 3 wide-open TEMP rules should become scoped rules once VLAN traffic is defined (goals 22–24).
- DHCP reservations for infra devices (goal 11) not yet created.

Last verified: 2026-08-15
