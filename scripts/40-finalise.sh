#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

log() { printf '\033[1;36m[40-finalise]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

[ -f work/loop.dev ] || die "work/loop.dev missing — nothing to finalise"
LOOP=$(cat work/loop.dev)

log "Unmounting partitions..."
sudo umount work/boot   || true
sudo umount work/rootfs || true

log "Detaching loop device $LOOP..."
sudo losetup -d "$LOOP"
rm -f work/loop.dev

WORK_IMG=$(ls work/*.img 2>/dev/null | head -1)
[ -n "$WORK_IMG" ] || die "No .img found in work/ — did a previous stage fail?"

mkdir -p deploy
log "Moving image to deploy/$IMG_NAME..."
mv "$WORK_IMG" "deploy/$IMG_NAME"

log "[ok] Image ready: deploy/$IMG_NAME"
log "Flash: sudo dd if=deploy/$IMG_NAME of=/dev/sdX bs=4M status=progress conv=fsync"
