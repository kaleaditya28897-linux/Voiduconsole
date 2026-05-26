# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A build system that produces a flashable Void Linux aarch64 (glibc) SD-card image for the ClockworkPi uConsole (CM4 and CM5 variants, 4G modem). There is no application to run — the artifact boots on real hardware and is validated by flashing.

## Building

```bash
./build.sh           # full build; prompts for sudo once
```

The build takes 20–40 minutes (dominated by package downloads + firefox-esr under qemu-user). Output: `deploy/voiduconsole-both-YYYYMMDD.img`.

**Cached state:**
- `downloads/` — platformfs tarball + clockwork kernel deb; delete to re-fetch
- `work/rootfs/` — the chroot; reused across re-runs

**If a stage died mid-run, wipe before retrying:**
```bash
sudo umount -lR work/rootfs/{proc,sys,dev/pts,dev} 2>/dev/null
sudo rm -rf work/
./build.sh
```

**Host prerequisites:** `qemu-user-static` installed at `/usr/bin/qemu-aarch64-static` and the aarch64 binfmt handler registered (`/proc/sys/fs/binfmt_misc/qemu-aarch64` must exist). `build.sh` fails fast if either is missing.

There is no test suite or linter. Validation = boot the `.img` on the uConsole.

## Architecture

`build.sh` sources `config.sh` (all tunables), then runs `scripts/00-*.sh` through `scripts/90-*.sh` sequentially, each stage operating on the same `work/rootfs/`.

| Stage | Script | What it does |
|-------|--------|-------------|
| 00 | `00-download.sh` | Fetch platformfs tarball + clockwork kernel deb into `downloads/` |
| 10 | `10-prepare-rootfs.sh` | Extract rootfs, drop in `qemu-aarch64-static` + `resolv.conf` |
| 20 | `20-install-packages.sh` | Bind-mount `/proc /sys /dev /dev/pts`, `xbps-install -Suy` all packages from `config.sh` |
| 30 | `30-install-kernel.sh` | `ar x` the deb, copy both CM4/CM5 kernels, DTBs, overlays, modules; `depmod -a` |
| 40 | `40-apply-overlay.sh` | `cp -af overlay-boot/* → rootfs/boot/` and `overlay-root/* → rootfs/` |
| 50 | `50-configure-system.sh` | Hostname, locale, tz, users, runit services, greetd, fstab, setuid fixups |
| 90 | `90-pack-image.sh` | Partition sparse `.img`, mkfs, rsync rootfs in, patch `ROOTDEV` with real PARTUUID |

## Where to make changes

Do not edit `work/rootfs/` directly — it's rebuilt from scratch.

| Change | Where |
|--------|-------|
| Hostname / user / passwords / locale / timezone | `config.sh` |
| Package set | `PACKAGES_*` variables in `config.sh` |
| Boot args (cmdline) | `overlay-boot/cmdline.txt` — keep `ROOTDEV` token (replaced at pack time) |
| Boot overlays / display flags | `overlay-boot/config.txt` |
| Any rootfs file (configs, scripts) | Mirror target path under `overlay-root/` |
| Default desktop config for new users | `overlay-root/etc/skel/.config/{labwc,waybar,foot}/` |
| Custom CLI tools | `overlay-root/usr/local/bin/uconsole-*` + matching `.desktop` in `overlay-root/usr/share/applications/` |
| Runit services to enable | `services="…"` line in `scripts/50-configure-system.sh` (name must match `/etc/sv/<name>`) |

## Shell script conventions

All scripts use `#!/bin/bash` + `set -euo pipefail`. Logging uses `log()` (cyan) and `die()` (red) ANSI helpers defined in `build.sh`. Follow these patterns in new stages.

Stages are numbered with a 10-step gap (`00`, `10`, …, `90`) so new stages can be inserted without renumbering. The `CHROOT()` helper in each stage is `sudo chroot "$ROOTFS" /usr/bin/qemu-aarch64-static /bin/bash -c "$*"`.

## Critical gotchas

These have all caused real build failures:

- **qemu-user strips setuid bits** when xbps-install lays down `sudo`, `su`, `passwd`, `unix_chkpwd`, `pkexec`, `polkit-agent-helper-1`. Stage 50 must `chmod 4755` them post-install or the booted system can't `sudo`.

- **`chpasswd` inside the qemu-aarch64 chroot produces unusable `$6$` hashes** that fail `unix_chkpwd` at login. Always generate hashes on the host with `openssl passwd -6` and apply via `usermod -p` (as stage 50 does). Never use `chpasswd` inside chroot.

- **Display rotation uses opposite conventions** between kernel and Wayland: kernel TTY needs `fbcon=rotate:1` + `panel_orientation=right_side_up` (in `cmdline.txt`); wlroots compositors (labwc/sway) need `transform 270`. These values must disagree — do not "fix" them to match.

- **QMI is intentionally blacklisted** (`overlay-root/etc/modprobe.d/blacklist-qmi.conf`). ModemManager talks AT on `/dev/ttyUSB2/3` — required for SIM7600G voice calls. Do not re-enable `qmi_wwan` / `cdc_wdm`.

- **`_greeter` needs a real shell** (`/bin/bash`, not `/sbin/nologin`): `nologin` → no PAM session → no elogind session → seatd refuses input devices → no keyboard in ReGreet. Stage 50 calls `usermod -s /bin/bash _greeter`.

- **`xbps-install -y` aborts on a no-op** (already-installed package). Stage 20 filters out installed packages before calling `xbps-install`. Replicate this if adding a new install step.

## Custom on-device tools

All live in `overlay-root/usr/local/bin/` and are named `uconsole-*`. Each should ship a matching `.desktop` file in `overlay-root/usr/share/applications/` so it appears in fuzzel.

OSD convention: `wob` reads from `$XDG_RUNTIME_DIR/wob.sock`. Helpers write a single integer percent + `\n` to that socket. Do not hardcode `/tmp/wob.sock`.

GPIO access uses `libgpiod` (not sysfs, not wiringPi) — see `uconsole-4g` for the pattern.
