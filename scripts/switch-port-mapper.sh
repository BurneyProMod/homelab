#!/usr/bin/env bash
# switch-port-mapper — wrapper around the Python implementation.
# Usage:
#   scripts/switch-port-mapper.sh verify [--report out.md]
#   scripts/switch-port-mapper.sh map
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="python3"
# Prefer a venv with pyyaml if present
for cand in "$DIR/../.venv/bin/python" "$DIR/.venv/bin/python"; do
  if [ -x "$cand" ] && "$cand" -c 'import yaml' 2>/dev/null; then
    PY="$cand"
    break
  fi
done

if ! "$PY" -c 'import yaml' 2>/dev/null; then
  echo "ERROR: pyyaml required. Run: python3 -m venv .venv && .venv/bin/pip install pyyaml" >&2
  exit 1
fi

exec "$PY" "$DIR/switch-port-mapper.py" "$@"
