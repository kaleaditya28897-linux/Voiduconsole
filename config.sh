# Voiduconsole build config. Override anything by editing this file.

# --- target board ---
# "cm4"  -> ClockworkPi uConsole with Raspberry Pi CM4
# "cm5"  -> ClockworkPi uConsole with Raspberry Pi CM5 (a.k.a. CM5/CM5L)
# "both" -> single universal image that boots on both CM4 and CM5
TARGET="${TARGET:-both}"

# --- output image ---
IMG_NAME="voiduconsole-${TARGET}-$(date +%Y%m%d).img"
IMG_SIZE_MB=6144            # final image size; ~6 GiB fits on a 8GB SD with room to grow
BOOT_SIZE_MB=512
HOSTNAME="uconsole"

# --- default user ---
# Void Linux convention: default user "anon" with password "voidlinux".
# Same default password is set for root so first boot matches a stock Void
# install. Change both immediately after first login with `passwd`.
USERNAME="anon"
USERPASS="voidlinux"
ROOTPASS="voidlinux"
LOCALE="en_IN.UTF-8"
TIMEZONE="Asia/Kolkata"
KEYMAP="us"

# --- void mirror & arch ---
VOID_ARCH="aarch64"
VOID_MIRROR="https://repo-default.voidlinux.org"
VOID_PLATFORMFS_URL="${VOID_MIRROR}/live/current/void-rpi-aarch64-PLATFORMFS-20250202.tar.xz"

# --- clockwork kernel deb ---
# We use ak-rex's community kernel deb because it ships a single, universal kernel
# tree (kernel8.img for CM4 + kernel_2712.img for CM5), all RPi DTBs including
# bcm2712-rpi-cm5-*, *both* the clockworkpi-uconsole (CM4) and
# clockworkpi-uconsole-cm5 device-tree overlays, and module trees for both the
# 4 KiB-page CM4 kernel and the 16 KiB-page CM5 kernel.
#
# The original clockworkpi/apt deb (uconsole-kernel-cm4-rpi) is CM4-only and
# kept here for reference / fall-back.
CLOCKWORK_KERNEL_DEB_URL="https://github.com/ak-rex/ClockworkPi-apt/raw/main/debian/pool/main/c/clockworkpi-kernel/clockworkpi-kernel_6.12.87-v8-16k+_arm64.deb"
CLOCKWORK_KERNEL_DEB_URL_CM4_LEGACY="https://github.com/clockworkpi/apt/raw/main/debian/pool/main/u/uconsole-kernel-cm4-rpi/uconsole-kernel-cm4-rpi_0.13_arm64.deb"

# --- packages to install inside the chroot ---
# Base + WM (labwc/wayland) + GUI tools for connectivity, audio, files, browser, modem.
PACKAGES_BASE="base-system void-repo-nonfree dbus elogind polkit-elogind chrony wpa_supplicant openssh sudo curl wget git nano vim tmux bash-completion man-pages"
PACKAGES_FIRMWARE="linux-firmware-broadcom linux-firmware-network bluez"
PACKAGES_GFX="mesa-dri mesa-vulkan-broadcom xkeyboard-config xkbcomp"
PACKAGES_WAYLAND="labwc foot Waybar fuzzel swaybg swayidle swaylock grim slurp wl-clipboard wlr-randr brightnessctl wob cliphist wlsunset xdg-desktop-portal xdg-desktop-portal-wlr xdg-user-dirs mako greetd ReGreet seatd"
PACKAGES_AUDIO="pipewire wireplumber alsa-pipewire alsa-utils pavucontrol pamixer"
PACKAGES_NET="NetworkManager network-manager-applet ModemManager libmbim libqmi mobile-broadband-provider-info usb-modeswitch socat ppp"
PACKAGES_APPS="firefox-esr Thunar gnome-disk-utility galculator mpv imv gnome-text-editor"
PACKAGES_UTIL="libgpiod i2c-tools usbutils pciutils lsof htop btop fastfetch rsync"

ALL_PACKAGES="$PACKAGES_BASE $PACKAGES_FIRMWARE $PACKAGES_GFX $PACKAGES_WAYLAND $PACKAGES_AUDIO $PACKAGES_NET $PACKAGES_APPS $PACKAGES_UTIL"
