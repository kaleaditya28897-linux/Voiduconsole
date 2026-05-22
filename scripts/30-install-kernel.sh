#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

ROOTFS="$(pwd)/work/rootfs"
TMP="$(pwd)/work/kerneldeb"
sudo rm -rf "$TMP"; mkdir -p "$TMP"

DEB="$(pwd)/downloads/clockworkpi-kernel.deb"
[ -f "$DEB" ] || DEB="$(pwd)/downloads/uconsole-kernel-cm4-rpi.deb"  # legacy filename

echo "[..] extracting ClockworkPi kernel deb: $(basename "$DEB")"
( cd "$TMP" && ar x "$DEB" && tar -xf data.tar.* )

# The ak-rex deb lays things out under ./boot/firmware/, the legacy clockworkpi
# CM4-only deb uses ./boot/. Find whichever the deb shipped.
if [ -d "$TMP/boot/firmware" ]; then
  SRC_BOOT="$TMP/boot/firmware"
else
  SRC_BOOT="$TMP/boot"
fi

# Wipe whatever the Void platformfs shipped under /boot and replace with the
# ClockworkPi kernel + DTBs + overlays.
sudo rm -f  "$ROOTFS"/boot/kernel*.img
sudo rm -f  "$ROOTFS"/boot/*.dtb
sudo rm -rf "$ROOTFS"/boot/overlays

# Kernels: kernel8.img (CM4 / generic aarch64 4 KiB-page) and, when available,
# kernel_2712.img (CM5 / BCM2712 16 KiB-page).
sudo cp -a "$SRC_BOOT"/kernel8.img      "$ROOTFS"/boot/ 2>/dev/null || true
sudo cp -a "$SRC_BOOT"/kernel_2712.img  "$ROOTFS"/boot/ 2>/dev/null || true
# All DTBs (CM4 = bcm2711-rpi-cm4.dtb, CM5 = bcm2712-rpi-cm5-cm4io.dtb etc.).
sudo cp -a "$SRC_BOOT"/*.dtb            "$ROOTFS"/boot/ 2>/dev/null || true
sudo cp -a "$SRC_BOOT"/overlays         "$ROOTFS"/boot/

# Modules: the ak-rex deb ships *two* trees (e.g. 6.12.87-v8+ for the CM4 4 KiB
# kernel and 6.12.87-v8-16k+ for the CM5 16 KiB kernel). Copy both, depmod each.
# Some debs install modules under /usr/lib/modules instead of /lib/modules.
if [ -d "$TMP/lib/modules" ]; then
  MOD_SRC="$TMP/lib/modules"
elif [ -d "$TMP/usr/lib/modules" ]; then
  MOD_SRC="$TMP/usr/lib/modules"
else
  echo "[fail] no module tree found in deb" >&2
  exit 1
fi
sudo mkdir -p "$ROOTFS"/lib/modules
sudo cp -a "$MOD_SRC"/* "$ROOTFS"/lib/modules/

for d in "$ROOTFS"/lib/modules/*/; do
  KVER=$(basename "$d")
  echo "[..] depmod $KVER"
  sudo chroot "$ROOTFS" /usr/bin/qemu-aarch64-static /sbin/depmod -a "$KVER"
done

echo "[ok] kernel(s) installed: $(ls "$ROOTFS"/lib/modules | xargs)"
