# Voiduconsole

A complete builder that produces a **ready-to-flash Void Linux (glibc) image**
for the **ClockworkPi uConsole CM4** with the **SIM7600G 4G expansion**.

## What you get

* Void Linux aarch64 (glibc) base, runit
* ClockworkPi's CM4 kernel + device tree overlays (`devterm-panel-uc`,
  `devterm-pmu`, `devterm-misc`) so the screen, keyboard, audio amp,
  battery gauge and fan work out of the box.
* **labwc** Wayland compositor + Waybar + wofi + foot + mako
* **greetd + ReGreet** graphical login
* **PipeWire / WirePlumber** audio with `pavucontrol`
* **NetworkManager + nm-applet** (GUI for Wi-Fi *and* the GSM modem)
* **ModemManager + libmbim + libqmi + mobile-broadband-provider-info**
* `/usr/local/bin/uconsole-4g` – libgpiod-based power on/off for the
  SIM7600G (replacement for ClockworkPi's wiringPi script)
* `/usr/local/bin/uconsole-call` – TUI for **voice calls + SMS** via the
  modem's AT port (replacement for gnome-calls, which isn't packaged on
  Void). It implements every recipe from the ClockworkPi wiki.
* Bluetooth (`bluez`), Thunar file manager, Firefox-ESR, mpv, etc.

## Build prerequisites (on your Void desktop)

```sh
sudo xbps-install -y qemu qemu-user-static parted dosfstools e2fsprogs \
  rsync xz wget binutils
# Register the aarch64 binfmt (one-time; lost on reboot):
sudo mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc 2>/dev/null
printf ':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-aarch64-static:OCF' | sudo tee /proc/sys/fs/binfmt_misc/register
```

## Build

```sh
cd ~/Voiduconsole
./build.sh
# -> deploy/voiduconsole-cm4-YYYYMMDD.img
```

The build downloads ~250 MB (Void platformfs + Clockwork kernel deb) and
runs a packaged install inside a qemu-user chroot. Expect 30–60 min on a
typical machine.

## Flash

```sh
lsblk             # find your SD card (e.g. /dev/sdc)
sudo dd if=deploy/voiduconsole-cm4-YYYYMMDD.img \
        of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Boot the uConsole. Default login: **aditya / adi28897** (change it!).

## First-boot checklist

1. `sudo passwd aditya`  – change the password.
2. Grow the rootfs:
   ```sh
   sudo parted /dev/mmcblk0 resizepart 2 100%
   sudo resize2fs /dev/mmcblk0p2
   ```
3. Bring up the modem:
   ```sh
   sudo uconsole-4g enable          # GPIO power sequence (~20 s)
   mmcli -L                          # confirm SIMCOM_SIM7600G-H appears
   nmcli c add type gsm ifname ttyUSB2 con-name 4gnet apn YOUR_APN
   nmcli c up 4gnet
   ```
4. Make a call:
   ```sh
   uconsole-call call 1234567890
   uconsole-call sms  1234567890 "hi from Void"
   ```

## Files / layout

```
config.sh                tunables (user, locale, image size, packages)
build.sh                 entry point
scripts/                 numbered build stages
overlay-boot/            files dropped verbatim into /boot
overlay-root/            files dropped verbatim into /
xbps-src-templates/      optional packages to build under void-packages
```

## Notes / known gaps

* `gnome-calls` and `modem-manager-gui` are **not** packaged for Void.
  `uconsole-call` covers voice/SMS via AT; if you want the GTK
  `modem-manager-gui`, build the supplied xbps-src template under
  `void-packages` and `xbps-install` the result.
* The image uses ClockworkPi's 5.10.17 kernel, the same one their
  official OS ships, so every peripheral they support works here too.
* Wayland is the default; X11 fallbacks still work via Xwayland.
