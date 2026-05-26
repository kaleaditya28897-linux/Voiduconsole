# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A build system that patches the official Void Linux XFCE Raspberry Pi image for the ClockworkPi uConsole CM4 4G. It downloads the pre-built XFCE image, loop-mounts it, swaps in the ClockworkPi kernel, and applies hardware configuration. The artifact is a flashable `.img`; validation = boot on hardware.

## Building

    ./build.sh           # full build; prompts for sudo once

Build time: ~5–10 minutes (dominated by image decompress + kernel deb extract). Output: `deploy/voiduconsole-cm4-YYYYMMDD.img`.

**Cached state:**
- `downloads/` — XFCE img.xz + clockwork kernel deb; delete to re-fetch
- `work/<img>` — decompressed working image; delete to re-decompress
- `work/loop.dev` — active loop device path (written by stage 10, deleted by stage 40)

**If a stage fails mid-run, clean up before retrying:**

    sudo umount work/boot work/rootfs 2>/dev/null || true
    sudo losetup -d "$(cat work/loop.dev 2>/dev/null)" 2>/dev/null || true
    rm -f work/loop.dev
    # If the image is corrupted, also: rm work/*.img
    ./build.sh

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
- **Kernel deb puts files at `./boot/firmware/`**, not `./boot/` (Raspberry Pi OS layout). The destination in `work/boot/` is flat — only the source paths in stage 20 use the `firmware/` subdirectory.

## Modem tool

    uconsole-4g on      # GPIO power sequence, waits 13s for /dev/ttyUSB*
    uconsole-4g status  # mmcli -L + network interface check
    uconsole-4g off     # clean shutdown, waits 20s

GPIO access uses `libgpiod` (`gpioset`). The sudoers rule at `overlay-root/etc/sudoers.d/uconsole-4g` allows NOPASSWD execution.
