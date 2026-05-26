#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

log() { printf '\033[1;36m[00-download]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

mkdir -p downloads

XFCE_IMG_XZ="downloads/$(basename "$VOID_XFCE_IMG_URL")"
KERNEL_DEB="downloads/$(basename "$CLOCKWORK_KERNEL_DEB_URL")"

if [ ! -f "$XFCE_IMG_XZ" ]; then
    log "Checking XFCE image URL..."
    wget -q --spider "$VOID_XFCE_IMG_URL" 2>/dev/null || \
        die "XFCE image not found at $VOID_XFCE_IMG_URL
  → Update VOID_XFCE_IMG_URL in config.sh.
  → If Void only ships a base RPi image, use that URL and add an xfce4 install
    step in scripts/20-swap-kernel.sh (see comment in config.sh)."
    log "Downloading Void XFCE RPi image (~1 GiB)..."
    wget -O "${XFCE_IMG_XZ}.part" "$VOID_XFCE_IMG_URL" && mv "${XFCE_IMG_XZ}.part" "$XFCE_IMG_XZ"
else
    log "Cached: $XFCE_IMG_XZ"
fi

if [ ! -f "$KERNEL_DEB" ]; then
    log "Downloading clockworkpi kernel deb..."
    wget -O "${KERNEL_DEB}.part" "$CLOCKWORK_KERNEL_DEB_URL" && mv "${KERNEL_DEB}.part" "$KERNEL_DEB"
else
    log "Cached: $KERNEL_DEB"
fi

log "[ok] downloads complete"
