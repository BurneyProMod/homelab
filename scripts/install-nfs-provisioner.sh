#!/usr/bin/env bash
set -euo pipefail

# Installs nfs-subdir-external-provisioner for dynamic NFS PV provisioning.
# Creates the "nfs" StorageClass backed by the Synology NAS at 192.168.1.11.

NFS_SERVER="${NFS_SERVER:-192.168.1.11}"
NFS_PATH="${NFS_PATH:-/volume1/homelab/k8s}"

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required but not found in PATH" >&2
  exit 1
fi

helm repo add nfs-subdir-external-provisioner \
  https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/ 2>/dev/null || true
helm repo update

helm upgrade --install nfs-provisioner \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --version 4.0.18 \
  --namespace kube-system \
  --atomic --wait \
  --set nfs.server="$NFS_SERVER" \
  --set nfs.path="$NFS_PATH" \
  --set storageClass.name=nfs \
  --set storageClass.defaultClass=false \
  --set storageClass.accessModes=ReadWriteMany \
  --set storageClass.reclaimPolicy=Retain

echo "NFS provisioner installed. StorageClass 'nfs' is ready."
