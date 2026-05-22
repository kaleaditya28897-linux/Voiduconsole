#!/bin/bash
# Voiduconsole: build a ready-to-flash Void Linux glibc image
# for the ClockworkPi uConsole CM4 4G.
#
# Run as a normal user. It will sudo for the privileged steps.
set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJ"
. ./config.sh

log() { printf '\033[1;36m[build]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

require() { command -v "$1" >/dev/null || die "missing tool: $1"; }
for t in xz tar wget parted losetup mkfs.vfat mkfs.ext4 rsync ar; do require "$t"; done
[ -x /usr/bin/qemu-aarch64-static ] || die "install qemu-user-static"
[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || die "aarch64 binfmt not registered (see README)"

# Ensure sudo works non-interactively for this session
sudo -n true 2>/dev/null || sudo -v

bash "$PROJ/scripts/00-download.sh"
bash "$PROJ/scripts/10-prepare-rootfs.sh"
bash "$PROJ/scripts/20-install-packages.sh"
bash "$PROJ/scripts/30-install-kernel.sh"
bash "$PROJ/scripts/40-apply-overlay.sh"
bash "$PROJ/scripts/50-configure-system.sh"
bash "$PROJ/scripts/90-pack-image.sh"

log "Image ready: $PROJ/deploy/$IMG_NAME"
log "Flash with:  sudo dd if=$PROJ/deploy/$IMG_NAME of=/dev/sdX bs=4M status=progress conv=fsync"
