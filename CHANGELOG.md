# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Because this is a collection of setup scripts rather than a library, "breaking"
means a change that alters what a script writes to your system, removes a
command-line flag, or requires you to re-run something you had already applied.

## [1.0.1] — 2026-08-02

Reboot-hardening and cleanup. Re-run `install-touchscreen.sh` to pick up the
unit change; `setup-gps-time.sh` is worth re-running too, since it now enables
`chronyd`. Neither is required if your machine already comes up correctly.

### Fixed

- `cf30-touch-mouse.service` set no `StartLimitIntervalSec`, so with
  `Restart=always` and `RestartSec=2` five quick failures inside ten seconds
  tripped systemd's default start limit and left the unit **permanently
  failed**. At boot the daemon can lose the race against `systemd-modules-load`
  and exit immediately for want of `/dev/uinput`, which is exactly that
  pattern — and on this machine the daemon is the only pointing device, so a
  failed unit meant no cursor. The unit now sets `StartLimitIntervalSec=0`,
  orders itself after module load and udev, and runs `modprobe uinput` first.
- `cf30-touch-mouse` now waits up to 60 s for `/dev/uinput` to appear instead of
  dying on the first attempt, the same way it already waited for the panel.
- `setup-gps-time.sh` now enables `chronyd` rather than only restarting it. The
  refclock lives in `chrony.conf`, so it only survives a reboot if chronyd is
  actually enabled — true by default on Fedora, but the script should not
  assume it.
- `setup-gps-time.sh` now saves `/etc/chrony.conf.bak` before appending, the
  way `setup-gps-serial.sh` already did for `/etc/sysconfig/gpsd`.

### Removed

- Dead `daemon_exists()` helper in `cf30-touch-calibrate`.

### Documentation

- New "Surviving a reboot" section in the README: what comes back on its own,
  how, and the commands to verify it.

## [1.0.0] — 2026-08-02

First public release. Everything below is tested on a Panasonic Toughbook CF-30
running Fedora 44 (LXQt under the Mir/miriway Wayland compositor) on x86-64.

### Added

**Serial GPS** — `setup-gps-serial.sh`

- Detects the SiRF Star III receiver by probing the real serial ports for NMEA,
  rather than assuming `/dev/ttyS3`. Asks a running `gpsd` first, and only falls
  back to probing (with gpsd stood down) so the two do not compete for bytes.
- Configures `/etc/sysconfig/gpsd`, keeping the previous file as `.bak`, and
  enables both `gpsd.socket` and `gpsd.service` so the receiver is polled from
  boot instead of only when a client connects.
- Adds the invoking user to `dialout`.
- Flags: `--scan`, `--status`, `--device`, `--baud`, `--secs`, `--dry-run`,
  `--force`, `--help`.
- Documents the BIOS prerequisite: the GPS needs its own I/O and IRQ
  (0x2E8 / IRQ 5 avoids COM1 and COM2).

**Time from GPS** — `setup-gps-time.sh`, `TIME-OVER-GPS.md`

- Adds a `refclock SHM 0` block to `/etc/chrony.conf` so chrony disciplines the
  clock from gpsd's shared-memory NTP segment once the receiver has a fix.
- Keeps internet NTP as fallback and refinement: there is no PPS on this UART,
  so GPS time is coarse (~0.1 s).

**Touchscreen** — `touchscreen/`

- `72-cf30-touchscreen.rules` reclassifies the Fujitsu panel (USB `0430:0530`)
  from tablet to touchscreen, which udev otherwise gets wrong because the panel
  advertises `BTN_TOOL_PEN` / `BTN_STYLUS`.
- `cf30-touch-mouse`, a daemon that grabs the panel and drives a virtual
  absolute mouse through uinput, because Mir does not emulate a pointer from
  touch. Tap = left click, press-and-hold ~0.6 s = right click, and a drag
  presses the button *at the original touch point* so scrollbar thumbs, sliders
  and handles can be grabbed. Reloads its calibration matrix on SIGHUP and
  re-grabs the panel if it disappears.
- `cf30-touch-mouse.service`, a systemd unit wanted by `graphical.target`.
- `cf30-touch-calibrate`, a 4-corner calibrator that least-squares-fits a
  libinput calibration matrix, writes it as a generated udev rule, and rebinds
  the USB interface so it applies without a reboot. Supports `--show` and
  `--reset`, and pauses/resumes the daemon around the capture.
- `install-touchscreen.sh` to install dependencies, tools, rule and service,
  with `--uninstall` to reverse it.

**Desktop** — `setup-desktop.sh`, `DESKTOP.md`

- Sets the LXQt worldclock panel plugin to a 12-hour local format, stopping the
  panel first because it rewrites `panel.conf` on exit.
- Switches the icon theme away from the incomplete `oxygen` stub shipped here.
- Restarts `pcmanfm-qt` and `lxqt-panel` while inheriting the full environment
  of the running `lxqt-session`, which is what keeps the panel from going
  transparent with blank icons.

### Notes

- All scripts are idempotent and safe to re-run. The README lists everything
  they write outside `$HOME`.
- SELinux runs permissive on this build; that is documented in `DESKTOP.md`, but
  no script here changes your SELinux mode.

[1.0.1]: https://github.com/campbell-r-e/toughbook-cf30-fedora/releases/tag/v1.0.1
[1.0.0]: https://github.com/campbell-r-e/toughbook-cf30-fedora/releases/tag/v1.0.0
