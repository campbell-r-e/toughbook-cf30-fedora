#!/usr/bin/env bash
#
# install-touchscreen.sh — make the CF-30 resistive touch panel usable on
# Fedora + Mir/miriway (LXQt Wayland), the way it worked under Windows Vista:
# the pen drives the mouse cursor, tap = click, hold = right click.
#
#   sudo bash install-touchscreen.sh          # install + enable
#   sudo bash install-touchscreen.sh --uninstall
#
# Idempotent: safe to re-run. See README.md in this directory for the why.
#
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BIN=/usr/local/bin
UDEV=/etc/udev/rules.d
UNIT=/etc/systemd/system
SERVICE=cf30-touch-mouse.service

if [[ -t 1 ]]; then
    C_OK=$'\e[32m'; C_ERR=$'\e[31m'; C_HEAD=$'\e[1;36m'; C_OFF=$'\e[0m'
else
    C_OK=; C_ERR=; C_HEAD=; C_OFF=
fi
section() { printf '\n%s==> %s%s\n' "$C_HEAD" "$*" "$C_OFF"; }
did()  { printf '    %s[ok]%s   %s\n' "$C_OK" "$C_OFF" "$*"; }
die()  { printf '\n%serror:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

(( EUID == 0 )) || die "must run as root — try: sudo bash $0"

uninstall() {
    section "Removing touch-mouse"
    systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
    rm -f "$UNIT/$SERVICE" "$BIN/cf30-touch-mouse" "$BIN/cf30-touch-calibrate"
    rm -f "$UDEV/72-cf30-touchscreen.rules"
    # Leave the generated calibration (73-*) in place unless asked; it is harmless.
    systemctl daemon-reload
    udevadm control --reload
    did "removed tools, service and classification rule"
    printf '\n    Calibration (%s/73-cf30-touch-calibration.rules) left in place.\n\n' "$UDEV"
    exit 0
}
[[ "${1:-}" == "--uninstall" ]] && uninstall

section "Dependencies"
if ! python3 -c "import evdev" >/dev/null 2>&1; then
    dnf install -y python3-evdev >/dev/null 2>&1 || die "could not install python3-evdev"
    did "installed python3-evdev"
else
    did "python3-evdev already present"
fi
# uinput is needed for the virtual mouse; make sure it is loaded now and at boot.
modprobe uinput 2>/dev/null || true
echo uinput > /etc/modules-load.d/uinput.conf
did "uinput module loaded and set to load at boot"

section "Installing tools"
install -m 0755 "$SCRIPT_DIR/cf30-touch-mouse"     "$BIN/cf30-touch-mouse"
install -m 0755 "$SCRIPT_DIR/cf30-touch-calibrate" "$BIN/cf30-touch-calibrate"
did "cf30-touch-mouse and cf30-touch-calibrate -> $BIN"

section "Device classification"
install -m 0644 "$SCRIPT_DIR/72-cf30-touchscreen.rules" "$UDEV/72-cf30-touchscreen.rules"
udevadm control --reload
did "installed 72-cf30-touchscreen.rules (tablet -> touchscreen)"

section "Service"
install -m 0644 "$SCRIPT_DIR/cf30-touch-mouse.service" "$UNIT/$SERVICE"
systemctl daemon-reload
systemctl enable --now "$SERVICE"
sleep 2
if systemctl is-active --quiet "$SERVICE"; then
    did "$SERVICE enabled and running"
else
    die "$SERVICE failed to start — check: journalctl -u $SERVICE"
fi

section "Done"
cat <<EOF
    Touch the screen: the cursor follows your finger, tap = click,
    press-and-hold ~0.6 s = right click.

    Calibrate:   sudo cf30-touch-calibrate
    Show state:  sudo cf30-touch-calibrate --show
    Undo cal.:   sudo cf30-touch-calibrate --reset
EOF
