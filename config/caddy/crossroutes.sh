#!/bin/bash
# Add cross-node route so this caddy node can reach the sibling node's isolated
# network during HA failover. Idempotent.
#
# 103 (pve-core, 192.168.1.42) -> 10.30.0.0/24 (arr/qbit on pve-gpu) via 192.168.1.32
# 101 (pve-gpu, 192.168.1.40)  -> 10.31.0.0/24 (pi on pve-core) via 192.168.1.30

LANIP=$(ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1)

case "$LANIP" in
  192.168.1.42)
    ip route add 10.30.0.0/24 via 192.168.1.32 || true
    ;;
  192.168.1.40)
    ip route add 10.31.0.0/24 via 192.168.1.30 || true
    ;;
esac
