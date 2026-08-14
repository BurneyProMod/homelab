#!/usr/bin/env sh
set -eu

HOME="/home/openchamber"

# Ensure opencode config dirs exist (mounted volumes).
mkdir -p "${HOME}/.config/opencode" "${HOME}/.local/share/opencode" "${HOME}/.local/state/opencode" "${HOME}/workspaces"

# SSH: use mounted keys if present, else generate a fresh key (upstream behavior).
SSH_DIR="${HOME}/.ssh"
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}" 2>/dev/null || true
if [ ! -f "${SSH_DIR}/id_ed25519" ]; then
  ssh-keygen -t ed25519 -N "" -f "${SSH_DIR}/id_ed25519" >/dev/null 2>&1 || true
fi
chmod 600 "${SSH_DIR}/id_ed25519" 2>/dev/null || true

# Docker containers must listen on all interfaces for port mapping.
export OPENCHAMBER_HOST="${OPENCHAMBER_HOST:-0.0.0.0}"

echo "[entrypoint] starting openchamber (host ${OPENCHAMBER_HOST})..."
if [ -n "${OPENCHAMBER_UI_PASSWORD:-}" ]; then
  openchamber --ui-password "${OPENCHAMBER_UI_PASSWORD}"
else
  openchamber
fi

# openchamber daemonizes; keep the container alive by tailing logs.
echo "[entrypoint] daemon started, tailing logs..."
exec openchamber logs
