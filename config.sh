# Voiduconsole build config — CM4-only XFCE base approach.
# Override anything by editing this file.

# --- Void Linux XFCE RPi image ---
# If Void does not publish an XFCE .img.xz for aarch64, update this URL
# to the base RPi image and add "xbps-install -y xfce4 xfce4-goodies lightdm
# lightdm-gtk3-greeter" in scripts/20-swap-kernel.sh after the kernel step.
VOID_XFCE_IMG_URL="https://repo-default.voidlinux.org/live/current/void-rpi-aarch64-XFCE-20250202.img.xz"

# --- clockworkpi CM4 kernel deb (ak-rex universal build) ---
CLOCKWORK_KERNEL_DEB_URL="https://github.com/ak-rex/ClockworkPi-apt/raw/main/debian/pool/main/c/clockworkpi-kernel/clockworkpi-kernel_6.12.87-v8-16k+_arm64.deb"

# --- output image ---
IMG_NAME="voiduconsole-cm4-$(date +%Y%m%d).img"
IMG_SIZE_MB=6144          # 6 GiB; fits an 8 GB SD card

# --- system ---
HOSTNAME="uconsole"
USERNAME="anon"
USERPASS="voidlinux"
ROOTPASS="voidlinux"
TIMEZONE="Asia/Kolkata"
LOCALE="en_IN.UTF-8"
KEYMAP="us"
