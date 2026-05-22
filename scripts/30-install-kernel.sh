#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

ROOTFS="$(pwd)/work/rootfs"
TMP="$(pwd)/work/kerneldeb"
sudo rm -rf "$TMP"; mkdir -p "$TMP"

echo "[..] extracting ClockworkPi kernel deb"
( cd "$TMP" && ar x "$(pwd)/../../downloads/uconsole-kernel-cm4-rpi.deb" \
  && tar -xf data.tar.* )

# Replace /boot kernel/dtb/overlays with ClockworkPi's
sudo rm -f "$ROOTFS"/boot/kernel*.img
sudo rm -f "$ROOTFS"/boot/*.dtb
sudo rm -rf "$ROOTFS"/boot/overlays
sudo cp -a "$TMP"/boot/kernel8.img "$ROOTFS"/boot/
sudo cp -a "$TMP"/boot/*.dtb        "$ROOTFS"/boot/ 2>/dev/null || true
# clockwork deb only ships bcm2711-rpi-cm4.dtb -- that is the one CM4 needs
sudo cp -a "$TMP"/boot/overlays     "$ROOTFS"/boot/

# Modules
sudo mkdir -p "$ROOTFS"/lib/modules
sudo cp -a "$TMP"/lib/modules/* "$ROOTFS"/lib/modules/
KVER=$(ls "$TMP"/lib/modules | head -n1)
sudo chroot "$ROOTFS" /usr/bin/qemu-aarch64-static /sbin/depmod -a "$KVER"

echo "[ok] kernel $KVER installed"
