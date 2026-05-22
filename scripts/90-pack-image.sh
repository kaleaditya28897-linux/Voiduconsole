#!/bin/bash
# Build final .img file: 2 partitions (FAT32 /boot, ext4 /), populate, detach.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

ROOTFS="$(pwd)/work/rootfs"
IMG="deploy/$IMG_NAME"
mkdir -p deploy
rm -f "$IMG"

echo "[..] allocating ${IMG_SIZE_MB}M sparse image"
truncate -s "${IMG_SIZE_MB}M" "$IMG"

echo "[..] partitioning"
parted -s "$IMG" mklabel msdos
parted -s "$IMG" mkpart primary fat32 4MiB "$((4 + BOOT_SIZE_MB))MiB"
parted -s "$IMG" mkpart primary ext4 "$((4 + BOOT_SIZE_MB))MiB" 100%
parted -s "$IMG" set 1 boot on

LOOP=$(sudo losetup --show -fP "$IMG")
trap 'sudo umount -lR work/mnt 2>/dev/null || true; sudo losetup -d "$LOOP" 2>/dev/null || true' EXIT
echo "[..] loop = $LOOP"

sudo mkfs.vfat -F32 -n BOOT  "${LOOP}p1"
sudo mkfs.ext4 -F   -L ROOT  "${LOOP}p2"

mkdir -p work/mnt
sudo mount "${LOOP}p2" work/mnt
sudo mkdir -p work/mnt/boot
sudo mount "${LOOP}p1" work/mnt/boot

echo "[..] copying rootfs to image (rsync)"
sudo rsync -aHAX --numeric-ids \
  --exclude=/boot/* \
  "$ROOTFS"/ work/mnt/
sudo rsync -aHAX --numeric-ids \
  "$ROOTFS"/boot/ work/mnt/boot/

# Get the actual root partition UUID and patch cmdline.txt
ROOT_PARTUUID=$(sudo blkid -s PARTUUID -o value "${LOOP}p2")
sudo sed -i "s|ROOTDEV|PARTUUID=${ROOT_PARTUUID}|" work/mnt/boot/cmdline.txt

sync
sudo umount work/mnt/boot
sudo umount work/mnt
sudo losetup -d "$LOOP"
trap - EXIT

echo "[ok] image written: $IMG"
echo "    size: $(du -h "$IMG" | cut -f1)"
