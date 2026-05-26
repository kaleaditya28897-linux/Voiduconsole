#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

log() { printf '\033[1;36m[10-prepare]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

XFCE_IMG_XZ="downloads/$(basename "$VOID_XFCE_IMG_URL")"
WORK_IMG="work/$(basename "${XFCE_IMG_XZ%.xz}")"

mkdir -p work

# Bail early if already mounted from a previous run
if [ -f work/loop.dev ]; then
    EXISTING=$(cat work/loop.dev)
    if sudo losetup "$EXISTING" >/dev/null 2>&1 \
       && mountpoint -q work/boot \
       && mountpoint -q work/rootfs; then
        log "Image already prepared and mounted at $EXISTING — skipping"
        exit 0
    fi
    # Loop device exists but mounts are gone — detach and redo
    sudo umount work/boot work/rootfs 2>/dev/null || true
    sudo losetup -d "$EXISTING" 2>/dev/null || true
    rm -f work/loop.dev
fi

# Decompress (idempotent — skip if already done)
if [ ! -f "$WORK_IMG" ]; then
    log "Decompressing image (this may take a few minutes)..."
    xz -dk "$XFCE_IMG_XZ" --stdout > "$WORK_IMG"
else
    log "Using existing decompressed image: $WORK_IMG"
fi

# Expand file to target size if smaller
CURRENT_SIZE=$(stat -c%s "$WORK_IMG")
TARGET_SIZE=$((IMG_SIZE_MB * 1024 * 1024))
if [ "$CURRENT_SIZE" -lt "$TARGET_SIZE" ]; then
    log "Expanding image from $((CURRENT_SIZE / 1024 / 1024)) MiB to ${IMG_SIZE_MB} MiB..."
    truncate -s "${IMG_SIZE_MB}M" "$WORK_IMG"
fi

# Attach loop device with partition detection
log "Attaching loop device..."
LOOP=$(sudo losetup -f --show -P "$WORK_IMG")
echo "$LOOP" > work/loop.dev
log "Loop device: $LOOP"

# Resize root partition (p2) to fill the new space
log "Resizing root partition to fill expanded space..."
sudo parted -s "$LOOP" resizepart 2 100%
sudo e2fsck -fy "${LOOP}p2" || true
sudo resize2fs "${LOOP}p2"

# Mount both partitions
mkdir -p work/boot work/rootfs
sudo mount "${LOOP}p1" work/boot
sudo mount "${LOOP}p2" work/rootfs

log "[ok] mounted: work/boot ($(df -h work/boot | awk 'NR==2{print $2}')) + work/rootfs ($(df -h work/rootfs | awk 'NR==2{print $2}'))"
