#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

ROOTFS="$(pwd)/work/rootfs"

# Bind mounts for chroot
mounts=()
mnt() { sudo mount --bind "$1" "$ROOTFS$2"; mounts+=("$ROOTFS$2"); }
cleanup() { for m in "${mounts[@]}"; do sudo umount -l "$m" 2>/dev/null || true; done; }
trap cleanup EXIT

sudo mkdir -p "$ROOTFS"/{proc,sys,dev,dev/pts,tmp,run}
mnt /proc /proc
mnt /sys /sys
mnt /dev /dev
mnt /dev/pts /dev/pts

CHROOT() { sudo chroot "$ROOTFS" /usr/bin/qemu-aarch64-static /bin/bash -c "$*"; }

echo "[..] syncing xbps & installing nonfree repo"
CHROOT "xbps-install -Suy xbps" || true
CHROOT "xbps-install -Suy"
CHROOT "xbps-install -y void-repo-nonfree"
CHROOT "xbps-install -Suy"

echo "[..] installing packages (this takes a while)"
# xbps-install errors out hard when a package is already at the latest
# version. Filter to only those not yet installed.
NEED=""
for p in $ALL_PACKAGES; do
  if ! sudo chroot "$ROOTFS" /usr/bin/qemu-aarch64-static /usr/bin/xbps-query "$p" >/dev/null 2>&1; then
    NEED="$NEED $p"
  fi
done
echo "[..] need:$NEED"
if [ -n "$NEED" ]; then
  CHROOT "xbps-install -y $NEED"
fi

echo "[ok] packages installed"
