#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

log() { printf '\033[1;36m[30-configure]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

[ -f work/loop.dev ] || die "work/loop.dev missing — run prior stages first"
LOOP=$(cat work/loop.dev)
mountpoint -q work/boot   || die "work/boot is not mounted — re-run 10-prepare.sh"
mountpoint -q work/rootfs || die "work/rootfs is not mounted — re-run 10-prepare.sh"

CHROOT() { sudo chroot work/rootfs /usr/bin/qemu-aarch64-static /bin/bash -c "$*"; }

# --- Boot partition ---
log "Writing config.txt..."
sudo cp overlay-boot/config.txt work/boot/config.txt

log "Patching cmdline.txt with PARTUUID..."
ROOT_PARTUUID=$(sudo blkid -s PARTUUID -o value "${LOOP}p2")
[ -n "$ROOT_PARTUUID" ] || die "Could not read PARTUUID from ${LOOP}p2"
grep -q 'ROOTDEV' overlay-boot/cmdline.txt || die "overlay-boot/cmdline.txt has no ROOTDEV token — cannot patch PARTUUID"
sudo sed "s|ROOTDEV|PARTUUID=$ROOT_PARTUUID|g" overlay-boot/cmdline.txt | \
    sudo tee work/boot/cmdline.txt >/dev/null
log "  PARTUUID: $ROOT_PARTUUID"

# --- Root overlay ---
log "Applying overlay-root/..."
sudo cp -af overlay-root/. work/rootfs/

# --- Hostname ---
log "Setting hostname to '$HOSTNAME'..."
echo "$HOSTNAME" | sudo tee work/rootfs/etc/hostname >/dev/null

# --- Locale and timezone ---
log "Setting locale and timezone..."
CHROOT "ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime"
echo "LANG=$LOCALE" | sudo tee work/rootfs/etc/locale.conf >/dev/null

# --- User setup ---
# Use openssl on the host to generate hashes — chpasswd under qemu-aarch64
# produces broken $6$ hashes that fail unix_chkpwd at login.
log "Setting up user '$USERNAME'..."
ROOT_HASH=$(openssl passwd -6 "$ROOTPASS")
USER_HASH=$(openssl passwd -6 "$USERPASS")
CHROOT "usermod -p '$ROOT_HASH' root"
CHROOT "id $USERNAME >/dev/null 2>&1 || \
    useradd -m -G wheel,audio,video,input,plugdev,network,storage,users,dialout \
            -s /bin/bash $USERNAME"
CHROOT "usermod -p '$USER_HASH' $USERNAME"
CHROOT "chown -R $USERNAME:$USERNAME /home/$USERNAME"

# --- Runit services ---
log "Enabling runit services..."
for s in dbus elogind polkitd NetworkManager ModemManager lightdm; do
    if [ -d "work/rootfs/etc/sv/$s" ]; then
        sudo ln -sf "/etc/sv/$s" "work/rootfs/etc/runit/runsvdir/default/$s"
        log "  enabled: $s"
    else
        log "  Warning: /etc/sv/$s not found — skipping"
    fi
done

log "[ok] system configured"
