#!/usr/bin/env python3
"""Monitor a fixed set of hosts while one switch port is unplugged.

Reports which targets drop (and stay down) with timestamps, plus a control
host used to prove the monitor itself kept network connectivity throughout the
test. The control host must NOT be reachable only through the cable under test.

Usage:
    python3 retest-port.py --targets 192.168.1.125,192.168.1.129 \
        --control 192.168.1.1 --duration 90

Run the monitor on a host that is NOT in the blast radius of the cable being
pulled (e.g. pve-core for anything on the yuanley / bedroom branch), then
unplug the port, leave it out ~15-20s, and reconnect it.
"""
import argparse
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime


def now() -> str:
    return datetime.now().strftime("%H:%M:%S")


def ping(ip: str, timeout: int) -> bool:
    r = subprocess.run(
        ["ping", "-c", "1", "-W", str(timeout), ip],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return r.returncode == 0


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--targets", required=True, help="comma-separated IPs to monitor")
    ap.add_argument("--control", default="192.168.1.1",
                    help="control IP that must stay up for results to be trusted")
    ap.add_argument("--duration", type=int, default=90)
    ap.add_argument("--misses", type=int, default=2)
    ap.add_argument("--interval", type=float, default=1.5)
    ap.add_argument("--timeout", type=int, default=1, help="per-ping timeout (s)")
    args = ap.parse_args()

    targets = [t.strip() for t in args.targets.split(",") if t.strip()]
    all_hosts = targets + ([args.control] if args.control not in targets else [])

    state = {h: True for h in all_hosts}     # current up/down
    misses = {h: 0 for h in all_hosts}
    down_since = {}                           # host -> timestamp it went DOWN
    ever_down = set()                         # hosts that dropped at any point

    print(f"[{now()}] monitoring {len(all_hosts)} host(s) for {args.duration}s "
          f"(control={args.control}, misses={args.misses}, interval={args.interval}s)")
    print(f"    targets: {', '.join(targets)}")
    print("    >>> PULL THE CABLE NOW, leave out 15-20s, then reconnect. <<<")
    sys.stdout.flush()

    end = time.time() + args.duration
    with ThreadPoolExecutor(max_workers=len(all_hosts)) as ex:
        while time.time() < end:
            round_start = time.time()
            for h, ok in ex.map(lambda ip: (ip, ping(ip, args.timeout)), all_hosts):
                if ok:
                    if not state[h]:
                        print(f"[{now()}] UP   {h}")
                    state[h] = True
                    misses[h] = 0
                else:
                    misses[h] += 1
                    if misses[h] >= args.misses and state[h]:
                        state[h] = False
                        down_since[h] = now()
                        ever_down.add(h)
                        print(f"[{now()}] DOWN {h}")
            sys.stdout.flush()
            time.sleep(max(0, args.interval - (time.time() - round_start)))

    print("\n=== RESULT ===")
    control_ok = state.get(args.control, False)
    print(f"control {args.control}: "
          f"{'UP (monitor stayed connected; results reliable)' if control_ok else 'DOWN (monitor lost path; results UNRELIABLE)'}")
    down_now = [h for h in targets if not state[h]]
    if down_now:
        print("DOWN at test end:")
        for h in down_now:
            print(f"    {h}  (down since {down_since.get(h, '?')})")
    else:
        print("no targets DOWN at test end")
    if ever_down:
        print(f"dropped at some point (incl. flapping): {', '.join(sorted(ever_down))}")


if __name__ == "__main__":
    main()
