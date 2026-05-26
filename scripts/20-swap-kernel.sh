#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

log() { printf '\033[1;36m[20-swap-kernel]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

KERNEL_DEB="downloads/$(basename "$CLOCKWORK_KERNEL_DEB_URL")"

[ -f work/loop.dev ] || die "work/loop.dev missing — run 10-prepare.sh first"
mountpoint -q work/boot   || die "work/boot is not mounted — re-run 10-prepare.sh"
mountpoint -q work/rootfs || die "work/rootfs is not mounted — re-run 10-prepare.sh"

log "Extracting kernel deb..."
rm -rf work/kerneldeb
mkdir -p work/kerneldeb/data
(cd work/kerneldeb && ar x "../../$KERNEL_DEB")
tar -xf work/kerneldeb/data.tar.xz -C work/kerneldeb/data

log "Installing kernel into boot partition..."
sudo cp work/kerneldeb/data/boot/firmware/kernel8.img work/boot/kernel8.img

# DTBs
sudo cp work/kerneldeb/data/boot/firmware/*.dtb work/boot/ 2>/dev/null || \
    log "Warning: no *.dtb found in deb boot/firmware/ — skipping"

# Overlays
sudo mkdir -p work/boot/overlays
sudo find work/kerneldeb/data/boot/firmware/overlays -name '*.dtbo' \
    -exec sudo cp {} work/boot/overlays/ \;
sudo cp work/kerneldeb/data/boot/firmware/overlays/README work/boot/overlays/ 2>/dev/null || true

log "Installing kernel modules (CM4 / 4 KiB page tree)..."
# The ak-rex deb ships both CM4 (*-v8+) and CM5 (*-v8-16k+) module trees.
# We only want the CM4 tree.
CM4_MOD_SRC=$(find work/kerneldeb/data -path '*/lib/modules/*-v8+' -maxdepth 5 -type d | head -1)
[ -n "$CM4_MOD_SRC" ] || die "CM4 module tree (*-v8+) not found in kernel deb"
KVER=$(basename "$CM4_MOD_SRC")
log "Kernel version: $KVER"
sudo cp -a "$CM4_MOD_SRC" "work/rootfs/lib/modules/$KVER"

log "Running depmod inside chroot..."
sudo chroot work/rootfs /usr/bin/qemu-aarch64-static /bin/bash -c \
    'depmod -a '"$KVER"

log "[ok] kernel swapped: $KVER"
log "    kernel8.img  -> work/boot/kernel8.img"
log "    modules      -> work/rootfs/lib/modules/$KVER"
