#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

log() { printf '\033[1;36m[00-download]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

mkdir -p downloads

RPI_IMG_XZ="downloads/$(basename "$VOID_RPI_IMG_URL")"
KERNEL_DEB="downloads/$(basename "$CLOCKWORK_KERNEL_DEB_URL")"

if [ ! -f "$RPI_IMG_XZ" ]; then
    log "Checking RPi base image URL..."
    wget -q --spider "$VOID_RPI_IMG_URL" 2>/dev/null || \
        die "RPi image not found at $VOID_RPI_IMG_URL — update VOID_RPI_IMG_URL in config.sh"
    log "Downloading Void Linux RPi base image (~500 MiB)..."
    wget -O "${RPI_IMG_XZ}.part" "$VOID_RPI_IMG_URL" && mv "${RPI_IMG_XZ}.part" "$RPI_IMG_XZ"
else
    log "Cached: $RPI_IMG_XZ"
fi

if [ ! -f "$KERNEL_DEB" ]; then
    log "Downloading clockworkpi kernel deb..."
    wget -O "${KERNEL_DEB}.part" "$CLOCKWORK_KERNEL_DEB_URL" && mv "${KERNEL_DEB}.part" "$KERNEL_DEB"
else
    log "Cached: $KERNEL_DEB"
fi

log "[ok] downloads complete"
