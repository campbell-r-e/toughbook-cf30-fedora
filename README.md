# CF-30 on Fedora — GPS and touchscreen

Setup scripts, tools and field notes for two parts of running a Panasonic
Toughbook **CF-30** on **Fedora 44 (LXQt / Wayland)**:

- the built-in **SiRF serial GPS** (and using it to discipline the clock), and
- the resistive **touchscreen**, made to behave like a mouse.

Everything here is original scripts and documentation — no vendor binaries.

## What's in this repo

| Area | Where |
|---|---|
| Serial GPS (SiRF on `/dev/ttyS3`) | `setup-gps-serial.sh` |
| Pull time from GPS (gpsd + chrony) | `setup-gps-time.sh`, [`TIME-OVER-GPS.md`](TIME-OVER-GPS.md) |
| Touchscreen as a mouse + calibration | [`touchscreen/`](touchscreen/) |
| LXQt desktop (12-hour clock, icons) | `setup-desktop.sh`, [`DESKTOP.md`](DESKTOP.md) |

## GPS

The CF-30's GPS option is a **SiRF Star III** receiver on a legacy UART
(`/dev/ttyS3`, 4800 baud). Enable it in the BIOS first (F2 → Device / Wireless
Configuration → GPS, its own I/O + IRQ; 0x2E8 / IRQ 5 avoids COM1 and COM2),
then:

```sh
sudo bash setup-gps-serial.sh      # find the receiver, configure gpsd
sudo bash setup-gps-time.sh        # add a chrony refclock fed by gpsd
cgps -s                            # watch the fix
```

`setup-gps-serial.sh` probes the real serial ports for NMEA rather than assuming
`/dev/ttyS3`, and takes `--scan` (just locate the receiver), `--status` (report
satellites and fix, change nothing), `--device`/`--baud` (skip detection),
`--dry-run` and `--force`. Run it with `--help` for the full list.

`setup-gps-time.sh` adds a gpsd shared-memory refclock so `chrony` disciplines
the clock from GPS once the receiver has a fix. It won't lock without a clear
view of the sky — see [`TIME-OVER-GPS.md`](TIME-OVER-GPS.md).

## Touchscreen

The panel is a Fujitsu resistive digitizer that Mir does not turn into a mouse
on its own. [`touchscreen/`](touchscreen/) reclassifies it as a touchscreen and
runs a small daemon that drives a virtual absolute mouse — the pointer follows
your finger, tap = click, hold = right click — plus a 4-corner calibrator:

```sh
cd touchscreen
sudo bash install-touchscreen.sh              # install + enable the service
sudo cf30-touch-calibrate                     # 4-corner calibration (at the laptop)
sudo bash install-touchscreen.sh --uninstall  # remove it all again
```

Full write-up in [`touchscreen/README.md`](touchscreen/README.md).

## Desktop

`setup-desktop.sh` sets the LXQt panel clock to 12-hour local time and fixes the
blank desktop icons (the `oxygen` icon theme shipped on this install is an
incomplete stub). Run it as **your normal user, not root** — it edits
`~/.config/lxqt` and restarts your panel:

```sh
bash setup-desktop.sh              # ICON_THEME=breeze by default
```

See [`DESKTOP.md`](DESKTOP.md).

## What these scripts change

They are idempotent and safe to re-run, but they do touch system files. Outside
your home directory:

| Script | Writes |
|---|---|
| `setup-gps-serial.sh` | `/etc/sysconfig/gpsd` (old copy kept as `.bak`); enables `gpsd.socket` + `gpsd.service`; adds your user to `dialout`; installs `gpsd`, `gpsd-clients` |
| `setup-gps-time.sh` | appends a `refclock SHM 0` block to `/etc/chrony.conf`; enables gpsd; restarts `chronyd`; installs `chrony`, `gpsd`, `gpsd-clients` |
| `touchscreen/install-touchscreen.sh` | `/usr/local/bin/cf30-touch-*`, `/etc/udev/rules.d/72-cf30-touchscreen.rules`, `/etc/systemd/system/cf30-touch-mouse.service`, `/etc/modules-load.d/uinput.conf`; installs `python3-evdev` |
| `cf30-touch-calibrate` | `/etc/udev/rules.d/73-cf30-touch-calibration.rules` (generated, per-panel) |
| `setup-desktop.sh` | nothing outside `~/.config/lxqt` |

`--uninstall` reverses the touchscreen install (it leaves the generated
calibration rule and `uinput.conf` in place, both harmless).

## Surviving a reboot

Run the scripts once; everything below comes back on its own at the next boot.
Nothing here needs to be re-run, and there is no login script to install.

| Piece | How it comes back |
|---|---|
| GPS | `gpsd.socket` **and** `gpsd.service` are both enabled. Enabling only the socket is the classic trap: gpsd then stays dead after a reboot until some client connects, so nothing feeds chrony |
| GPS time | the `refclock SHM 0` line lives in `/etc/chrony.conf`, and `chronyd` is enabled |
| Touch panel classification | udev rules in `/etc/udev/rules.d` are re-read every boot |
| Calibration | same — the generated `73-*` rule is applied by udev, and the daemon re-reads it on start |
| Touch-to-mouse daemon | `cf30-touch-mouse.service`, `WantedBy=graphical.target` |
| `uinput` module | `/etc/modules-load.d/uinput.conf` |
| Desktop clock and icons | plain settings in `~/.config/lxqt`; LXQt reloads them at login |

The touch daemon is the one with real boot-ordering exposure, since it needs
both `/dev/uinput` (a module load) and the USB panel (an enumeration) before it
can do anything. It waits for each of them instead of exiting, its unit sets
`StartLimitIntervalSec=0` so a slow boot can never latch it into `failed`, and
`Restart=always` covers the rest. That matters more than usual here: on a
tablet-style machine this daemon *is* the pointer, so a failed unit means no
cursor and no easy way to fix it.

Check the whole lot after a reboot with:

```sh
systemctl is-enabled gpsd.socket gpsd.service chronyd cf30-touch-mouse.service
systemctl status cf30-touch-mouse.service
chronyc -n sources                 # the GPS refclock line
sudo bash setup-gps-serial.sh --status
```

## Notes

- Tested on Fedora 44 LXQt under the Mir/miriway Wayland compositor, on x86-64.
  Nothing here is CF-30-exclusive in principle, but the device IDs, the serial
  port and the BIOS steps are.
- SELinux is run **permissive** on this build; details in
  [`DESKTOP.md`](DESKTOP.md). None of these scripts change your SELinux mode.
- Provided as-is under the MIT license. They run as root and reconfigure system
  services — read them before you run them.
