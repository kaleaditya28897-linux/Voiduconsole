#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

ROOTFS="$(pwd)/work/rootfs"

echo "[..] copying boot overlay"
sudo cp -af overlay-boot/. "$ROOTFS/boot/"

echo "[..] copying rootfs overlay"
sudo cp -af overlay-root/. "$ROOTFS/"

# correct ownership and modes for things we just dropped in
sudo chown -R root:root "$ROOTFS/etc" "$ROOTFS/usr" "$ROOTFS/boot"
sudo chmod 755 "$ROOTFS"/usr/local/bin/* 2>/dev/null || true
sudo chmod 440 "$ROOTFS"/etc/sudoers.d/* 2>/dev/null || true

echo "[ok] overlays applied"
