#!/usr/bin/env python3
"""switch-port-mapper — cable-pull discovery + topology verification.

Subcommands:
  verify  — Read network/topology.yaml + network/devices.yaml, ping every
            device's management IP, cross-check the topology, and emit a
            verification report (drift detection).
  map     - Interactive cable-pull discovery (unplug a port, see which hosts
            drop). Legacy interactive tooling lives in the original
            ~/Downloads/switch-port-mapper.sh; this subcommand is a thin
            pointer to it for now.

Requires python3 + pyyaml. Use a venv: `python3 -m venv .venv &&
.venv/bin/pip install pyyaml`.
"""
import argparse
import concurrent.futures
import os
import subprocess
import sys

import yaml

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
NET = os.path.join(REPO, "network")


def ping(ip: str) -> bool:
    r = subprocess.run(
        ["ping", "-c", "1", "-W", "1", ip],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    return r.returncode == 0


def load_net(name: str):
    with open(os.path.join(NET, name)) as f:
        return yaml.safe_load(f)


def cmd_verify(args) -> int:
    devices = load_net("devices.yaml")["devices"]
    topology = load_net("topology.yaml")

    # collect every hostname referenced in topology links
    topo_hosts = set()
    for lk in topology["links"]:
        topo_hosts.add(lk["a"])
        topo_hosts.add(lk["b"])

    dev_by_host = {d["hostname"]: d for d in devices}
    ip_hosts = {d["hostname"]: d["mgmt_ip"] for d in devices if d.get("mgmt_ip")}

    # cross-check: topology references hosts that exist in devices.yaml
    missing_in_devices = sorted(topo_hosts - set(dev_by_host))
    unused_in_topology = sorted(set(dev_by_host) - topo_hosts)

    # ping all management IPs
    targets = [(h, ip) for h, ip in ip_hosts.items()]
    with concurrent.futures.ThreadPoolExecutor(max_workers=24) as ex:
        results = {h: ex.submit(ping, ip) for h, ip in targets}

    up, down = [], []
    for h, ip in targets:
        (up if results[h].result() else down).append((h, ip))

    print(f"verification report (2026-08-15) — {len(devices)} devices, "
          f"{len(topology['links'])} links")
    print(f"\n=== devices UP ({len(up)}) ===")
    for h, ip in sorted(up, key=lambda x: x[0]):
        print(f"  {h:<22} {ip}")
    print(f"\n=== devices DOWN / unreachable ({len(down)}) ===")
    for h, ip in sorted(down, key=lambda x: x[0]):
        print(f"  {h:<22} {ip}")
    print("\n=== topology cross-check ===")
    print(f"  links in topology.yaml: {len(topology['links'])}")
    if missing_in_devices:
        print(f"  WARN hosts in topology but MISSING in devices.yaml: {missing_in_devices}")
    if unused_in_topology:
        print(f"  note devices.yaml hosts not referenced in topology: {unused_in_topology}")
    print("\n  (devices without a management IP are not pinged: e.g. unmanaged switches)")

    if args.report:
        with open(args.report, "w") as f:
            f.write(f"# Network verification — 2026-08-15\n\n")
            f.write(f"Devices up: {len(up)}  down: {len(down)}  total: {len(targets)}\n")
            for h, ip in sorted(down, key=lambda x: x[0]):
                f.write(f"- DOWN {h} ({ip})\n")
            for h, ip in sorted(up, key=lambda x: x[0]):
                f.write(f"- UP {h} ({ip})\n")
        print(f"\nreport written: {args.report}")
    return 0


def cmd_map(args) -> int:
    legacy = os.path.expanduser("~/Downloads/switch-port-mapper.sh")
    if not os.path.exists(legacy):
        print("interactive mapper not found at ~/Downloads/switch-port-mapper.sh; "
              "copy the original into the repo (scripts/) to use `map`.")
        return 1
    print(f"note: interactive `map` is provided by the legacy script: {legacy}")
    return subprocess.call([legacy])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    v = sub.add_parser("verify", help="verify documented topology vs live reachability")
    v.add_argument("--report", help="write a markdown report to this path")
    v.set_defaults(func=cmd_verify)
    m = sub.add_parser("map", help="interactive cable-pull discovery (legacy)")
    m.set_defaults(func=cmd_map)
    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
