# Voiduconsole build config — CM4-only, base RPi image + XFCE install.
# Override anything by editing this file.

# --- Void Linux base RPi image ---
# Void does not publish a pre-built XFCE RPi image; we use the base image and
# install XFCE in stage 15 via xbps-install inside the chroot.
VOID_RPI_IMG_URL="https://repo-default.voidlinux.org/live/current/void-rpi-aarch64-20250202.img.xz"

# --- clockworkpi CM4 kernel deb (ak-rex universal build) ---
CLOCKWORK_KERNEL_DEB_URL="https://github.com/ak-rex/ClockworkPi-apt/raw/main/debian/pool/main/c/clockworkpi-kernel/clockworkpi-kernel_6.12.87-v8-16k+_arm64.deb"

# --- output image ---
IMG_NAME="voiduconsole-cm4-$(date +%Y%m%d).img"
IMG_SIZE_MB=6144          # 6 GiB; fits an 8 GB SD card

# --- XFCE package set installed in stage 15 ---
# xorg-server + drivers must be explicit — xfce4 meta-package does not pull
# them in reliably inside a chroot.  xf86-video-modesetting is the correct
# driver for vc4 KMS on CM4 (not fbdev).
XFCE_PACKAGES="xorg-server xf86-video-modesetting xf86-input-libinput \
    xfce4 lightdm lightdm-gtk3-greeter \
    NetworkManager network-manager-applet ModemManager libmbim libqmi \
    mobile-broadband-provider-info usb-modeswitch \
    pipewire wireplumber alsa-pipewire alsa-utils \
    libgpiod"

# --- system ---
HOSTNAME="uconsole"
USERNAME="anon"
USERPASS="voidlinux"
ROOTPASS="voidlinux"
TIMEZONE="Asia/Kolkata"
LOCALE="en_IN.UTF-8"
KEYMAP="us"
