# Voiduconsole

A complete, reproducible builder that produces a **ready-to-flash glibc Void
Linux image** for the **ClockworkPi uConsole CM4 (4G)** with a fully working
Wayland desktop, 4G modem stack, and replacement GUI tools for the bits the
Linux ecosystem doesn't package for Void.

The build runs on any x86_64 Linux host (developed on Void Linux) and uses
`qemu-user-static` to chroot into the aarch64 rootfs while installing packages.

---

## Table of contents

1. [What you get](#what-you-get)
2. [Why this is necessary](#why-this-is-necessary)
3. [Hardware requirements](#hardware-requirements)
4. [Host build prerequisites](#host-build-prerequisites)
5. [Building the image](#building-the-image)
6. [Flashing the SD card](#flashing-the-sd-card)
7. [First boot](#first-boot)
8. [Default credentials](#default-credentials)
9. [Using the 4G modem](#using-the-4g-modem)
10. [Making and receiving calls / SMS](#making-and-receiving-calls--sms)
11. [Display rotation explained](#display-rotation-explained)
12. [Project layout](#project-layout)
13. [What the build does, stage by stage](#what-the-build-does-stage-by-stage)
14. [Customising the image](#customising-the-image)
15. [Troubleshooting](#troubleshooting)
16. [Known limitations](#known-limitations)
17. [Roadmap / ideas](#roadmap--ideas)
18. [Credits](#credits)
19. [License](#license)

---

## What you get

A single `.img` file (~6 GiB sparse, ~3.8 GiB actual data) containing:

| Layer            | Software |
|------------------|----------|
| Base             | Void Linux aarch64 **glibc**, runit, xbps, elogind, seatd, polkit, dbus |
| Kernel           | ClockworkPi 5.10.17-v8+ deb with `devterm-panel-uc`, `devterm-pmu`, `devterm-misc` overlays |
| Compositor       | **labwc** (Wayland) + Waybar + wofi + foot + mako |
| Login            | **greetd + ReGreet** on the rotated DSI-1 panel |
| Audio            | PipeWire + WirePlumber + alsa-pipewire + `pavucontrol` |
| Network          | NetworkManager + `nm-applet` (Wi-Fi *and* GSM in a single tray icon) |
| Modem            | ModemManager + libmbim + libqmi + `mobile-broadband-provider-info` + `usb-modeswitch` + `socat` + `ppp` |
| File manager     | Thunar |
| Browser          | Firefox-ESR (Wayland-enabled) |
| Misc GUIs        | gnome-disk-utility, gnome-system-monitor, galculator, mpv, imv, gnome-text-editor |
| Custom tools     | `uconsole-4g`, `uconsole-call`, `uconsole-brightness`, `labwc-greeter` |

The custom tools live under `/usr/local/bin/` and have desktop entries so they
also show up in wofi.

---

## Why this is necessary

The official ClockworkPi OS uses a heavily-modified Raspberry Pi OS (Debian)
with GNOME / KDE. Several of the apps the user normally relies on for the
uConsole (`gnome-calls` for voice calls over the SIM7600G; `modem-manager-gui`
as a graphical MM frontend) **are not packaged on Void Linux**. This builder:

* uses Clockwork's **binary kernel** (5.10) because the panel, keyboard MCU,
  fan controller, power-management IC (AXP209), and audio amp drivers are not
  in mainline,
* drops in a Wayland desktop that runs well on the CM4 (labwc + GTK4 apps),
* ships **`uconsole-4g`** (a `libgpiod` reimplementation of Clockwork's
  wiringPi power script) and **`uconsole-call`** (an AT-over-`socat` TUI) so
  you can power the modem, place calls, send SMS, and inspect the modem
  without `gnome-calls` / `modem-manager-gui`.

---

## Hardware requirements

* ClockworkPi **uConsole CM4 4G** (with SIMCom **SIM7600G** modem)
* microSD card, ≥ 8 GiB (16 GiB+ recommended)
* SIM card with a known APN (or post-paid auto-config)
* A Linux x86_64 host with ≥ 8 GiB free disk (for downloads + rootfs + image)

The build has only been validated on the CM4 4G variant. The Pi 5 variant and
the A04/A06 variants will need different kernel debs in `config.sh`.

---

## Host build prerequisites

On the host you need a recent kernel with binfmt_misc and the following tools.

### Void Linux host

```bash
sudo xbps-install -Sy git curl wget xz tar rsync openssl parted dosfstools e2fsprogs \
                     qemu qemu-user-static binutils util-linux
```

### Debian / Ubuntu host

```bash
sudo apt install -y git curl wget xz-utils rsync openssl parted dosfstools e2fsprogs \
                    qemu-user-static binfmt-support binutils util-linux
```

### Arch host

```bash
sudo pacman -S --needed git curl wget xz rsync openssl parted dosfstools e2fsprogs \
                       qemu-user-static binfmt-support binutils util-linux
```

### Register the aarch64 binfmt handler

On systems without `systemd-binfmt`, register once per boot:

```bash
sudo sh -c 'echo ":qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\xfc\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:OCF" > /proc/sys/fs/binfmt_misc/register'
```

Verify:

```bash
cat /proc/sys/fs/binfmt_misc/qemu-aarch64
```

On distros with `binfmt-support` (Debian/Ubuntu/Arch) this is usually
automatic via systemd.

---

## Building the image

```bash
git clone https://github.com/kaleaditya28897-linux/Voiduconsole.git
cd Voiduconsole
./build.sh
```

The script needs `sudo` for: bind-mounting `/proc /sys /dev /dev/pts` into the
chroot, chrooting, creating loop devices, formatting partitions, and rsyncing
the rootfs into the image. It will prompt for your password once.

Typical run time: **20–40 minutes**, dominated by package downloads and
firefox-esr unpacking under qemu-user. Output lands in `deploy/`:

```
deploy/voiduconsole-cm4-YYYYMMDD.img
```

### Re-running

Cached files are kept under `downloads/` (Void platformfs tarball + Clockwork
kernel deb). A re-run reuses them; delete the directory to refetch.

Stale chroot state under `work/rootfs/` is reused too. If a previous run died
mid-package-install, wipe and start fresh:

```bash
sudo umount -lR work/rootfs/{proc,sys,dev/pts,dev} 2>/dev/null
sudo rm -rf work/
./build.sh
```

---

## Flashing the SD card

Identify the SD device (**double-check this** — wrong device = data loss):

```bash
lsblk
```

Say your card is `/dev/sdX`:

```bash
sudo umount /dev/sdX* 2>/dev/null
sudo dd if=deploy/voiduconsole-cm4-*.img of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Optionally expand the root partition to fill the card (the image is 6 GiB; on
a 32/64 GiB card this gives you the rest):

```bash
sudo parted -s /dev/sdX resizepart 2 100%
sudo e2fsck -fy /dev/sdX2
sudo resize2fs /dev/sdX2
sync
sudo eject /dev/sdX
```

If you skip the resize you can do it from the running uConsole instead:

```bash
sudo growpart /dev/mmcblk0 2
sudo resize2fs /dev/mmcblk0p2
```

---

## First boot

1. Insert the SD into the uConsole, power on.
2. The **kernel TTY** will appear right-side-up (cmdline has
   `fbcon=rotate:1 video=DSI-1:panel_orientation=right_side_up`).
3. `greetd` starts a labwc session as the system user `_greeter`, which then
   `exec`s **ReGreet** on the rotated panel.
4. Log in as **`aditya`** with password **`adi28897`** — your labwc session
   starts (Waybar at the top, swaybg dark background, mako notifications,
   `nm-applet` tray icon).

### Keyboard / WM shortcuts (labwc default `rc.xml`)

| Shortcut       | Action                                  |
|----------------|-----------------------------------------|
| Super + Enter  | Open `foot` terminal                    |
| Super + D      | Launcher (`wofi --show drun`)           |
| Super + Q      | Close focused window                    |
| Super + Shift + E | Logout (kill labwc)                  |
| PrtSc          | `grim` screenshot to `~/Pictures/`      |
| Vol Up / Down  | `pamixer` ±5%                           |
| Brightness +/− | `uconsole-brightness +/-`               |

---

## Default credentials

| User       | Password   |
|------------|------------|
| `root`     | `adi28897` |
| `aditya`   | `adi28897` |

Change immediately on first login:

```bash
passwd                 # change aditya's password
sudo passwd root       # change root's password
```

`aditya` is in `wheel,audio,video,input,plugdev,network,storage,users,dialout`.
`sudo` is wired up for `wheel`.

---

## Using the 4G modem

The SIM7600G is wired to the CM4's GPIO header, not USB-power. It needs an
explicit power sequence before USB enumeration happens.

```bash
uconsole-4g on      # PWR_EN high, pulse PWRKEY 5s, wait 13s for /dev/ttyUSB*
uconsole-4g status  # show GPIO state + ttyUSB* devices
uconsole-4g off     # hold PWR_EN low, wait 20s for clean shutdown
```

After `on`, you should see four serial devices:

```
/dev/ttyUSB0  diagnostics
/dev/ttyUSB1  GNSS / NMEA
/dev/ttyUSB2  AT command port (control)
/dev/ttyUSB3  AT command port (data / voice)
```

The QMI net interface is intentionally **blacklisted** (`qmi_wwan` +
`cdc_wdm`, see `/etc/modprobe.d/blacklist-qmi.conf`). ModemManager talks AT
on `/dev/ttyUSB2/3` instead — required for voice calls.

### Connecting

Via GUI: click the `nm-applet` icon in the Waybar tray → *Mobile Broadband* →
*Add* → pick your country/carrier → *Apply*.

Via CLI:

```bash
nmcli c add type gsm ifname '*' con-name 4g apn <YOUR_APN>
nmcli c up 4g
nmcli device status        # should show ppp0 or wwan0 connected
```

---

## Making and receiving calls / SMS

`uconsole-call` is a small TUI that opens a `socat` PTY to `/dev/ttyUSB3`
(falls back to `ttyUSB2`) and sends the appropriate AT commands.

```bash
uconsole-call signal                    # AT+CSQ -- signal strength
uconsole-call network                   # AT+COPS? / AT+CREG?
uconsole-call sim                       # AT+CPIN? AT+CIMI

uconsole-call call +911234567890        # ATD<number>;
uconsole-call answer                    # ATA
uconsole-call hangup                    # ATH

uconsole-call sms +911234567890 "hi"    # AT+CMGS=...
```

Voice audio: the SIM7600G routes call audio over **PCM** to the CM4. The
PipeWire stack already loads `bluez-mediakeys` and the AXP-codec card; for
voice routing you may need to wire `pw-link` between the modem PCM source and
your speaker sink. (This is a known rough edge — see *Known limitations*.)

---

## Display rotation explained

The uConsole has a **portrait-mounted** 1280×480 panel on `DSI-1`. The
kernel framebuffer and wlroots use **opposite rotation conventions** for it:

| Subsystem        | Setting                                                       |
|------------------|---------------------------------------------------------------|
| Kernel TTY       | `fbcon=rotate:1 video=DSI-1:panel_orientation=right_side_up`  |
| labwc / sway / hyprland | `<transform>270</transform>` / `wlr-randr --transform 270` |
| Greeter session  | same — set in `/var/lib/_greeter/.config/labwc/outputs.xml`   |

All four files are written by the build (or you can edit them after first
boot under `~/.config/labwc/`).

---

## Project layout

```
Voiduconsole/
├── build.sh                       # top-level orchestrator
├── config.sh                      # all tunables (sizes, URLs, package lists, creds)
├── scripts/
│   ├── 00-download.sh             # fetch platformfs tarball + clockwork kernel deb
│   ├── 10-prepare-rootfs.sh       # extract rootfs, drop qemu binary + resolv.conf
│   ├── 20-install-packages.sh     # xbps-install -Suy + install all listed packages
│   ├── 30-install-kernel.sh       # ar-extract the deb, copy kernel/dtb/overlays/modules
│   ├── 40-apply-overlay.sh        # cp -af overlay-boot/* overlay-root/* into rootfs
│   ├── 50-configure-system.sh     # hostname/locale/tz/users/services/greetd/fstab
│   └── 90-pack-image.sh           # partition, mkfs, rsync rootfs, patch PARTUUID
├── overlay-boot/                  # files copied to /boot on the SD
│   ├── config.txt                 # uConsole-specific (dtoverlay=clockworkpi-uconsole)
│   └── cmdline.txt                # fbcon=rotate:1 panel_orientation=right_side_up
├── overlay-root/                  # files copied into the rootfs
│   ├── etc/
│   │   ├── greetd/config.toml             # greetd: runs labwc as _greeter -> regreet
│   │   ├── modprobe.d/blacklist-qmi.conf  # force AT over QMI for voice
│   │   ├── polkit-1/rules.d/              # allow wheel to manage NM/MM without prompt
│   │   ├── skel/.config/{labwc,waybar,foot}/  # default desktop config
│   │   ├── sudoers.d/                     # wheel + uconsole-4g NOPASSWD
│   │   └── udev/rules.d/99-uconsole.rules # ttyUSB -> dialout, gpiochip -> wheel
│   └── usr/
│       ├── local/bin/{uconsole-4g,uconsole-call,uconsole-brightness,labwc-greeter}
│       └── share/applications/{uconsole-4g,uconsole-call}.desktop
└── xbps-src-templates/
    └── modem-manager-gui/template # optional: build the real GTK GUI later
```

---

## What the build does, stage by stage

1. **00 download** — `void-platformfs.tar.xz` (Void aarch64 base) and
   `uconsole-kernel-cm4-rpi.deb` (ClockworkPi 5.10 kernel) into `downloads/`.
2. **10 prepare-rootfs** — extract platformfs into `work/rootfs/`, drop in
   `/usr/bin/qemu-aarch64-static` and `/etc/resolv.conf` so the chroot can
   resolve DNS.
3. **20 install-packages** — bind `/proc /sys /dev /dev/pts`, `xbps-install -Suy`,
   add the `nonfree` repo (firmware), then install every package listed in
   `config.sh`. Already-installed packages are filtered out beforehand
   because `xbps-install -y` aborts hard on a no-op.
4. **30 install-kernel** — `ar x` the deb, copy `kernel8.img`, `*.dtb`,
   `overlays/*.dtbo` into `rootfs/boot`, copy modules under
   `rootfs/usr/lib/modules/5.10.17-v8+`, then `depmod -a` inside the chroot.
5. **40 apply-overlay** — `cp -af overlay-boot/* rootfs/boot/` and
   `overlay-root/* rootfs/`.
6. **50 configure-system** — hostname, locale, timezone, create user with the
   right groups, set passwords (using **host-generated `openssl passwd -6`**
   hashes via `usermod -p`, because `chpasswd` inside qemu produces unusable
   hashes), enable runit services, configure greetd, write fstab, **restore
   setuid bits** on `sudo`, `su`, `passwd`, `unix_chkpwd`, etc. (qemu-user
   strips them during `xbps-install`).
7. **90 pack-image** — `truncate` a 6 GiB sparse `.img`, `parted` MBR with
   FAT32 `/boot` + ext4 `/`, loop-mount, `mkfs`, rsync the rootfs in, replace
   the `ROOTDEV` placeholder in `cmdline.txt` with the real `PARTUUID` via
   `blkid`. Final `.img` lands in `deploy/`.

Two of those steps fix gotchas I hit the hard way:

* **qemu-user strips setuid** when xbps-install creates `/usr/bin/sudo` (and
  friends). Without the explicit `chmod 4755` in stage 50, the booted system
  refuses `sudo` with *"must be owned by uid 0 and must have the setuid bit
  set"*.
* **`chpasswd` under qemu produces broken `$6$…` hashes** that pass `useradd`
  but fail `unix_chkpwd` at login. Generating the hash on the host with
  `openssl passwd -6` and applying via `usermod -p` avoids it.

---

## Customising the image

* **Hostname / locale / timezone / credentials** — edit `config.sh`.
* **Package set** — `PACKAGES_*` variables in `config.sh`. Already-installed
  packages are filtered out automatically.
* **Boot args** — `overlay-boot/cmdline.txt`. `ROOTDEV` is replaced with the
  real PARTUUID at image-pack time, so don't change that token.
* **Boot overlays / display flags** — `overlay-boot/config.txt`.
* **Desktop defaults** — anything under
  `overlay-root/etc/skel/.config/{labwc,waybar,foot}/` becomes the per-user
  default for everyone created after this point.
* **Services** — edit the `services="…"` line in
  `scripts/50-configure-system.sh`. Each name must match a directory under
  `/etc/sv/`.

After any change, just re-run `./build.sh`. Untouched stages are fast.

---

## Troubleshooting

### No ReGreet appears

```bash
# switch to a TTY (Ctrl+Alt+F2), log in as aditya / adi28897
sudo sv status greetd
sudo head /var/log/socklog/everything/current     # if socklog enabled
journalctl                                         # NOT applicable on runit
sudo cat /var/log/messages                         # if syslog-ng / socklog
sudo -u _greeter -H sh -c 'cd && dbus-run-session -- labwc' # try greeter session manually
```

### labwc starts but screen is wrong orientation

Edit `~/.config/labwc/outputs.xml` and toggle `<transform>` between `90`,
`180`, and `270` to find the one that matches your panel. (Default is `270`.)

### 4G modem doesn't enumerate

```bash
uconsole-4g status               # check GPIO + ttyUSB*
dmesg | grep -i 'ttyUSB\|option\|qcserial'
uconsole-4g off && sleep 3 && uconsole-4g on
ls /dev/ttyUSB*
```

If `qmi_wwan` and `cdc_wdm` show up despite the blacklist, regenerate the
initramfs (`xbps-reconfigure -f linux`) and reboot.

### sudo says "must be owned by uid 0 and must have the setuid bit set"

The build was produced before the setuid fixup landed. Boot, log in on a TTY
as root (`root / adi28897`), then:

```bash
chmod 4755 /usr/bin/sudo /usr/bin/su /usr/bin/passwd
find /usr -name unix_chkpwd -exec chmod 4755 {} \;
```

### Password doesn't work

Same root cause as above (built before the openssl-hash fix). From a root
TTY:

```bash
passwd aditya
passwd root
```

### Audio not routed

```bash
pactl info               # check PipeWire is running
wpctl status             # inspect WirePlumber graph
pavucontrol              # GUI mixer
```

---

## Known limitations

* **Voice call audio** is not auto-routed from the modem PCM to the speaker
  yet — calls connect (you can see them on the other end) but audio routing
  needs manual `pw-link` glue. Patches welcome.
* **`modem-manager-gui`** is not in xbps. A ready-made `xbps-src` template is
  provided under `xbps-src-templates/modem-manager-gui/` so you can build it
  locally once you have an xbps-src checkout.
* **GPS / NMEA** from `/dev/ttyUSB1` works but no GUI consumer is shipped.
  Use `gpsd` + `gpsmon` or `mmcli -m 0 --location-get`.
* **Bluetooth** packages are installed (`bluez`) but no GUI manager is shipped
  by default — install `blueman` if you want a tray applet.
* The Clockwork 5.10 kernel is **not** mainline. Future mainlining of the
  uConsole CM4 (panel driver upstream) would let us drop this dependency.

---

## Roadmap / ideas

* Auto-route call audio (PipeWire link policy module).
* Build & ship `modem-manager-gui` automatically via xbps-src.
* Optional KDE Plasma Mobile / Phosh variant.
* Optional GPT layout + UEFI for non-Pi-bootloader use cases.
* CI to publish nightly `.img` artifacts.

---

## Credits

* **ClockworkPi** — for the uConsole hardware, kernel, and overlays.
* **Void Linux** — for the aarch64 PLATFORMFS and excellent runit setup.
* **labwc / wlroots / ReGreet / greetd** — for a sensible Wayland stack.
* **ModemManager / NetworkManager** — for actually shipping GSM voice/SMS
  support that just needs the right APs and serial port permissions.

---

## License

Code in this repository (build scripts, overlays, custom tools) is released
under the **MIT License** — do whatever you want, no warranty.

The redistributed payloads keep their upstream licenses:

* Void Linux PLATFORMFS — see <https://github.com/void-linux/void-packages>
* ClockworkPi kernel deb — see <https://github.com/clockworkpi/apt>
* All xbps-installed packages — see individual upstream projects.
