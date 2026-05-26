# Design: XFCE-base image rebuild for uConsole CM4 4G

**Date:** 2026-05-26
**Status:** Approved

## Background

The original approach built a Void Linux image entirely from scratch: extracted a raw `PLATFORMFS` tarball, ran `xbps-install` for ~80 packages under `qemu-user-static`, and wired everything up manually (greetd, labwc, Waybar, custom Wayland tools). This produced reliability problems: long qemu-user package installs, setuid bits stripped by qemu, broken `chpasswd` hashes, and Wayland display rotation complexity.

The new approach starts from the official Void Linux XFCE Raspberry Pi image, which is already a fully bootable, natively-built system. The build script just patches in the ClockworkPi hardware layer on top.

## Scope

- **Target hardware:** ClockworkPi uConsole with Raspberry Pi **CM4** + SIM7600G 4G modem only (not CM5)
- **Desktop:** XFCE (X11) as shipped by the official Void image — no changes to the DE itself
- **Custom tools:** `uconsole-4g` only (GPIO modem power management via libgpiod)
- **Modem GUI tools:** deferred — will evaluate modem-manager-gui and gnome-calls separately

## Build pipeline

Five stages, run sequentially by `build.sh` which sources `config.sh`:

### 00 — Download
Fetch into `downloads/` (cached; delete to re-fetch):
- `void-rpi-aarch64-XFCE-YYYYMMDD.img.xz` from `VOID_XFCE_IMG_URL`
- `clockworkpi-kernel_6.12.87-v8-16k+_arm64.deb` from `CLOCKWORK_KERNEL_DEB_URL`

**Risk:** Void may not publish an XFCE `.img.xz` for aarch64/RPi (they definitely publish the `PLATFORMFS` tarball and may publish a base image). The script will verify the URL with a `wget --spider` check and fail-fast with a clear message. Fallback if needed: use the base RPi `.img.xz` and add one `xbps-install xfce4 xfce4-goodies lightdm lightdm-gtk3-greeter` step in stage 20.

### 10 — Prepare
1. Decompress: `xz -d downloads/*.img.xz` into `work/`
2. Expand file: `truncate -s ${IMG_SIZE_MB}M work/<img>`
3. Attach loop device: `losetup -P /dev/loopX work/<img>`
4. Resize partition: `parted /dev/loopX resizepart 2 100%`
5. Expand filesystem: `e2fsck -fy /dev/loopXp2` then `resize2fs /dev/loopXp2`
6. Mount: `work/boot` ← boot partition, `work/rootfs` ← root partition

### 20 — Swap kernel
1. `ar x` the clockworkpi deb into `work/kerneldeb/`
2. Extract `data.tar.xz`
3. Copy into the mounted image:
   - `kernel8.img` → `work/boot/kernel8.img` (CM4 kernel)
   - All `*.dtb` → `work/boot/`
   - `overlays/*.dtbo` → `work/boot/overlays/`
   - Module tree (`lib/modules/6.12.87-v8+/`) → `work/rootfs/lib/modules/`
4. `depmod -a 6.12.87-v8+` inside the chroot (via qemu-user-static)

If the XFCE fallback path is active, `xbps-install` runs here before the kernel swap.

### 30 — Configure
All changes applied by writing files directly into the mounted image (no chroot needed for most of these):

**Boot partition (`work/boot/`):**
- `config.txt` — rewritten: `dtoverlay=clockworkpi-uconsole`, `[pi4]` section, display/audio flags
- `cmdline.txt` — patched: add `fbcon=rotate:1 video=DSI-1:panel_orientation=right_side_up`; `ROOTDEV` replaced with actual PARTUUID via `blkid`

**Root partition (`work/rootfs/`) — via `cp -af overlay-root/* work/rootfs/`:**
- `etc/X11/xorg.conf.d/99-uconsole-rotate.conf` — X11 display rotation (`Option "Rotate" "right"` on DSI-1)
- `etc/modprobe.d/blacklist-qmi.conf` — blacklist `qmi_wwan` + `cdc_wdm`
- `etc/udev/rules.d/99-uconsole.rules` — `ttyUSB*` → `dialout`, `gpiochip*` → `wheel`
- `etc/sudoers.d/10-wheel` — wheel sudo
- `etc/sudoers.d/uconsole-4g` — NOPASSWD for uconsole-4g
- `etc/polkit-1/rules.d/50-uconsole-nm-mm.rules` — wheel manages NM/MM without prompt
- `usr/local/bin/uconsole-4g` — GPIO modem power tool

**Chroot steps** (still need qemu for these):
- Set hostname
- Configure locale + timezone
- Create/configure user `anon` with password set via `openssl passwd -6` + `usermod -p` (same host-hash approach — avoids qemu chpasswd bug)
- Enable runit services: `dbus elogind polkitd NetworkManager ModemManager lightdm`

### 40 — Finalise
1. Unmount `work/rootfs` and `work/boot`
2. Detach loop device (`losetup -d`)
3. Move `work/<img>` → `deploy/voiduconsole-cm4-YYYYMMDD.img`

## Display rotation

The DSI-1 panel is portrait-mounted. Two layers must disagree (same physical reality, different coordinate conventions):

| Layer | Setting |
|-------|---------|
| Kernel TTY / framebuffer | `fbcon=rotate:1 video=DSI-1:panel_orientation=right_side_up` in `cmdline.txt` |
| X11 (XFCE + LightDM) | `Option "Rotate" "right"` in `/etc/X11/xorg.conf.d/99-uconsole-rotate.conf` |

LightDM inherits the same X server, so the greeter is automatically rotated correctly. No separate greeter config needed.

## Modem support

The SIM7600G is not USB-powered — it needs the GPIO power sequence before USB enumeration:

```bash
uconsole-4g on      # PWR_EN high, pulse PWRKEY 5s, wait for /dev/ttyUSB*
uconsole-4g status
uconsole-4g off
```

QMI modules are blacklisted so ModemManager uses AT commands on `/dev/ttyUSB2/3` (required for voice). ModemManager is already present in the XFCE image.

## `overlay-root/` contents (final)

```
overlay-root/
├── etc/
│   ├── X11/xorg.conf.d/99-uconsole-rotate.conf
│   ├── modprobe.d/blacklist-qmi.conf
│   ├── polkit-1/rules.d/50-uconsole-nm-mm.rules
│   ├── sudoers.d/10-wheel
│   ├── sudoers.d/uconsole-4g
│   └── udev/rules.d/99-uconsole.rules
└── usr/
    └── local/bin/uconsole-4g
```

Everything Wayland-specific (labwc, waybar, fuzzel, foot, mako, wob, greetd, skel dotfiles, all other uconsole-* tools) is removed.

## `config.sh` variables

```bash
VOID_XFCE_IMG_URL="https://repo-default.voidlinux.org/live/current/void-rpi-aarch64-XFCE-20250202.img.xz"
CLOCKWORK_KERNEL_DEB_URL="https://github.com/ak-rex/ClockworkPi-apt/raw/main/debian/pool/main/c/clockworkpi-kernel/clockworkpi-kernel_6.12.87-v8-16k+_arm64.deb"
IMG_SIZE_MB=6144
HOSTNAME="uconsole"
USERNAME="anon"
USERPASS="voidlinux"
ROOTPASS="voidlinux"
TIMEZONE="Asia/Kolkata"
LOCALE="en_IN.UTF-8"
```

No `PACKAGES_*` variables.

## What disappears vs old approach

| Old | New |
|-----|-----|
| 7 stages | 5 stages |
| `xbps-install` ~80 packages under qemu | Not needed — XFCE already installed |
| setuid fixup (`chmod 4755 sudo` etc.) | Not needed — packages installed natively |
| `openssl passwd` + `usermod -p` workaround | Still needed (chpasswd under qemu still broken) |
| greetd + ReGreet | LightDM (ships with XFCE image) |
| labwc + Wayland stack | XFCE + X11 |
| 8 custom uconsole-* tools | 1 tool (`uconsole-4g`) |
| Display rotation: wlr-randr + outputs.xml | Display rotation: single xorg.conf snippet |

## Known risks

1. **XFCE RPi image availability** — handled with fail-fast check + documented fallback
2. **Default user in official image** — Void's RPi images may ship a default `anon/voidlinux` user or require first-boot setup; stage 30 will create/configure the user explicitly either way
3. **ModemManager version** — if the XFCE image ships an older MM, AT-based voice may need testing; uconsole-4g is independent of MM version
