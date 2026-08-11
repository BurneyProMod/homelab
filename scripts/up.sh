#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "============================================"
echo "  Homelab Deployment"
echo "============================================"
echo ""

echo "--- Step 1/5: Validate repo ---"
bash scripts/validate.sh
echo ""

echo "--- Step 2/5: Create secrets ---"
bash scripts/create-secrets.sh
echo ""

echo "--- Step 3/5: Deploy K8s (dry-run preview) ---"
bash scripts/deploy-k8s.sh --dry-run
echo ""

echo "--- Step 4/5: Deploy K8s ---"
bash scripts/deploy-k8s.sh
echo ""

echo "--- Step 5/5: Check K8s ---"
bash scripts/check-k8s.sh
echo ""

echo "============================================"
echo "  Deployment complete"
echo "  Docker Compose stacks: run 'make deploy-docker' on the target host"
echo "  (host targeting automation is P1 in docs/gitops-plan.md)"
echo "============================================"
