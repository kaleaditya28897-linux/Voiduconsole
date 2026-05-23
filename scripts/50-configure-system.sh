#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

ROOTFS="$(pwd)/work/rootfs"

mounts=()
mnt() { sudo mount --bind "$1" "$ROOTFS$2"; mounts+=("$ROOTFS$2"); }
cleanup() { for m in "${mounts[@]}"; do sudo umount -l "$m" 2>/dev/null || true; done; }
trap cleanup EXIT

mnt /proc /proc
mnt /sys /sys
mnt /dev /dev
mnt /dev/pts /dev/pts

CHROOT() { sudo chroot "$ROOTFS" /usr/bin/qemu-aarch64-static /bin/bash -c "$*"; }

echo "[..] hostname / locale / tz"
echo "$HOSTNAME" | sudo tee "$ROOTFS/etc/hostname" >/dev/null
CHROOT "ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime"
# void glibc locale
CHROOT "sed -i 's/^#\(${LOCALE//./\\.} \)/\1/' /etc/default/libc-locales || true"
echo "LANG=$LOCALE" | sudo tee "$ROOTFS/etc/locale.conf" >/dev/null
CHROOT "xbps-reconfigure -f glibc-locales || true"

echo "[..] user setup"
ROOT_HASH=$(openssl passwd -6 "$ROOTPASS")
USER_HASH=$(openssl passwd -6 "$USERPASS")
CHROOT "usermod -p '$ROOT_HASH' root"
CHROOT "useradd -m -G wheel,audio,video,input,plugdev,network,storage,users,dialout -s /bin/bash $USERNAME || true"
CHROOT "usermod -p '$USER_HASH' $USERNAME"
CHROOT "cp -a /etc/skel/.config /home/$USERNAME/ 2>/dev/null || true; chown -R $USERNAME:$USERNAME /home/$USERNAME"

echo "[..] enable runit services"
services="dbus elogind polkitd NetworkManager ModemManager chronyd sshd seatd greetd wpa_supplicant"
for s in $services; do
  if [ -d "$ROOTFS/etc/sv/$s" ]; then
    sudo ln -sf "/etc/sv/$s" "$ROOTFS/etc/runit/runsvdir/default/$s"
  fi
done

echo "[..] greetd: run labwc as _greeter; labwc autostart launches regreet"
sudo tee "$ROOTFS/etc/greetd/config.toml" >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "dbus-run-session -- labwc"
user = "_greeter"
EOF
sudo mkdir -p "$ROOTFS/var/lib/_greeter/.config/labwc"
sudo tee "$ROOTFS/var/lib/_greeter/.config/labwc/autostart" >/dev/null <<EOF
wlr-randr --output DSI-1 --transform 270 2>/dev/null
exec regreet
EOF
sudo tee "$ROOTFS/var/lib/_greeter/.config/labwc/outputs.xml" >/dev/null <<EOF
<?xml version="1.0"?>
<labwc_config><output><name>DSI-1</name><transform>270</transform><scale>1.0</scale></output></labwc_config>
EOF
sudo chroot "$ROOTFS" /usr/bin/qemu-aarch64-static /bin/bash -c "chown -R _greeter:_greeter /var/lib/_greeter"
# _greeter needs seat + input + video access for labwc/regreet to open the seat and HID devices
for g in _seatd seat video input plugdev; do
  CHROOT "getent group $g >/dev/null && usermod -aG $g _greeter && echo '  + _greeter -> $g'" || true
done
for g in _seatd seat; do
  CHROOT "getent group $g >/dev/null && usermod -aG $g $USERNAME && echo '  + $USERNAME -> $g'" || true
done

echo "[..] restore setuid bits stripped by qemu-user xbps-install"
for bin in /usr/bin/sudo /usr/bin/su /usr/bin/passwd /usr/bin/chage /usr/bin/chsh \
           /usr/bin/chfn /usr/bin/gpasswd /usr/bin/newgrp /usr/bin/mount /usr/bin/umount \
           /usr/bin/pkexec; do
  if [ -f "$ROOTFS$bin" ]; then
    sudo chown 0:0 "$ROOTFS$bin"
    sudo chmod 4755 "$ROOTFS$bin"
  fi
done
# unix_chkpwd (PAM password helper) — location varies
sudo find "$ROOTFS/usr" -name unix_chkpwd -exec chown 0:0 {} \; -exec chmod 4755 {} \; 2>/dev/null || true
sudo find "$ROOTFS/usr" -name 'polkit-agent-helper-1' -exec chown 0:0 {} \; -exec chmod 4755 {} \; 2>/dev/null || true
sudo find "$ROOTFS/usr" -name 'dbus-daemon-launch-helper' -exec chown 0:81 {} \; -exec chmod 4754 {} \; 2>/dev/null || true

echo "[..] fstab (mmcblk0p1=/boot, mmcblk0p2=/)"
sudo tee "$ROOTFS/etc/fstab" >/dev/null <<'EOF'
# <fs>             <mountpoint>   <type>   <opts>                          <dump/pass>
/dev/mmcblk0p2     /              ext4     defaults,noatime                0 1
/dev/mmcblk0p1     /boot          vfat     defaults,noatime                0 2
tmpfs              /tmp           tmpfs    defaults,nosuid,nodev           0 0
EOF

# Drop qemu and resolv.conf before packing
sudo rm -f "$ROOTFS/usr/bin/qemu-aarch64-static"
sudo rm -f "$ROOTFS/etc/resolv.conf"

echo "[ok] system configured"
