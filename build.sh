#!/bin/bash
# Voiduconsole: patch the official Void XFCE RPi image for ClockworkPi uConsole CM4.
# Run as a normal user; will sudo for chroot/loopdev/mount.
set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJ"
. ./config.sh

log() { printf '\033[1;36m[build]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

require() { command -v "$1" >/dev/null || die "missing tool: $1"; }
for t in xz wget parted losetup resize2fs e2fsck rsync ar blkid; do require "$t"; done
[ -x /usr/bin/qemu-aarch64-static ] || die "install qemu-user-static"
[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || die "aarch64 binfmt not registered (see README)"

sudo -n true 2>/dev/null || sudo -v

bash "$PROJ/scripts/00-download.sh"
bash "$PROJ/scripts/10-prepare.sh"
bash "$PROJ/scripts/20-swap-kernel.sh"
bash "$PROJ/scripts/30-configure.sh"
bash "$PROJ/scripts/40-finalise.sh"

log "Image ready: $PROJ/deploy/$IMG_NAME"
log "Flash with:  sudo dd if=$PROJ/deploy/$IMG_NAME of=/dev/sdX bs=4M status=progress conv=fsync"
