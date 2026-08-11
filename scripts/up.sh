#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "============================================"
echo "  Homelab Deployment"
echo "============================================"
echo ""

echo "--- Step 1/6: Bootstrap ---"
make bootstrap
echo ""

echo "--- Step 2/6: Platform ---"
make platform
echo ""

echo "--- Step 3/6: Create secrets ---"
bash scripts/create-secrets.sh
echo ""

echo "--- Step 4/6: Sync homepage ---"
bash scripts/sync-homepage.sh
echo ""

echo "--- Step 5/6: Deploy K8s ---"
bash scripts/deploy-k8s.sh
echo ""

echo "--- Step 6/6: Check K8s ---"
bash scripts/check-k8s.sh
echo ""

echo "============================================"
echo "  Deployment complete"
echo "============================================"
