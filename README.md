# Voiduconsole

A build system that patches the official **Void Linux XFCE Raspberry Pi image**
for the **ClockworkPi uConsole CM4 4G**. It downloads the pre-built XFCE image,
loop-mounts it, swaps in the ClockworkPi kernel, and applies uConsole-specific
hardware configuration. The artifact is a ready-to-flash `.img`.

---

## Table of contents

1. [What you get](#what-you-get)
2. [Hardware requirements](#hardware-requirements)
3. [Host build prerequisites](#host-build-prerequisites)
4. [Building the image](#building-the-image)
5. [Flashing the SD card](#flashing-the-sd-card)
6. [First boot](#first-boot)
7. [Default credentials](#default-credentials)
8. [Using the 4G modem](#using-the-4g-modem)
9. [Display rotation explained](#display-rotation-explained)
10. [Project layout](#project-layout)
11. [What the build does, stage by stage](#what-the-build-does-stage-by-stage)
12. [Customising the image](#customising-the-image)
13. [Troubleshooting](#troubleshooting)
14. [Known limitations](#known-limitations)
15. [Credits](#credits)
16. [License](#license)

---

## What you get

A single `.img` file containing:

| Layer       | Software |
|-------------|----------|
| Base        | Official Void Linux XFCE aarch64 image (glibc, runit, XFCE desktop) |
| Kernel      | ClockworkPi CM4 kernel (`kernel8.img`, DTBs, `clockworkpi-uconsole` overlay) |
| Desktop     | XFCE with LightDM autologin, display rotation applied |
| Modem       | ModemManager + AT interface on `/dev/ttyUSB2/3` (QMI blacklisted) |
| Custom tool | `uconsole-4g` — GPIO power sequence for the SIM7600G modem |
| Fonts       | Extra TTF fonts for better rendering |

---

## Hardware requirements

- ClockworkPi **uConsole 4G** with a **Raspberry Pi CM4** compute module
- SIMCom **SIM7600G** modem
- microSD card ≥ 8 GiB (16 GiB+ recommended)
- A Linux x86_64 host with ≥ 8 GiB free disk

---

## Host build prerequisites

On the host you need `qemu-aarch64-static`, `binutils` (`ar`), standard shell
utilities, and loop-device support.

### Void Linux host

```bash
sudo xbps-install -Sy git curl wget xz tar rsync openssl parted \
                     dosfstools e2fsprogs qemu-user-static binutils util-linux
```

### Debian / Ubuntu host

```bash
sudo apt install -y git curl wget xz-utils rsync openssl parted dosfstools \
                    e2fsprogs qemu-user-static binfmt-support binutils util-linux
```

### Arch host

```bash
sudo pacman -S --needed git curl wget xz rsync openssl parted dosfstools \
                        e2fsprogs qemu-user-static binfmt-support binutils util-linux
```

---

## Building the image

```bash
git clone https://github.com/kaleaditya28897-linux/Voiduconsole.git
cd Voiduconsole
./build.sh
```

The script will prompt for `sudo` once (needed for loop devices, mount, chroot).

**Build time: ~5–10 minutes** (dominated by image decompress + kernel deb extract).

Output: `deploy/voiduconsole-cm4-YYYYMMDD.img`

### Cached state

- `downloads/` — XFCE `.img.xz` + ClockworkPi kernel deb; delete to re-fetch
- `work/<img>` — decompressed working image; delete to re-decompress
- `work/loop.dev` — active loop device path (written by stage 10, deleted by stage 40)

### Recovery from a failed run

If a stage fails mid-run, clean up before retrying:

```bash
sudo umount work/boot work/rootfs 2>/dev/null || true
sudo losetup -d "$(cat work/loop.dev 2>/dev/null)" 2>/dev/null || true
rm -f work/loop.dev
# If the working image is corrupted:
# rm work/*.img
./build.sh
```

---

## Flashing the SD card

Identify the SD device (**double-check — wrong device = data loss**):

```bash
lsblk
```

Say your card is `/dev/sdX`:

```bash
sudo umount /dev/sdX* 2>/dev/null
sudo dd if=deploy/voiduconsole-cm4-*.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Optionally expand the root partition to fill the card:

```bash
sudo parted -s /dev/sdX resizepart 2 100%
sudo e2fsck -fy /dev/sdX2
sudo resize2fs /dev/sdX2
sync
sudo eject /dev/sdX
```

Or do it from the running uConsole after first boot:

```bash
sudo growpart /dev/mmcblk0 2
sudo resize2fs /dev/mmcblk0p2
```

---

## First boot

1. Insert the SD into the uConsole, power on.
2. The kernel TTY will appear right-side-up (`fbcon=rotate:1 video=DSI-1:panel_orientation=right_side_up`).
3. LightDM autologins to an XFCE session.

---

## Default credentials

| User   | Password    |
|--------|-------------|
| `root` | `voidlinux` |
| `anon` | `voidlinux` |

Change immediately on first login:

```bash
passwd            # change anon's password
sudo passwd root  # change root's password
```

---

## Using the 4G modem

The SIM7600G requires a GPIO power sequence before USB enumeration.

```bash
uconsole-4g on      # PWR_EN high, pulse PWRKEY 5s, wait 13s for /dev/ttyUSB*
uconsole-4g status  # mmcli -L + network interface check
uconsole-4g off     # clean shutdown, waits 20s
```

After `on`, you should see:

```
/dev/ttyUSB0  diagnostics
/dev/ttyUSB1  GNSS / NMEA
/dev/ttyUSB2  AT command port (control)
/dev/ttyUSB3  AT command port (data / voice)
```

QMI (`qmi_wwan` / `cdc_wdm`) is intentionally blacklisted — ModemManager talks
AT on `/dev/ttyUSB2/3` for voice call support.

### Connecting to mobile data

Via NetworkManager:

```bash
nmcli c add type gsm ifname '*' con-name 4g apn <YOUR_APN>
nmcli c up 4g
```

---

## Display rotation explained

The uConsole has a portrait-mounted panel. Kernel and X11 use **opposite** rotation conventions — do not normalise them:

| Subsystem        | Setting |
|------------------|---------|
| Kernel TTY       | `fbcon=rotate:1 video=DSI-1:panel_orientation=right_side_up` (in `cmdline.txt`) |
| X11 / LightDM    | `Option "Rotate" "right"` in `/etc/X11/xorg.conf.d/99-uconsole-rotate.conf` |

---

## Project layout

```
Voiduconsole/
├── build.sh                    # orchestrator — runs stages 00–40 in order
├── config.sh                   # all tunables (URLs, image size, hostname, credentials)
├── scripts/
│   ├── 00-download.sh          # fetch XFCE .img.xz + ClockworkPi kernel deb
│   ├── 10-prepare.sh           # decompress, expand, loop-mount both partitions
│   ├── 20-swap-kernel.sh       # install CM4 kernel, DTBs, overlays, modules; depmod
│   ├── 30-configure.sh         # overlays, PARTUUID patch, hostname, user, services
│   └── 40-finalise.sh          # unmount, detach loop, move .img to deploy/
├── overlay-boot/               # files copied verbatim to the FAT boot partition
│   ├── config.txt              # uConsole-specific (dtoverlay=clockworkpi-uconsole)
│   └── cmdline.txt             # fbcon=rotate:1 panel_orientation=right_side_up; ROOTDEV token
└── overlay-root/               # files copied verbatim into the rootfs
    └── etc/
        ├── X11/xorg.conf.d/99-uconsole-rotate.conf   # X11 display rotation
        ├── modprobe.d/blacklist-qmi.conf              # force AT over QMI for voice
        ├── sudoers.d/uconsole-4g                      # NOPASSWD for modem tool
        └── udev/rules.d/99-uconsole-kbd.rules         # keyboard udev rule
```

---

## What the build does, stage by stage

| Stage | Script | What it does |
|-------|--------|--------------|
| 00 | `00-download.sh` | Fetch XFCE `.img.xz` + ClockworkPi kernel deb into `downloads/`; skip if already present |
| 10 | `10-prepare.sh` | Decompress the image, expand to `IMG_SIZE_MB`, loop-mount both partitions (`work/boot`, `work/rootfs`); write loop device path to `work/loop.dev` |
| 20 | `20-swap-kernel.sh` | `ar x` kernel deb; replace `kernel8.img`, DTBs, overlays, and kernel modules; run `depmod -a` inside the chroot via `qemu-aarch64-static` |
| 30 | `30-configure.sh` | Copy `overlay-boot/` and `overlay-root/` into the mounted image; patch `ROOTDEV` token in `cmdline.txt` with real PARTUUID; set hostname, user password (via host-generated `openssl passwd -6` hash + `usermod -p`), and enable runit services |
| 40 | `40-finalise.sh` | Unmount partitions, detach loop device, move finished `.img` to `deploy/` |

### Key gotchas baked into the build

- **`chpasswd` under qemu produces broken `$6$` hashes.** Stage 30 generates
  password hashes on the host with `openssl passwd -6` and applies them via
  `usermod -p`. Never use `chpasswd` inside the chroot.
- **Display rotation uses opposite conventions** between the kernel TTY and
  X11/LightDM. The two settings must disagree — do not normalise them.

---

## Customising the image

| Change | Where |
|--------|-------|
| Hostname / user / passwords / locale / timezone | `config.sh` |
| Image source URL or kernel deb URL | `config.sh` |
| Boot args (cmdline) | `overlay-boot/cmdline.txt` — keep the `ROOTDEV` token |
| Boot overlays / display flags | `overlay-boot/config.txt` |
| Any rootfs file (configs, scripts, udev rules) | Mirror target path under `overlay-root/` |
| Runit services to enable | `services` loop in `scripts/30-configure.sh` |

After any change, re-run `./build.sh`. Cached downloads and the decompressed
image are reused automatically.

---

## Troubleshooting

### 4G modem doesn't enumerate

```bash
uconsole-4g status
dmesg | grep -i 'ttyUSB\|option'
uconsole-4g off && sleep 3 && uconsole-4g on
```

### XFCE doesn't start / LightDM fails

```bash
# Switch to TTY2 (Ctrl+Alt+F2), log in as anon
sudo sv status lightdm
cat /var/log/lightdm/lightdm.log
```

### Display rotation wrong

Edit `/etc/X11/xorg.conf.d/99-uconsole-rotate.conf` and toggle the `Rotate`
option between `"left"`, `"right"`, `"inverted"`.

### Password doesn't work

From a root TTY:

```bash
passwd anon
passwd root
```

---

## Known limitations

- **Voice call audio** routing over PCM is not configured by default.
- **CM5** is not supported — this build targets CM4 only (`kernel8.img`).
- The ClockworkPi kernel carries out-of-tree patches; it is not mainline.

---

## Credits

- **ClockworkPi** — uConsole hardware, kernel, and overlays
- **Void Linux** — aarch64 XFCE image and excellent runit setup
- **ak-rex** — `clockworkpi-kernel` deb

---

## License

Build scripts and overlays in this repository are released under the **MIT License**.

Redistributed payloads keep their upstream licenses:
- Void Linux image — see <https://github.com/void-linux/void-packages>
- ClockworkPi kernel deb — see <https://github.com/clockworkpi/apt>
