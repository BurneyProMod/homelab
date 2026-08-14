#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "============================================"
echo "  Homelab Deployment (bootstrap.sh stages)"
echo "============================================"
echo ""
echo "This drives the rebuild flow. Run stages in order, or pass a single"
echo "stage: bash scripts/bootstrap.sh --stage N"
echo ""

echo "--- Step 1/9: Validate repo (stage 0) ---"
bash scripts/bootstrap.sh --stage 0 --dry-run
echo ""

echo "--- Step 2/9: Infra - Proxmox LXC/VMs (stage 1) ---"
echo "  (dry-run; run 'bash scripts/bootstrap.sh --stage 1 --apply' to create)"
bash scripts/bootstrap.sh --stage 1 --dry-run
echo ""

echo "--- Step 3/9: OS bootstrap - docker, NFS, cron (stage 2) ---"
echo "  (dry-run; requires existing guests)"
bash scripts/bootstrap.sh --stage 2 --dry-run
echo ""

echo "--- Step 4/9: k3s cluster (stage 3) ---"
echo "  (dry-run; run --apply on a fresh cluster)"
bash scripts/bootstrap.sh --stage 3 --dry-run
echo ""

echo "--- Step 5/9: Secrets (stage 4) ---"
bash scripts/bootstrap.sh --stage 4 --dry-run
echo ""

echo "--- Step 6/9: Docker stacks (stage 5) ---"
bash scripts/bootstrap.sh --stage 5 --dry-run
echo ""

echo "--- Step 7/9: K8s manifests (stage 6) ---"
bash scripts/bootstrap.sh --stage 6 --dry-run
echo ""

echo "--- Step 8/9: File configs - caddy, step-ca (stage 7) ---"
bash scripts/bootstrap.sh --stage 7 --dry-run
echo ""

echo "--- Step 9/9: Data restore (stage 8) ---"
echo "  (still HARD-DISABLED in restore-app-data.sh pending review)"
bash scripts/bootstrap.sh --stage 8 --dry-run
echo ""

echo "============================================"
echo "  Deployment preview complete"
echo "  To apply:  bash scripts/bootstrap.sh --stage N --apply"
echo "  One shot:  bash scripts/bootstrap.sh --apply  (after review)"
echo "============================================"
