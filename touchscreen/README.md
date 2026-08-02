# CF-30 resistive touchscreen on Fedora (Mir/Wayland)

Getting the Panasonic Toughbook CF-30's resistive touch panel to behave like it
did under Windows Vista — the pen drives the mouse cursor, tap = click, hold =
right click — on Fedora 44 running LXQt under **Mir/miriway** (Wayland).

Quick start:

```
sudo bash install-touchscreen.sh              # install + enable the service
sudo cf30-touch-calibrate                     # 4-corner calibration (at the laptop)
sudo bash install-touchscreen.sh --uninstall  # remove tools, rule and service
```

## The hardware

`lsusb`/evdev show a **"Fujitsu Component USB Touch Panel"**, USB `0430:0530`,
on an internal USB port. It is a single-touch resistive digitizer:

```
EV_KEY: BTN_TOOL_PEN BTN_TOOL_RUBBER BTN_TOUCH BTN_STYLUS
EV_ABS: ABS_X (0..4096)  ABS_Y (0..4096)
Properties: INPUT_PROP_DIRECT
```

## Two problems, and the fixes

### 1. udev calls it a tablet, so nothing clicks

Because the panel advertises `BTN_TOOL_PEN` / `BTN_STYLUS`, systemd's `input_id`
builtin tags it **`ID_INPUT_TABLET=1`** and libinput hands it to the compositor
as a *tablet tool*, not a touchscreen. `72-cf30-touchscreen.rules` overrides that:

```
ENV{ID_VENDOR_ID}=="0430", ENV{ID_MODEL_ID}=="0530",
  ENV{ID_INPUT_TOUCHSCREEN}="1", ENV{ID_INPUT_TABLET}="0", ENV{ID_INPUT_TABLET_PAD}="0"
```

After that, `libinput list-devices` shows `Capabilities: touch`. Apply it live
without a reboot by re-adding the USB interface — the interface name differs per
machine, so look it up rather than copying `1-2:1.0`:

```
# find it: the interface directory under the 0430:0530 USB device
grep -l 0430 /sys/bus/usb/devices/*/idVendor | xargs -n1 dirname
IFACE=1-2:1.0                      # <- whatever the above turned up, plus :1.0
echo -n $IFACE | sudo tee /sys/bus/usb/drivers/usbhid/unbind
echo -n $IFACE | sudo tee /sys/bus/usb/drivers/usbhid/bind
```

`cf30-touch-calibrate` does this lookup and rebind for you after writing a
matrix, so you only need it when applying the classification rule by hand.

### 2. Mir does not emulate a pointer from touch

This is the real catch. Under X11 (and Vista) a touchscreen drove the mouse
pointer for free. **Mir does not** — `miriway-shell --help` offers only
`--enable-touchspots` (visual dots), no touch-to-pointer emulation. So even as a
proper touchscreen, taps produce `wl_touch` events with no cursor, and the LXQt
shell, menus and most controls ignore them.

The fix is `cf30-touch-mouse`, a small daemon that:

* **grabs** the panel (`EVIOCGRAB`) so Mir stops seeing raw touch, and
* creates a **virtual absolute mouse** via `/dev/uinput` and drives it from the
  panel.

The trick that makes the cursor follow absolutely: a uinput device with
`ABS_X`/`ABS_Y` **and** `BTN_LEFT` but **no** `INPUT_PROP_DIRECT` and no
tool/finger bits is classified by udev as `ID_INPUT_MOUSE` — libinput reports it
as `Capabilities: pointer`, and because it carries absolute axes the compositor
positions the cursor absolutely. This is the same path QEMU/VMware "usb-tablet"
absolute pointers take, and it works under Mir.

Gestures the daemon synthesizes:

| Gesture | Output |
|---|---|
| tap | `BTN_LEFT` click at the touch point |
| touch + move past ~60 raw units | `BTN_LEFT` drag |
| press and hold ~0.6 s, stationary | `BTN_RIGHT` click |

**Dragging grabs at the touch point.** When a touch turns into a drag, the
button is pressed *at the original touch point* (the cursor is still sitting
there — it doesn't follow the finger until the drag begins), then it follows.
That's what lets you grab a **scrollbar thumb, slider or handle** in Settings and
other apps and drag it — pressing at the moved-to position instead would grab the
empty space beside the handle. To scroll, drag the app's own scrollbar; there is
no separate scroll gesture.

Tunables at the top of `cf30-touch-mouse`: `HOLD_MS` (hold-to-right-click time,
600 ms) and `MOVE_THRESH` (how far a touch must move before it counts as a drag,
60 raw units). Edit them in `/usr/local/bin/cf30-touch-mouse` and
`systemctl restart cf30-touch-mouse`.

The daemon reloads the calibration matrix on **SIGHUP**
(`sudo systemctl kill -s HUP cf30-touch-mouse`), so a re-calibration does not
need a restart. If the panel disappears — a USB rebind, for instance — it waits
for it to come back and re-grabs it.

## Calibration

There is no interactive Wayland calibrator for Mir, so calibration is a
**libinput calibration matrix** — a 2×3 affine transform on the panel's
normalized `[0,1]` coordinates. `cf30-touch-calibrate` captures four corner
touches, least-squares-fits the matrix, and writes it as
`73-cf30-touch-calibration.rules`:

```
ENV{...}, ENV{LIBINPUT_CALIBRATION_MATRIX}="a b c d e f"
```

The matrix lives in the same normalized space whether libinput applies it (when
the daemon is off) or the daemon applies it (when it owns the panel), so one
calibration serves both. The calibrator automatically pauses/resumes
`cf30-touch-mouse` around the capture, because the daemon holds an exclusive grab.

```
sudo cf30-touch-calibrate            # calibrate (touch TL, TR, BR, BL)
sudo cf30-touch-calibrate --show     # print current matrix / device state
sudo cf30-touch-calibrate --reset    # back to identity
```

## Files

| File | Purpose |
|---|---|
| `cf30-touch-mouse` | daemon: panel → virtual absolute mouse (+ gestures) |
| `cf30-touch-mouse.service` | systemd unit, `WantedBy=graphical.target` |
| `cf30-touch-calibrate` | 4-corner calibrator → libinput matrix |
| `72-cf30-touchscreen.rules` | reclassify tablet → touchscreen |
| `install-touchscreen.sh` | install deps, tools, rule, service (idempotent) |

`73-cf30-touch-calibration.rules` is **generated** by the calibrator, not shipped
— calibration is per-panel.

## Gotchas learned the hard way

* The daemon reads the matrix out of the udev rule; the rule writes it as
  `ENV{LIBINPUT_CALIBRATION_MATRIX}="..."`, so the parser must allow the `}`
  before `="` (a regex without it silently loads identity).
* Grabbing the panel means libinput's own calibration on the panel node is
  bypassed — the daemon must apply the matrix itself. It does.
* `python3-evdev` and the `uinput` kernel module are required; the installer
  loads `uinput` now and via `/etc/modules-load.d/uinput.conf` at boot.
* Both tools must run as root — they need `/dev/input/event*` and `/dev/uinput`.
* `cf30-touch-calibrate` unpacks raw `input_event` structs with the 64-bit
  layout (`llHHi`, 24 bytes). On a 32-bit kernel the timeval halves are 4 bytes
  each and that format would need changing. The CF-30 here is x86-64.
