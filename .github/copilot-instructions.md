# Voiduconsole — Copilot instructions

This repo is a **build system**, not an application. It produces a flashable Void
Linux aarch64 (glibc) SD-card image for the ClockworkPi uConsole CM4 4G. There
is nothing to "run" except the build itself; the artifacts boot on real hardware.

## Build / iterate

```bash
./build.sh                # full build, will sudo for chroot/loop/mkfs
sudo rm -rf work/         # nuke chroot state if a stage died mid-run
                          # (also: sudo umount -lR work/rootfs/{proc,sys,dev/pts,dev})
```

- No test suite, no linter, no CI. Validation = boot the resulting `.img` on
  the uConsole.
- Build runs **stages sequentially** (`scripts/00…90`). Untouched stages are
  cheap on re-run; `downloads/` is the cache for the platformfs tarball and
  Clockwork kernel deb, `work/rootfs/` is the cached chroot.
- Host requirements: `qemu-user-static` + aarch64 binfmt registered. The build
  fails fast if either is missing (`build.sh` top).

## Architecture: how a stage works

`build.sh` sources `config.sh` (all tunables: image size, creds, package lists,
URLs) and then runs each `scripts/NN-*.sh` in order against the same
`work/rootfs/`. Stages assume the previous one's filesystem state.

1. **00 download** → `downloads/` (platformfs tarball, kernel deb)
2. **10 prepare-rootfs** → extract tarball into `work/rootfs/`, drop in
   `qemu-aarch64-static` + `/etc/resolv.conf`
3. **20 install-packages** → bind-mount `/proc /sys /dev /dev/pts`, then
   `xbps-install -Suy` the package set from `config.sh`. Packages already
   installed are filtered out first because `xbps-install -y` aborts on no-op.
4. **30 install-kernel** → `ar x` the Clockwork deb; copy `kernel8.img`,
   `*.dtb`, `overlays/*.dtbo`, modules; `depmod -a` in chroot.
5. **40 apply-overlay** → `cp -af overlay-boot/* → rootfs/boot/` and
   `overlay-root/* → rootfs/`. **This is how you ship config/scripts.**
6. **50 configure-system** → hostname, locale, tz, user creation, services,
   greetd, fstab, **two qemu-user fixups** (see Gotchas).
7. **90 pack-image** → `truncate` sparse `.img`, `parted` MBR (FAT32 boot +
   ext4 root), loop-mount, mkfs, rsync rootfs in, replace `ROOTDEV` token in
   `cmdline.txt` with the real PARTUUID via `blkid`.

## Where to put changes (don't edit `work/rootfs/` directly — it's rebuilt)

| Want to change…                          | Edit…                                                 |
|------------------------------------------|-------------------------------------------------------|
| Hostname / user / passwords / locale / tz| `config.sh`                                           |
| Package set                              | `PACKAGES_*` variables in `config.sh`                 |
| Boot args (cmdline)                      | `overlay-boot/cmdline.txt` (keep the `ROOTDEV` token) |
| Boot overlays / display flags            | `overlay-boot/config.txt`                             |
| Anything in the rootfs (configs, scripts)| add file under `overlay-root/` mirroring target path  |
| Default desktop config for new users     | `overlay-root/etc/skel/.config/{labwc,waybar,foot}/`  |
| Custom CLI tools                         | `overlay-root/usr/local/bin/` + matching `.desktop`   |
| Runit services to enable                 | `services="…"` line in `scripts/50-configure-system.sh` (name must match `/etc/sv/<name>`) |

## Critical gotchas (these have all bitten real builds)

- **qemu-user strips the setuid bit** when xbps-install lays down `sudo`, `su`,
  `passwd`, `unix_chkpwd`, `pkexec`, `polkit-agent-helper-1`. `50-configure-system.sh`
  must `chmod 4755` them post-install or the booted system can't `sudo`.
- **`chpasswd` inside the qemu-aarch64 chroot produces unusable `$6$` hashes.**
  Always generate password hashes on the host with `openssl passwd -6` and
  apply via `usermod -p` (this is what stage 50 does).
- **Display rotation uses opposite conventions** between subsystems on the
  DSI-1 panel: kernel TTY needs `fbcon=rotate:1` + `panel_orientation=right_side_up`
  (in `overlay-boot/cmdline.txt`), but wlroots compositors (labwc / sway) need
  `transform 270` / `wlr-randr --transform 270`. Don't "normalize" them — they
  must disagree.
- **QMI is intentionally blacklisted** (`overlay-root/etc/modprobe.d/blacklist-qmi.conf`)
  so ModemManager talks AT on `/dev/ttyUSB2/3` — required for SIM7600G voice.
  Don't re-enable `qmi_wwan` / `cdc_wdm` without understanding this.
- **Kernel is the Clockwork binary 5.10 deb**, not mainline. Panel/keyboard
  MCU/AXP209/audio-amp drivers are not upstream. Module path is hard-coded:
  `rootfs/usr/lib/modules/5.10.17-v8+`.

## Conventions

- All shell scripts: `#!/bin/bash` + `set -euo pipefail`. Logging via the
  `log()` / `die()` helpers (cyan/red ANSI). Follow the same pattern in new
  stages.
- Stages are numbered with a 10-step gap (`00`, `10`, `20`, …, `90`) so new
  stages can be slotted in without renumbering.
- Custom on-device tools live in `overlay-root/usr/local/bin/` and are named
  `uconsole-*` (`uconsole-4g`, `uconsole-call`, `uconsole-brightness`,
  `uconsole-menu`, `uconsole-cheatsheet`, `uconsole-clip`, `uconsole-osd-vol`,
  `uconsole-osd-bri`). New tools should follow that prefix and ship a matching
  `overlay-root/usr/share/applications/<name>.desktop` so they appear in
  fuzzel.
- **OSD FIFO convention:** `wob` reads from `$XDG_RUNTIME_DIR/wob.sock`. The
  FIFO is created in `labwc/autostart` before `wob` starts. Helpers
  (`uconsole-osd-*`) write a single integer percent followed by `\n` to that
  socket. Use the same path if you add new OSD sources; do not hardcode
  `/tmp/wob.sock`.
- GPIO access uses `libgpiod` (not sysfs, not wiringPi) — see `uconsole-4g`.
- License: MIT for code in this repo; redistributed payloads (Void platformfs,
  Clockwork kernel deb, xbps packages) keep upstream licenses.

## Output

Final artifact: `deploy/voiduconsole-cm4-YYYYMMDD.img` (~6 GiB sparse). Flash
with `dd if=… of=/dev/sdX bs=4M conv=fsync`.
