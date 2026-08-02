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
sudo bash setup-gps-serial.sh      # configure gpsd on /dev/ttyS3
sudo bash setup-gps-time.sh        # add a chrony refclock fed by gpsd
cgps -s                            # watch the fix
```

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
sudo bash install-touchscreen.sh   # install + enable the service
sudo cf30-touch-calibrate          # 4-corner calibration (run at the laptop)
```

Full write-up in [`touchscreen/README.md`](touchscreen/README.md).

## Desktop

`setup-desktop.sh` sets the LXQt panel clock to 12-hour local time and fixes the
blank desktop icons (the shipped `oxygen` icon theme is an incomplete stub). See
[`DESKTOP.md`](DESKTOP.md).

## Notes

- Tested on Fedora 44 LXQt under the Mir/miriway Wayland compositor.
- SELinux is run **permissive** on this build; details in
  [`DESKTOP.md`](DESKTOP.md).
