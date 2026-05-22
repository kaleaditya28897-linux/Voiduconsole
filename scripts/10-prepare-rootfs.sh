#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

ROOTFS="work/rootfs"
sudo rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"

echo "[..] extracting void platformfs..."
sudo tar -xpf downloads/void-platformfs.tar.xz -C "$ROOTFS"

# qemu-user-static for transparent chroot exec
sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/qemu-aarch64-static"

# resolver for xbps in chroot
sudo cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

echo "[ok] rootfs at $ROOTFS"
