# Voiduconsole build config. Override anything by editing this file.

# --- output image ---
IMG_NAME="voiduconsole-cm4-$(date +%Y%m%d).img"
IMG_SIZE_MB=6144            # final image size; ~6 GiB fits on a 8GB SD with room to grow
BOOT_SIZE_MB=512
HOSTNAME="uconsole"

# --- default user ---
USERNAME="aditya"
USERPASS="adi28897"         # change after first boot
ROOTPASS="adi28897"
LOCALE="en_IN.UTF-8"
TIMEZONE="Asia/Kolkata"
KEYMAP="us"

# --- void mirror & arch ---
VOID_ARCH="aarch64"
VOID_MIRROR="https://repo-default.voidlinux.org"
VOID_PLATFORMFS_URL="${VOID_MIRROR}/live/current/void-rpi-aarch64-PLATFORMFS-20250202.tar.xz"

# --- clockwork kernel deb (provides kernel8.img + uconsole dt overlays) ---
CLOCKWORK_KERNEL_DEB_URL="https://github.com/clockworkpi/apt/raw/main/debian/pool/main/u/uconsole-kernel-cm4-rpi/uconsole-kernel-cm4-rpi_0.13_arm64.deb"

# --- packages to install inside the chroot ---
# Base + WM (labwc/wayland) + GUI tools for connectivity, audio, files, browser, modem.
PACKAGES_BASE="base-system void-repo-nonfree dbus elogind polkit-elogind chrony wpa_supplicant openssh sudo curl wget git nano vim tmux bash-completion man-pages"
PACKAGES_FIRMWARE="linux-firmware-broadcom linux-firmware-network bluez"
PACKAGES_GFX="mesa-dri mesa-vulkan-broadcom xkeyboard-config xkbcomp"
PACKAGES_WAYLAND="labwc foot Waybar wofi swaybg swayidle swaylock grim slurp wl-clipboard wlr-randr brightnessctl xdg-desktop-portal xdg-desktop-portal-wlr xdg-user-dirs mako greetd ReGreet seatd"
PACKAGES_AUDIO="pipewire wireplumber alsa-pipewire alsa-utils pavucontrol pamixer"
PACKAGES_NET="NetworkManager network-manager-applet ModemManager libmbim libqmi mobile-broadband-provider-info usb-modeswitch socat ppp"
PACKAGES_APPS="firefox-esr Thunar gnome-disk-utility gnome-system-monitor galculator mpv imv gnome-text-editor"
PACKAGES_UTIL="libgpiod i2c-tools usbutils pciutils lsof htop fastfetch rsync"

ALL_PACKAGES="$PACKAGES_BASE $PACKAGES_FIRMWARE $PACKAGES_GFX $PACKAGES_WAYLAND $PACKAGES_AUDIO $PACKAGES_NET $PACKAGES_APPS $PACKAGES_UTIL"
