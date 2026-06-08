#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NAS_HOMEPAGE_ROOT="/mnt/syn/k8s/homepage"

mkdir -p "$NAS_HOMEPAGE_ROOT/config"
mkdir -p "$NAS_HOMEPAGE_ROOT/images"

rsync -av --delete \
  "$REPO_ROOT/config/homepage/config/" \
  "$NAS_HOMEPAGE_ROOT/config/"

rsync -av --delete \
  "$REPO_ROOT/config/homepage/images/" \
  "$NAS_HOMEPAGE_ROOT/images/"
