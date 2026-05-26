# XFCE-Base Image Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the from-scratch Void Linux build with a simpler pipeline that loop-mounts the official Void XFCE RPi image and patches in the ClockworkPi CM4 kernel + hardware config.

**Architecture:** Five numbered stage scripts (00–40) orchestrated by `build.sh`; each stage operates on a loop-mounted working copy of the official Void XFCE RPi `.img`. No `xbps-install` stage, no setuid fixups, no Wayland stack.

**Tech Stack:** bash, qemu-aarch64-static (chroot only for depmod + user setup), losetup, parted, resize2fs, wget, ar/tar

---

## File Map

| Action | Path | Responsibility |
|--------|------|---------------|
| Rewrite | `config.sh` | All tunables — URLs, image size, credentials, locale |
| Rewrite | `build.sh` | Orchestrator — prereq checks, run stages 00–40 |
| Rewrite | `scripts/00-download.sh` | Download XFCE img.xz + kernel deb into `downloads/` |
| Create | `scripts/10-prepare.sh` | Decompress, expand, loop-mount both partitions |
| Create | `scripts/20-swap-kernel.sh` | Install clockworkpi kernel/dtbs/modules, depmod |
| Create | `scripts/30-configure.sh` | Apply overlays, boot config, chroot user/locale/services |
| Create | `scripts/40-finalise.sh` | Unmount, detach loop, move img to `deploy/` |
| Modify | `overlay-boot/config.txt` | Strip `[pi5]` section — CM4 only |
| Keep | `overlay-boot/cmdline.txt` | Already correct (ROOTDEV placeholder + rotation flags) |
| Create | `overlay-root/etc/X11/xorg.conf.d/99-uconsole-rotate.conf` | X11 display rotation |
| Keep | `overlay-root/etc/modprobe.d/blacklist-qmi.conf` | QMI blacklist — no change |
| Keep | `overlay-root/etc/polkit-1/rules.d/50-uconsole-nm-mm.rules` | Polkit — no change |
| Keep | `overlay-root/etc/sudoers.d/10-wheel` | Sudoers — no change |
| Keep | `overlay-root/etc/sudoers.d/uconsole-4g` | NOPASSWD — no change |
| Keep | `overlay-root/etc/udev/rules.d/99-uconsole.rules` | udev — no change |
| Fix | `overlay-root/usr/local/bin/uconsole-4g` | Rename commands `enable→on`, `disable→off` |
| Delete | `scripts/10-prepare-rootfs.sh` | Replaced by 10-prepare.sh |
| Delete | `scripts/20-install-packages.sh` | No package install stage |
| Delete | `scripts/30-install-kernel.sh` | Folded into 20-swap-kernel.sh |
| Delete | `scripts/40-apply-overlay.sh` | Folded into 30-configure.sh |
| Delete | `scripts/50-configure-system.sh` | Replaced by 30-configure.sh |
| Delete | `scripts/90-pack-image.sh` | Replaced by 40-finalise.sh |
| Delete | `overlay-root/etc/greetd/` | Using LightDM from XFCE image |
| Delete | `overlay-root/etc/skel/` | XFCE defaults ship with the image |
| Delete | `overlay-root/usr/local/bin/` (all except uconsole-4g) | Custom tools removed |
| Delete | `overlay-root/usr/share/applications/` | .desktop files removed |
| Delete | `xbps-src-templates/` | Not needed in this approach |
| Rewrite | `CLAUDE.md` | Reflect new approach |

---

## Task 1: Delete old files

**Files:** All paths listed as "Delete" in the file map above.

- [ ] **Step 1: Remove old scripts**

```bash
rm scripts/10-prepare-rootfs.sh \
   scripts/20-install-packages.sh \
   scripts/30-install-kernel.sh \
   scripts/40-apply-overlay.sh \
   scripts/50-configure-system.sh \
   scripts/90-pack-image.sh
```

Expected: no error, files gone.

- [ ] **Step 2: Remove Wayland/greetd overlay-root content**

```bash
rm -rf overlay-root/etc/greetd \
       overlay-root/etc/skel \
       overlay-root/usr/share \
       overlay-root/usr/local/bin/labwc-greeter \
       overlay-root/usr/local/bin/uconsole-brightness \
       overlay-root/usr/local/bin/uconsole-call \
       overlay-root/usr/local/bin/uconsole-cheatsheet \
       overlay-root/usr/local/bin/uconsole-clip \
       overlay-root/usr/local/bin/uconsole-menu \
       overlay-root/usr/local/bin/uconsole-osd-bri \
       overlay-root/usr/local/bin/uconsole-osd-vol \
       xbps-src-templates
```

- [ ] **Step 3: Verify remaining overlay-root tree**

```bash
find overlay-root -type f | sort
```

Expected output (exactly these files, nothing else):
```
overlay-root/etc/modprobe.d/blacklist-qmi.conf
overlay-root/etc/polkit-1/rules.d/50-uconsole-nm-mm.rules
overlay-root/etc/sudoers.d/10-wheel
overlay-root/etc/sudoers.d/uconsole-4g
overlay-root/etc/udev/rules.d/99-uconsole.rules
overlay-root/usr/local/bin/uconsole-4g
```

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: nuke old from-scratch build scripts and Wayland overlay"
```

---

## Task 2: Rewrite `config.sh`

**Files:**
- Modify: `config.sh`

- [ ] **Step 1: Verify the file before editing**

```bash
grep -c PACKAGES config.sh
```

Expected: a number > 0 (the old file has PACKAGES variables we're removing).

- [ ] **Step 2: Overwrite with new content**

Replace the entire file with:

```bash
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
```

- [ ] **Step 3: Verify PACKAGES are gone**

```bash
grep PACKAGES config.sh
```

Expected: no output (exit 1 from grep is fine, means nothing matched).

- [ ] **Step 4: Commit**

```bash
git add config.sh
git commit -m "config: replace package-list approach with XFCE image URL"
```

---

## Task 3: Rewrite `build.sh`

**Files:**
- Modify: `build.sh`

- [ ] **Step 1: Check current stage list**

```bash
grep 'bash.*scripts' build.sh
```

Expected: 7 lines (the old 7 stages).

- [ ] **Step 2: Overwrite with new orchestrator**

```bash
#!/bin/bash
# Voiduconsole: patch the official Void XFCE RPi image for ClockworkPi uConsole CM4.
# Run as a normal user; will sudo for chroot/loopdev/mount.
set -euo pipefail

PROJ="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJ"
. ./config.sh

log() { printf '\033[1;36m[build]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

require() { command -v "$1" >/dev/null || die "missing tool: $1"; }
for t in xz wget parted losetup resize2fs e2fsck rsync ar blkid; do require "$t"; done
[ -x /usr/bin/qemu-aarch64-static ] || die "install qemu-user-static"
[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ] || die "aarch64 binfmt not registered (see README)"

sudo -n true 2>/dev/null || sudo -v

bash "$PROJ/scripts/00-download.sh"
bash "$PROJ/scripts/10-prepare.sh"
bash "$PROJ/scripts/20-swap-kernel.sh"
bash "$PROJ/scripts/30-configure.sh"
bash "$PROJ/scripts/40-finalise.sh"

log "Image ready: $PROJ/deploy/$IMG_NAME"
log "Flash with:  sudo dd if=$PROJ/deploy/$IMG_NAME of=/dev/sdX bs=4M status=progress conv=fsync"
```

- [ ] **Step 3: Make executable**

```bash
chmod +x build.sh
```

- [ ] **Step 4: Verify stage count**

```bash
grep 'bash.*scripts' build.sh | wc -l
```

Expected: `5`

- [ ] **Step 5: Commit**

```bash
git add build.sh
git commit -m "build: rewrite orchestrator for 5-stage XFCE patch approach"
```

---

## Task 4: Write `scripts/00-download.sh`

**Files:**
- Create: `scripts/00-download.sh`

- [ ] **Step 1: Verify the old 00-download.sh is gone**

```bash
grep -c VOID_PLATFORMFS scripts/00-download.sh 2>/dev/null && echo "OLD FILE EXISTS" || echo "ok, old file absent or updated"
```

- [ ] **Step 2: Write the new download script**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

log() { printf '\033[1;36m[00-download]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

mkdir -p downloads

XFCE_IMG_XZ="downloads/$(basename "$VOID_XFCE_IMG_URL")"
KERNEL_DEB="downloads/$(basename "$CLOCKWORK_KERNEL_DEB_URL")"

if [ ! -f "$XFCE_IMG_XZ" ]; then
    log "Checking XFCE image URL..."
    wget -q --spider "$VOID_XFCE_IMG_URL" 2>/dev/null || \
        die "XFCE image not found at $VOID_XFCE_IMG_URL
  → Update VOID_XFCE_IMG_URL in config.sh.
  → If Void only ships a base RPi image, use that URL and add an xfce4 install
    step in scripts/20-swap-kernel.sh (see comment in config.sh)."
    log "Downloading Void XFCE RPi image (~1 GiB)..."
    wget -O "$XFCE_IMG_XZ" "$VOID_XFCE_IMG_URL"
else
    log "Cached: $XFCE_IMG_XZ"
fi

if [ ! -f "$KERNEL_DEB" ]; then
    log "Downloading clockworkpi kernel deb..."
    wget -O "$KERNEL_DEB" "$CLOCKWORK_KERNEL_DEB_URL"
else
    log "Cached: $KERNEL_DEB"
fi

log "[ok] downloads complete"
```

- [ ] **Step 3: Make executable**

```bash
chmod +x scripts/00-download.sh
```

- [ ] **Step 4: Verify the script references the right variables**

```bash
grep 'VOID_XFCE_IMG_URL\|CLOCKWORK_KERNEL_DEB_URL' scripts/00-download.sh
```

Expected: 3 lines — two variable references in the URL check/download blocks and one in the cached log.

- [ ] **Step 5: Commit**

```bash
git add scripts/00-download.sh
git commit -m "feat: add 00-download stage for XFCE image + kernel deb"
```

---

## Task 5: Write `scripts/10-prepare.sh`

**Files:**
- Create: `scripts/10-prepare.sh`

This stage decompresses the XFCE image, expands it to `IMG_SIZE_MB`, loop-mounts both partitions, and writes the loop device path to `work/loop.dev` for subsequent stages.

- [ ] **Step 1: Write the script**

```bash
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
    if sudo losetup "$EXISTING" >/dev/null 2>&1; then
        log "Image already loop-mounted at $EXISTING — skipping prepare stage"
        exit 0
    fi
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/10-prepare.sh
```

- [ ] **Step 3: Verify the script**

```bash
bash -n scripts/10-prepare.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 4: Commit**

```bash
git add scripts/10-prepare.sh
git commit -m "feat: add 10-prepare stage — decompress, expand, loop-mount"
```

---

## Task 6: Write `scripts/20-swap-kernel.sh`

**Files:**
- Create: `scripts/20-swap-kernel.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

log() { printf '\033[1;36m[20-swap-kernel]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

KERNEL_DEB="downloads/$(basename "$CLOCKWORK_KERNEL_DEB_URL")"

[ -f work/loop.dev ] || die "work/loop.dev missing — run 10-prepare.sh first"

log "Extracting kernel deb..."
rm -rf work/kerneldeb
mkdir -p work/kerneldeb/data
(cd work/kerneldeb && ar x "../../$KERNEL_DEB")
tar -xf work/kerneldeb/data.tar.xz -C work/kerneldeb/data

log "Installing kernel into boot partition..."
sudo cp work/kerneldeb/data/boot/kernel8.img work/boot/kernel8.img

# DTBs
sudo cp work/kerneldeb/data/boot/*.dtb work/boot/ 2>/dev/null || \
    log "Warning: no *.dtb found at top level of deb boot/ — skipping"

# Overlays
sudo mkdir -p work/boot/overlays
sudo find work/kerneldeb/data/boot/overlays -name '*.dtbo' \
    -exec sudo cp {} work/boot/overlays/ \;
sudo cp work/kerneldeb/data/boot/overlays/README work/boot/overlays/ 2>/dev/null || true

log "Installing kernel modules (CM4 / 4 KiB page tree)..."
# The ak-rex deb ships both CM4 (*-v8+) and CM5 (*-v8-16k+) module trees.
# We only want the CM4 tree.
CM4_MOD_SRC=$(find work/kerneldeb/data -path '*/lib/modules/*-v8+' -maxdepth 5 -type d | head -1)
[ -n "$CM4_MOD_SRC" ] || die "CM4 module tree (*-v8+) not found in kernel deb"
KVER=$(basename "$CM4_MOD_SRC")
log "Kernel version: $KVER"
sudo cp -a "$CM4_MOD_SRC" "work/rootfs/lib/modules/$KVER"

log "Running depmod inside chroot..."
sudo chroot work/rootfs /usr/bin/qemu-aarch64-static /bin/bash -c \
    "depmod -a $KVER"

log "[ok] kernel swapped: $KVER"
log "    kernel8.img  -> work/boot/kernel8.img"
log "    modules      -> work/rootfs/lib/modules/$KVER"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/20-swap-kernel.sh
```

- [ ] **Step 3: Syntax check**

```bash
bash -n scripts/20-swap-kernel.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 4: Commit**

```bash
git add scripts/20-swap-kernel.sh
git commit -m "feat: add 20-swap-kernel stage — install clockworkpi CM4 kernel"
```

---

## Task 7: Update `overlay-boot/config.txt` (strip CM5)

**Files:**
- Modify: `overlay-boot/config.txt`

- [ ] **Step 1: Verify the CM5 section currently exists**

```bash
grep -c 'pi5\|CM5' overlay-boot/config.txt
```

Expected: > 0

- [ ] **Step 2: Overwrite with CM4-only config**

```bash
cat > overlay-boot/config.txt << 'EOF'
# /boot/config.txt for ClockworkPi uConsole CM4 — Void Linux
# Generated by Voiduconsole.

[all]
ignore_lcd=1
disable_overscan=1
max_framebuffers=2
dtparam=audio=on
dtoverlay=audremap,pins_12_13
dtoverlay=dwc2,dr_mode=host
dtparam=ant2
dtparam=spi=on

# GPIOs that hold the panel reset / backlight enable on at boot
gpio=10=ip,np
gpio=9=op,dh

# ClockworkPi shipped overlays
dtoverlay=devterm-pmu
dtoverlay=devterm-panel-uc
dtoverlay=devterm-misc

arm_64bit=1

# ----------------------------------------------------------------------------
# CM4 (BCM2711, 4 KiB pages, kernel8.img)
# ----------------------------------------------------------------------------
[pi4]
kernel=kernel8.img
dtoverlay=clockworkpi-uconsole
dtoverlay=vc4-kms-v3d-pi4,cma-384
enable_uart=1
over_voltage=2
arm_boost=1
EOF
```

- [ ] **Step 3: Verify CM5 section is gone**

```bash
grep 'pi5\|CM5\|kernel_2712' overlay-boot/config.txt
```

Expected: no output (exit 1 from grep is fine).

- [ ] **Step 4: Commit**

```bash
git add overlay-boot/config.txt
git commit -m "config: strip CM5 section from config.txt (CM4-only build)"
```

---

## Task 8: Add X11 display rotation config

**Files:**
- Create: `overlay-root/etc/X11/xorg.conf.d/99-uconsole-rotate.conf`

- [ ] **Step 1: Create the directory**

```bash
mkdir -p overlay-root/etc/X11/xorg.conf.d
```

- [ ] **Step 2: Write the xorg config**

```bash
cat > overlay-root/etc/X11/xorg.conf.d/99-uconsole-rotate.conf << 'EOF'
# Rotate the DSI-1 panel 90° clockwise so the portrait-mounted display
# appears landscape. Must be "right" — wlroots and X use opposite conventions.
Section "Monitor"
    Identifier "DSI-1"
    Option "Rotate" "right"
EndSection
EOF
```

- [ ] **Step 3: Verify the file exists**

```bash
cat overlay-root/etc/X11/xorg.conf.d/99-uconsole-rotate.conf
```

Expected: the xorg config above.

- [ ] **Step 4: Commit**

```bash
git add overlay-root/etc/X11/xorg.conf.d/99-uconsole-rotate.conf
git commit -m "feat: add X11 display rotation config for DSI-1 panel"
```

---

## Task 9: Fix `uconsole-4g` command names

**Files:**
- Modify: `overlay-root/usr/local/bin/uconsole-4g`

The script currently uses `enable`/`disable` but the README documents `on`/`off`. Fix the subcommand names and update the usage string.

- [ ] **Step 1: Verify the current command names**

```bash
grep 'enable\|disable' overlay-root/usr/local/bin/uconsole-4g
```

Expected: lines showing `enable)` and `disable)` in the case statement.

- [ ] **Step 2: Overwrite the script with corrected command names**

```bash
#!/bin/bash
# uconsole-4g: power-cycle the SIM7600G 4G expansion on uConsole CM4.
# Pure-libgpiod replacement for clockworkpi's wiringPi version.
#
# Pin map (BCM numbering on the CM4):
#   GPIO 24 = 4G module power-enable
#   GPIO 15 = 4G module reset/PWRKEY
set -euo pipefail
CHIP=gpiochip0
PWR_EN=24
PWRKEY=15

usage() { echo "usage: $0 {on|off|status}"; exit 1; }

ensure_gpioset() { command -v gpioset >/dev/null || { echo "install libgpiod"; exit 2; }; }

enable_4g() {
  echo ":: powering on 4G module..."
  gpioset --mode=exit "$CHIP" "$PWR_EN"=1
  gpioset --mode=time --sec=5 "$CHIP" "$PWRKEY"=1
  gpioset --mode=exit "$CHIP" "$PWRKEY"=0
  echo ":: waiting 13s for modem to enumerate..."
  sleep 13
  echo ":: done. Try:  mmcli -L"
}

disable_4g() {
  echo ":: powering off 4G module..."
  gpioset --mode=time --sec=3 "$CHIP" "$PWR_EN"=1
  gpioset --mode=exit "$CHIP" "$PWR_EN"=0
  sleep 20
  echo ":: done."
}

status_4g() {
  if command -v mmcli >/dev/null; then mmcli -L; fi
  ip -br addr | grep -E 'usb0|ppp0|wwan' || echo "(no 4G network interface up)"
}

[ "${1:-}" ] || usage
ensure_gpioset
case "$1" in
  on)     enable_4g ;;
  off)    disable_4g ;;
  status) status_4g ;;
  *) usage ;;
esac
```

- [ ] **Step 3: Verify the fix**

```bash
grep 'on)\|off)\|status)' overlay-root/usr/local/bin/uconsole-4g
```

Expected:
```
  on)     enable_4g ;;
  off)    disable_4g ;;
  status) status_4g ;;
```

- [ ] **Step 4: Commit**

```bash
git add overlay-root/usr/local/bin/uconsole-4g
git commit -m "fix: rename uconsole-4g subcommands to on/off/status"
```

---

## Task 10: Write `scripts/30-configure.sh`

**Files:**
- Create: `scripts/30-configure.sh`

This stage: applies `overlay-boot/config.txt`, patches `cmdline.txt` with the real PARTUUID, copies `overlay-root/` into the rootfs, sets hostname/locale/timezone, creates the user with a host-generated password hash, enables runit services.

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

log() { printf '\033[1;36m[30-configure]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

[ -f work/loop.dev ] || die "work/loop.dev missing — run prior stages first"
LOOP=$(cat work/loop.dev)

CHROOT() { sudo chroot work/rootfs /usr/bin/qemu-aarch64-static /bin/bash -c "$*"; }

# --- Boot partition ---
log "Writing config.txt..."
sudo cp overlay-boot/config.txt work/boot/config.txt

log "Patching cmdline.txt with PARTUUID..."
ROOT_PARTUUID=$(sudo blkid -s PARTUUID -o value "${LOOP}p2")
[ -n "$ROOT_PARTUUID" ] || die "Could not read PARTUUID from ${LOOP}p2"
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/30-configure.sh
```

- [ ] **Step 3: Syntax check**

```bash
bash -n scripts/30-configure.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 4: Commit**

```bash
git add scripts/30-configure.sh
git commit -m "feat: add 30-configure stage — boot config, overlays, user, services"
```

---

## Task 11: Write `scripts/40-finalise.sh`

**Files:**
- Create: `scripts/40-finalise.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. ./config.sh

log() { printf '\033[1;36m[40-finalise]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

[ -f work/loop.dev ] || die "work/loop.dev missing — nothing to finalise"
LOOP=$(cat work/loop.dev)

log "Unmounting partitions..."
sudo umount work/boot  || true
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
```

- [ ] **Step 2: Make executable**

```bash
chmod +x scripts/40-finalise.sh
```

- [ ] **Step 3: Syntax check**

```bash
bash -n scripts/40-finalise.sh && echo "syntax ok"
```

Expected: `syntax ok`

- [ ] **Step 4: Commit**

```bash
git add scripts/40-finalise.sh
git commit -m "feat: add 40-finalise stage — unmount, move img to deploy/"
```

---

## Task 12: Update `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Overwrite with updated content reflecting new approach**

```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A build system that patches the official Void Linux XFCE Raspberry Pi image for the ClockworkPi uConsole CM4 4G. It downloads the pre-built XFCE image, loop-mounts it, swaps in the ClockworkPi kernel, and applies hardware configuration. The artifact is a flashable `.img`; validation = boot on hardware.

## Building

```bash
./build.sh           # full build; prompts for sudo once
```

Build time: ~5–10 minutes (dominated by image decompress + kernel deb extract). Output: `deploy/voiduconsole-cm4-YYYYMMDD.img`.

**Cached state:**
- `downloads/` — XFCE img.xz + clockwork kernel deb; delete to re-fetch
- `work/<img>` — decompressed working image; delete to re-decompress
- `work/loop.dev` — active loop device path (written by stage 10, deleted by stage 40)

**If a stage fails mid-run, clean up before retrying:**
```bash
sudo umount work/boot work/rootfs 2>/dev/null || true
sudo losetup -d "$(cat work/loop.dev 2>/dev/null)" 2>/dev/null || true
rm -f work/loop.dev
# If the image is corrupted, also: rm work/*.img
./build.sh
```

No test suite. Validation = boot the `.img` on the uConsole.

## Architecture

`build.sh` sources `config.sh` (all tunables), then runs `scripts/00–40` sequentially against a loop-mounted working copy of the official Void XFCE RPi image.

| Stage | Script | What it does |
|-------|--------|-------------|
| 00 | `00-download.sh` | Fetch XFCE `.img.xz` + clockworkpi kernel deb into `downloads/` |
| 10 | `10-prepare.sh` | Decompress, expand to `IMG_SIZE_MB`, loop-mount both partitions |
| 20 | `20-swap-kernel.sh` | `ar x` kernel deb, replace `kernel8.img`/DTBs/overlays/modules, `depmod -a` |
| 30 | `30-configure.sh` | Apply `overlay-boot/` + `overlay-root/`, patch PARTUUID, set hostname/user/services |
| 40 | `40-finalise.sh` | Unmount, detach loop device, move `.img` to `deploy/` |

## Where to make changes

| Change | Where |
|--------|-------|
| Hostname / user / passwords / locale / timezone | `config.sh` |
| Image source URL or kernel deb URL | `config.sh` |
| Boot args (cmdline) | `overlay-boot/cmdline.txt` — keep `ROOTDEV` token |
| Boot overlays / display flags | `overlay-boot/config.txt` |
| Any rootfs file (configs, scripts) | Mirror target path under `overlay-root/` |
| Runit services to enable | `services` loop in `scripts/30-configure.sh` |

## Shell script conventions

All scripts use `#!/bin/bash` + `set -euo pipefail`. Logging uses `log()` (cyan) / `die()` (red). `CHROOT()` in stage scripts is `sudo chroot work/rootfs /usr/bin/qemu-aarch64-static /bin/bash -c "$*"` — only needed for depmod and user setup.

## Critical gotchas

- **`chpasswd` under qemu produces broken `$6$` hashes.** Stage 30 generates password hashes on the host with `openssl passwd -6` and applies via `usermod -p`. Never use `chpasswd` inside the chroot.
- **Display rotation uses opposite conventions.** Kernel TTY: `fbcon=rotate:1` + `panel_orientation=right_side_up`. X11/LightDM: `Option "Rotate" "right"` in `overlay-root/etc/X11/xorg.conf.d/99-uconsole-rotate.conf`. These must disagree — do not normalise them.
- **QMI is intentionally blacklisted.** ModemManager talks AT on `/dev/ttyUSB2/3` for SIM7600G voice. Do not re-enable `qmi_wwan` / `cdc_wdm`.
- **`uconsole-4g` subcommands are `on`/`off`/`status`** (not `enable`/`disable`).

## Modem tool

```bash
uconsole-4g on      # GPIO power sequence, waits 13s for /dev/ttyUSB*
uconsole-4g status  # mmcli -L + network interface check
uconsole-4g off     # clean shutdown, waits 20s
```

GPIO access uses `libgpiod` (`gpioset`). The sudoers rule at `overlay-root/etc/sudoers.d/uconsole-4g` allows NOPASSWD execution.
```

- [ ] **Step 2: Verify the file looks right**

```bash
grep -c 'stage\|CHROOT\|gotcha' CLAUDE.md
```

Expected: > 0 for each (file has the key sections).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for XFCE base image approach"
```

---

## Task 13: End-to-end build verification

This task validates the complete pipeline without running on hardware.

- [ ] **Step 1: Verify all new scripts are present and executable**

```bash
ls -la scripts/
```

Expected: `00-download.sh`, `10-prepare.sh`, `20-swap-kernel.sh`, `30-configure.sh`, `40-finalise.sh` — all executable (`-rwxrwxr-x` or similar). None of the old scripts (`10-prepare-rootfs.sh`, `20-install-packages.sh`, etc.) present.

- [ ] **Step 2: Syntax-check all scripts**

```bash
for f in build.sh scripts/*.sh; do
    bash -n "$f" && echo "ok: $f" || echo "FAIL: $f"
done
```

Expected: `ok: <path>` for every file, no FAILs.

- [ ] **Step 3: Verify overlay-root tree is correct**

```bash
find overlay-root -type f | sort
```

Expected:
```
overlay-root/etc/X11/xorg.conf.d/99-uconsole-rotate.conf
overlay-root/etc/modprobe.d/blacklist-qmi.conf
overlay-root/etc/polkit-1/rules.d/50-uconsole-nm-mm.rules
overlay-root/etc/sudoers.d/10-wheel
overlay-root/etc/sudoers.d/uconsole-4g
overlay-root/etc/udev/rules.d/99-uconsole.rules
overlay-root/usr/local/bin/uconsole-4g
```

- [ ] **Step 4: Run a dry-run download check (no actual download)**

```bash
wget -q --spider "$(grep VOID_XFCE_IMG_URL config.sh | cut -d'"' -f2)" \
    && echo "XFCE image URL reachable" \
    || echo "WARNING: XFCE image URL not reachable — update config.sh if this is not a network issue"
```

Expected: `XFCE image URL reachable`. If not, note the URL needs updating but the build logic is still correct.

- [ ] **Step 5: Final commit to close out the task**

```bash
git log --oneline -10
```

Confirm all tasks have been committed with sensible messages.

---

## Cleanup reference (if build fails mid-run)

```bash
sudo umount work/boot work/rootfs 2>/dev/null || true
sudo losetup -d "$(cat work/loop.dev 2>/dev/null)" 2>/dev/null || true
rm -f work/loop.dev
```

If root partition expand or depmod fails and the image is in an unknown state, also delete `work/*.img` and let stage 10 re-decompress from the cached `.img.xz`.
