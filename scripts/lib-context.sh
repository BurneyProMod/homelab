#!/usr/bin/env bash
# Shared guard: require kubectl to point at the homelab k3s cluster.
# Source this file, then call require_k3s_context before any kubectl use.

require_k3s_context() {
  if ! command -v kubectl >/dev/null 2>&1; then
    echo "ERROR: kubectl not found in PATH." >&2
    return 1
  fi

  local ctx server
  ctx=$(kubectl config current-context 2>/dev/null || true)
  server=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)

  # Accept any of the three k3s node kubeconfigs or the canonical one.
  case "$server" in
    *192.168.1.7[012]*|*127.0.0.1*) ;;
    *)
      echo "ERROR: kubectl context is '$ctx' (server: ${server:-<none>})." >&2
      echo "Expected the homelab k3s cluster (192.168.1.70/71/72 or local node). Aborting." >&2
      return 1
      ;;
  esac

  echo "kubectl context OK: $ctx ($server)"
}
