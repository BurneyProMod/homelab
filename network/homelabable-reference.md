# Homelabable Reference — generated from network/*.yaml (2026-08-15)

Physical topology + IoT/WiFi devices for building the homelabable diagram.

## Physical devices by room

### Hallway
  - `fw-opnsense` | ip=192.168.1.1 | mac=e4:3a:6e:5e:33:2e | Shenzhen Zeroone mini PC (OPNsense) | on sw-core p1
  - `sw-core` | ip=192.168.1.2 | mac=1c:2a:a3:24:22:09 | SODOLA 8-port switch (unmanaged, 2.5G)
  - `ap-hall` | ip=192.168.1.161 | mac=8c:ed:e1:98:23:40 | Ubiquiti U7 Pro (U7PRO) | on sw-core p7

### Living Room
  - `sw-livrom` | ip=192.168.1.115 | TP-Link TL-SG1024DE (24-port smart switch) | on sw-core p6
  - `sw-livrom-poe` | TP-Link TL-SF1005P (5-port PoE switch, 10/100) | on sw-livrom p1
  - `sw-kws` | Netgear GS308E (8-port managed switch) | on sw-livrom p24
  - `sw-kws-poe` | TP-Link tp-ls108 (8-port PoE switch) | on sw-kws p7
  - `pve-core` | ip=192.168.1.30 | mac=e8:6a:64:f2:62:f9 | LCFC/Lenovo (Proxmox VE) | on sw-kws p5
  - `pve-exu` | ip=192.168.1.31 | mac=e8:6a:64:bf:d1:f7 | LCFC/Lenovo (Proxmox VE) | on sw-kws p6
  - `pve-gpu` | ip=192.168.1.32 | mac=6c:4b:90:bc:9c:61 | LiteON/Dell (Proxmox VE, GPU) | on sw-kws p4
  - `synology` | ip=192.168.1.11 | mac=90:09:d0:0f:ff:0d | Synology NAS | on sw-kws p3
  - `kwsdisplay` | ip=192.168.1.168 | mac=d8:3a:dd:18:ac:bb | Raspberry Pi | on sw-kws p8
  - `kws-rpi-1` | ip=192.168.1.125 | mac=d8:3a:dd:67:28:75 | Raspberry Pi | on sw-kws-poe p1
  - `homeassistant` | ip=192.168.1.129 | mac=dc:a6:32:8a:e4:87 | Raspberry Pi | on sw-kws-poe p2
  - `burndev` | ip=192.168.1.50 | mac=30:9c:23:d9:6e:56 | MSI (Micro-Star) | on sw-livrom p23
  - `hue-bridge` | ip=192.168.1.180 | mac=ec:b5:fa:06:84:9b | Philips Hue Bridge | on sw-livrom p3
  - `android-tv` | Android TV | on sw-livrom p7
  - `ap-u6-lr` | mac=ac:8b:a9:4a:27:b1 | Ubiquiti U6 Long-Range (UALR6v2) | on sw-livrom-poe p

### Master Bedroom
  - `sw-masbed` | yuanley ys25-0402 (4-port switch, unmanaged) | on sw-core p4
  - `desktop-3u0m8bh` | ip=192.168.1.100 | mac=e8:9c:25:6d:4b:b2 | ASUSTek (Windows desktop) | on sw-masbed p2
  - `pikvm` | ip=192.168.1.197 | mac=e4:5f:01:e4:92:c9 | Raspberry Pi (PiKVM) | on sw-masbed p3
  - `openbench` | ip=192.168.1.199 | mac=20:12:21:68:01:a7 | Bazzite desktop (workstation) | on sw-masbed p4

### Master Bedroom Closet
  - `hikvision` | ip=192.168.1.145 | mac=b4:a3:82:c3:a1:f6 | Hikvision IP camera | on sw-core p3

### Back Bedroom (Kevin)
  - `thewoober` | ip=192.168.1.101 | mac=a0:ad:9f:85:b7:38 | ASUSTek (Kevin's gaming PC) | on sw-core p2

### Front Bedroom (Jeff)
  - `jeff-pc` | ip=192.168.1.102 | mac=a8:a1:59:a6:e2:be | ASRock (PC) | on sw-core p5

## Links

  - `fw-opnsense` [LAN] <-> `sw-core` [1]
  - `sw-core` [2] <-> `thewoober` [eth]  # Kevin's bedroom (back bedroom) wall jack
  - `sw-core` [3] <-> `hikvision` [eth]  # Master Bedroom Closet wall jack (dedicated)
  - `sw-core` [4] <-> `sw-masbed` [1]  # Master bedroom wall jack -> yuanley uplink
  - `sw-core` [5] <-> `jeff-pc` [eth]  # Front bedroom (Jeff's room) wall jack
  - `sw-core` [6] <-> `sw-livrom` [-]  # Living room wall jack -> metal rack (TL-SG1024DE)
  - `sw-core` [7] <-> `ap-hall` [eth]  # U7 Pro, direct (not a wall run)
  - `sw-livrom` [1] <-> `sw-livrom-poe` [1]  # PoE switch feeding U6 LR AP
  - `sw-livrom` [3] <-> `hue-bridge` [eth]  # Philips Hue Bridge (in metal rack)
  - `sw-livrom` [7] <-> `android-tv` [eth]  # Android TV (left of metal rack)
  - `sw-livrom` [23] <-> `burndev` [eth]  # burndev (right of KWS rack)
  - `sw-livrom` [24] <-> `sw-kws` [1]  # uplink -> GS308E main/trunk (KWS rack)
  - `sw-kws` [3] <-> `synology` [eth]
  - `sw-kws` [4] <-> `pve-gpu` [eth]
  - `sw-kws` [5] <-> `pve-core` [eth]
  - `sw-kws` [6] <-> `pve-exu` [eth]
  - `sw-kws` [7] <-> `sw-kws-poe` [8]  # uplink -> tp-ls108
  - `sw-kws` [8] <-> `kwsdisplay` [eth]
  - `sw-kws-poe` [1] <-> `kws-rpi-1` [eth]
  - `sw-kws-poe` [2] <-> `homeassistant` [eth]
  - `sw-masbed` [2] <-> `desktop-3u0m8bh` [eth]
  - `sw-masbed` [3] <-> `pikvm` [eth]
  - `sw-masbed` [4] <-> `openbench` [eth]

## IoT / WiFi devices (candidates for IOT99 VLAN)

All WiFi, associated to ap-hall (U7 Pro) unless noted. No switch port — attach as leaf nodes under ap-hall or their room.

### IoT (WiFi)
  - `emporiavue3`  ip=192.168.1.139  mac=6c:c8:40:7b:a0:68
  - `prusa-core-one-l`  ip=192.168.1.176  mac=8c:4f:00:ed:20:77
  - `prusa`  ip=192.168.1.190  mac=3c:e9:0e:e6:a5:8d
  - `voron24`  ip=192.168.1.123  mac=54:78:c9:94:3c:96
  - `hs300`  ip=192.168.1.105  mac=40:ae:30:40:1d:33
  - `kp115`  ip=192.168.1.186  mac=54:af:97:08:d2:04
  - `nest-cam-indoor`  ip=192.168.1.140  mac=1c:53:f9:29:97:cc
  - `nest-cam`  ip=192.168.1.106  mac=d8:eb:46:1e:cf:92
  - `nest-hello-263b`  ip=192.168.1.133  mac=44:bb:3b:1f:26:3b
  - `nest-hello-ed6a`  ip=192.168.1.127  mac=f0:ef:86:f7:ed:6a
  - `nest-09AA01AC501805L3`  ip=192.168.1.117  mac=64:16:66:95:31:1e
  - `google-home-mini`  ip=192.168.1.110  mac=00:f6:20:47:93:9c
  - `google-home-mini`  ip=192.168.1.104  mac=44:07:0b:b0:30:6e
  - `google-device`  ip=192.168.1.107  mac=38:86:f7:11:6f:a1
  - `broadlink-remote`  ip=192.168.1.175  mac=e8:70:72:08:3a:a7
  - `ipad`  ip=192.168.1.163  mac=02:03:e3:ce:88:61
  - `?`  ip=192.168.1.165  mac=88:49:2d:a2:d2:f1  (Shenzhen Bilian — identify)
  - `wifi-1c-d6-be`  ip=192.168.1.103  mac=1c:d6:be:df:ca:2f  (Wistron Neweb (smart TV/device) — identify)

### Mobile / personal (WiFi)
  - `pixel-8-pro`  ip=192.168.1.189  mac=8e:a9:ac:f4:cd:fb
  - `kevin-s23`  ip=192.168.1.169  mac=6e:bb:c2:0b:e4:07
  - `optimus`  ip=192.168.1.132  mac=04:f0:21:35:a8:cb

### Wired IoT (already in physical section)
  - hikvision (camera, closet jack), hue-bridge (living room)

## IoT VLAN notes

- OPNsense IOT99 (vlan02/opt4, 192.168.99.0/24) exists, DHCP range configured, but no clients yet.
- 'TEMP - Allow IoT everywhere' rule is the current posture (wide open).
- Wired IoT (hikvision, hue) + ~18 WiFi IoT devices are the IOT99 candidate set.