#!/usr/bin/env bash
# Canonical NAS paths for the homelab repo. Source this file, then use the
# variables. Override NAS_ROOT per host (e.g. burndev mounts the same share at
# /mnt/syn) by exporting it before sourcing.

: "${NAS_ROOT:=/mnt/synology/homelab}"
REPO_MIRROR="$NAS_ROOT/repo"
BACKUP_ROOT="$NAS_ROOT/backups/homelab"
