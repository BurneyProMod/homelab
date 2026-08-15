#!/usr/bin/env python3
"""Sync network/*.yaml into the Homelable (homelabable) app via its API.

Reads network/topology.yaml (physical links) and network/devices.yaml (physical
devices) and upserts them into the Homelable canvas as nodes + edges on the
chosen design. Idempotent: nodes matched by ip/mac, edges by source+target.

Usage:
    HOMELABLE_URL=https://homelable.burney.network \
    HOMELABLE_USER=<user> HOMELABLE_PASS=<pass> \
        python3 scripts/sync-homelabable.py [--design 'Burney Homelab'] [--dry-run]

Requires python3 + pyyaml (e.g. `python3 -m venv .venv && .venv/bin/pip install pyyaml`).
Uses only stdlib urllib for HTTP (no requests dependency).

The repo YAML is the source of truth; this script pushes it TO the app.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any

import yaml

REPO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def api(base: str, token: str | None, method: str, path: str, body: Any = None) -> dict | list | None:
    url = base.rstrip("/") + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:300]
        raise RuntimeError(f"{method} {path} -> {e.code}: {detail}")


def login(base: str, user: str, pw: str) -> str:
    r = api(base, None, "POST", "/api/v1/auth/login", {"username": user, "password": pw})
    return r["access_token"]


def norm(s: str) -> str:
    return (s or "").strip().lower()


def load_yaml(name: str) -> dict:
    with open(os.path.join(REPO, "network", name)) as f:
        return yaml.safe_load(f)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--design", default="Burney Homelab")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    base = os.environ.get("HOMELABLE_URL", "https://homelable.burney.network")

    devices = load_yaml("devices.yaml")["devices"]
    topology = load_yaml("topology.yaml")

    if args.dry_run:
        print(f"[dry-run] would sync {len(devices)} devices and {len(topology['links'])} links")
        for d in devices:
            print(f"  node {d['hostname']}  ip={d['mgmt_ip']}  mac={d['mac']}")
        for lk in topology["links"]:
            print(f"  edge {lk['a']}[{lk.get('a_port','')}] <-> {lk['b']}[{lk.get('b_port','')}]")
        return

    user = os.environ.get("HOMELABLE_USER")
    pw = os.environ.get("HOMELABLE_PASS")
    # Fall back to ~/.secrets/homelable (username= / password=), repo convention.
    if not user or not pw:
        secret_file = os.environ.get("HOMELABLE_SECRETS", os.path.expanduser("~/.secrets/homelable"))
        if os.path.exists(secret_file):
            with open(secret_file) as f:
                for line in f:
                    line = line.strip()
                    if "=" in line and not line.startswith("#"):
                        k, v = line.split("=", 1)
                        if k == "username" and not user:
                            user = v
                        elif k == "password" and not pw:
                            pw = v
    if not user or not pw:
        sys.exit("HOMELABLE_USER/HOMELABLE_PASS not set (or ~/.secrets/homelable missing)")

    tok = login(base, user, pw)

    # Resolve design
    designs = api(base, tok, "GET", "/api/v1/designs") or []
    design = next((d for d in designs if d["name"] == args.design), None)
    if design is None:
        # create it
        design = api(base, tok, "POST", "/api/v1/designs", {"name": args.design, "design_type": "network"})
    design_id = design["id"]
    print(f"design: {design['name']} ({design_id})")

    existing_nodes = api(base, tok, "GET", "/api/v1/nodes") or []
    by_ip = {norm(n.get("ip")): n for n in existing_nodes if n.get("ip")}
    by_mac = {norm(n.get("mac")): n for n in existing_nodes if n.get("mac")}

    # ── nodes ────────────────────────────────────────────────────────────────
    node_ids: dict[str, str] = {}  # hostname -> node id
    for d in devices:
        host = d["hostname"]
        ip = d.get("mgmt_ip") or ""
        mac = d.get("mac") or ""
        label = d.get("model") or host
        payload = {
            "design_id": design_id,
            "type": d.get("purpose", "device"),
            "label": label,
            "hostname": host,
            "ip": ip or None,
            "mac": mac or None,
            "notes": d.get("notes") or None,
        }
        existing = by_ip.get(norm(ip)) or by_mac.get(norm(mac)) if ip or mac else None
        if existing:
            node_ids[host] = existing["id"]
            api(base, tok, "PATCH", f"/api/v1/nodes/{existing['id']}", payload)
            print(f"  node UPD {host} ({existing['id']})")
        else:
            created = api(base, tok, "POST", "/api/v1/nodes", {**payload, "force": True})
            node_ids[host] = created["id"]
            print(f"  node ADD {host} ({created['id']})")

    # ── edges ────────────────────────────────────────────────────────────────
    existing_edges = api(base, tok, "GET", "/api/v1/edges") or []
    seen = set()
    for lk in topology["links"]:
        a_id = node_ids.get(lk["a"])
        b_id = node_ids.get(lk["b"])
        if not a_id or not b_id:
            print(f"  edge SKIP {lk['a']}<->{lk['b']} (missing node id)")
            continue
        key = tuple(sorted([a_id, b_id]))
        if key in seen:
            continue
        seen.add(key)
        payload = {
            "design_id": design_id,
            "source": a_id,
            "target": b_id,
            "type": "ethernet",
            "label": lk.get("note") or "",
            "source_handle": lk.get("a_port") or None,
            "target_handle": lk.get("b_port") or None,
        }
        match = next((e for e in existing_edges
                      if {e["source"], e["target"]} == {a_id, b_id}), None)
        if match:
            api(base, tok, "PATCH", f"/api/v1/edges/{match['id']}", payload)
            print(f"  edge UPD {lk['a']}[{lk.get('a_port')}]<->{lk['b']}[{lk.get('b_port')}]")
        else:
            api(base, tok, "POST", "/api/v1/edges", payload)
            print(f"  edge ADD {lk['a']}[{lk.get('a_port')}]<->{lk['b']}[{lk.get('b_port')}]")

    print("done")


if __name__ == "__main__":
    main()
