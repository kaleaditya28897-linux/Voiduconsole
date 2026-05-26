#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

log() { printf '\033[1;36m[15-install-xfce]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

ROOTFS="work/rootfs"

[ -f work/loop.dev ] || die "work/loop.dev not found — run 10-prepare.sh first"
mountpoint -q "$ROOTFS" || die "work/rootfs not mounted"

CHROOT() { sudo chroot "$ROOTFS" /usr/bin/qemu-aarch64-static /bin/sh -c "$1"; }

cleanup_chroot() {
    sudo umount "$ROOTFS/dev/pts" 2>/dev/null || true
    sudo umount "$ROOTFS/dev"     2>/dev/null || true
    sudo umount "$ROOTFS/sys"     2>/dev/null || true
    sudo umount "$ROOTFS/proc"    2>/dev/null || true
    sudo rm -f "$ROOTFS/usr/bin/qemu-aarch64-static"
    sudo rm -f "$ROOTFS/etc/resolv.conf.bak" 2>/dev/null || true
    sudo mv "$ROOTFS/etc/resolv.conf.bak" "$ROOTFS/etc/resolv.conf" 2>/dev/null || true
}
trap cleanup_chroot EXIT

# Set up qemu and DNS
sudo cp /usr/bin/qemu-aarch64-static "$ROOTFS/usr/bin/qemu-aarch64-static"
[ -f "$ROOTFS/etc/resolv.conf" ] && sudo cp "$ROOTFS/etc/resolv.conf" "$ROOTFS/etc/resolv.conf.bak" || true
sudo cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

# Bind mounts
sudo mount --bind /proc   "$ROOTFS/proc"
sudo mount --bind /sys    "$ROOTFS/sys"
sudo mount --bind /dev    "$ROOTFS/dev"
sudo mount --bind /dev/pts "$ROOTFS/dev/pts"

log "Syncing xbps package index..."
CHROOT "xbps-install -Suy xbps"
CHROOT "xbps-install -Suy"

# xbps-install aborts if a package is already installed; collect only missing ones
log "Checking which packages need installation..."
PKGS_TO_INSTALL=""
for pkg in $XFCE_PACKAGES; do
    if ! sudo chroot "$ROOTFS" /usr/bin/qemu-aarch64-static /bin/sh -c \
            "xbps-query '$pkg' >/dev/null 2>&1"; then
        PKGS_TO_INSTALL="$PKGS_TO_INSTALL $pkg"
    fi
done

if [ -n "$PKGS_TO_INSTALL" ]; then
    log "Installing:$PKGS_TO_INSTALL"
    # shellcheck disable=SC2086
    CHROOT "xbps-install -y $PKGS_TO_INSTALL"
else
    log "All packages already installed"
fi

# Restore setuid bits stripped by qemu-user
log "Restoring setuid bits..."
for bin in /usr/bin/sudo /bin/su /usr/bin/passwd /sbin/unix_chkpwd /usr/bin/newgrp; do
    [ -f "$ROOTFS$bin" ] && sudo chmod 4755 "$ROOTFS$bin" || true
done

log "[ok] XFCE + hardware packages installed"
