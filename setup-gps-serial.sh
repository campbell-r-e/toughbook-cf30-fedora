#!/usr/bin/env bash
#
# setup-gps-serial.sh — set up the CF-30's built-in serial GPS on Fedora 44
#
# A Toughbook with the GPS option has a SiRF Star III receiver on a legacy UART
# (ACPI PNP0501). It streams NMEA from boot, so it Just Works once the serial
# port and gpsd are configured.
#
# Enable it in the BIOS first: F2 -> Wireless/Device Configuration -> GPS, with
# its own I/O and IRQ. 0x2E8 with IRQ 5 works and avoids COM1 (3F8/IRQ4) and
# COM2 (2F8/IRQ3); sharing a legacy ISA interrupt gives you a port that opens
# and then stays silent.
#
# Safe to re-run — it detects the port, and skips work already done.
#
#   sudo bash setup-gps-serial.sh              # detect, configure gpsd, verify
#   sudo bash setup-gps-serial.sh --device /dev/ttyS3 --baud 4800
#   sudo bash setup-gps-serial.sh --scan       # just find the receiver
#   sudo bash setup-gps-serial.sh --status     # report fix state, change nothing
#   sudo bash setup-gps-serial.sh --dry-run
#
# shellcheck disable=SC2016  # '$G' is an NMEA prefix, not a shell variable
#
set -euo pipefail

GPSD_SYSCONFIG="/etc/sysconfig/gpsd"
DEVICE=""
BAUD=""
DRY_RUN=0
FORCE=0
SCAN_ONLY=0
STATUS_ONLY=0
SCAN_SECS=6
BAUDS=(4800 9600 19200 38400)

if [[ -t 1 ]]; then
    C_OK=$'\e[32m'; C_SKIP=$'\e[2m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'
    C_HEAD=$'\e[1;36m'; C_OFF=$'\e[0m'
else
    C_OK=; C_SKIP=; C_WARN=; C_ERR=; C_HEAD=; C_OFF=
fi
section() { printf '\n%s==> %s%s\n' "$C_HEAD" "$*" "$C_OFF"; }
did()   { printf '    %s[ok]%s   %s\n' "$C_OK"   "$C_OFF" "$*"; }
skip()  { printf '    %s[skip]%s %s\n' "$C_SKIP" "$C_OFF" "$*"; }
warn()  { printf '    %s[warn]%s %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
would() { printf '    %s[dry]%s  %s\n' "$C_WARN" "$C_OFF" "$*"; }
die()   { printf '\n%serror:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

usage() {
    awk 'NR>1 && /^#/ {sub(/^#[[:space:]]?/, ""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}"
    exit "${1:-0}"
}

while (( $# )); do
    case "$1" in
        -d|--device)  DEVICE="${2:?--device needs a value}"; shift 2 ;;
        -b|--baud)    BAUD="${2:?--baud needs a value}"; shift 2 ;;
        --scan)       SCAN_ONLY=1; shift ;;
        --status)     STATUS_ONLY=1; shift ;;
        --secs)       SCAN_SECS="${2:?--secs needs a value}"; shift 2 ;;
        -n|--dry-run) DRY_RUN=1; shift ;;
        -f|--force)   FORCE=1; shift ;;
        -h|--help)    usage 0 ;;
        *)            printf 'unknown option: %s\n\n' "$1" >&2; usage 1 ;;
    esac
done

# --- detection --------------------------------------------------------------

# Every possible /dev/ttySn node exists whether or not a UART sits behind it;
# the ones without hardware fail at the termios call, not at open(). So probe
# with stty and treat failure as "not a real port" rather than an error.
port_is_real() { stty -F "$1" >/dev/null 2>&1; }

# Listen for NMEA at one speed. Returns 0 and prints a sample if found.
listen_nmea() {
    local dev="$1" baud="$2" secs="$3" out
    stty -F "$dev" "$baud" raw -echo -echoe -echok -crtscts 2>/dev/null || return 1
    out="$(timeout "$secs" head -c 2048 < "$dev" 2>/dev/null | tr -d '\r' | grep -m3 '^\$G' || true)"
    [[ -n "$out" ]] || return 1
    printf '%s\n' "$out"
}

# gpsd holds its device open, so a naive scan finds nothing when the receiver
# is already configured. Ask gpsd first, and only fall back to probing ports —
# with gpsd stopped, so it is not competing for the same bytes.
ask_gpsd() {
    command -v gpspipe >/dev/null 2>&1 || return 1
    systemctl is-active --quiet gpsd 2>/dev/null || return 1
    local out dev bps
    out="$(timeout 12 gpspipe -w -n 6 2>/dev/null || true)"
    dev="$(printf '%s' "$out" | grep -o '"path":"[^"]*"' | head -1 | cut -d'"' -f4)"
    bps="$(printf '%s' "$out" | grep -o '"bps":[0-9]*' | head -1 | cut -d: -f2)"
    [[ -n "$dev" && -n "$bps" ]] || return 1
    printf '%s %s\n' "$dev" "$bps"
}

scan_for_gps() {
    local dev baud sample restart=0

    if found_via_gpsd="$(ask_gpsd)"; then
        printf '%s\n' "$found_via_gpsd"
        return 0
    fi

    # Nothing to ask, so probe. Stand gpsd down first if it is up, or it will
    # eat every byte we are looking for.
    if systemctl is-active --quiet gpsd 2>/dev/null; then
        systemctl stop gpsd gpsd.socket >/dev/null 2>&1 || true
        restart=1
        sleep 1
    fi

    for dev in /dev/ttyS[0-9] /dev/ttyS1[0-9]; do
        [[ -e "$dev" ]] || continue
        port_is_real "$dev" || continue
        for baud in "${BAUDS[@]}"; do
            if sample="$(listen_nmea "$dev" "$baud" "$SCAN_SECS")"; then
                printf '%s %s\n' "$dev" "$baud"
                printf '%s\n' "$sample" | sed 's/^/        /' >&2
                if (( restart )); then systemctl start gpsd.socket gpsd >/dev/null 2>&1 || true; fi
                return 0
            fi
        done
    done
    if (( restart )); then systemctl start gpsd.socket gpsd >/dev/null 2>&1 || true; fi
    return 1
}

if (( SCAN_ONLY )); then
    (( EUID == 0 )) || die "must run as root — try: sudo bash $0 --scan"
    section "Scanning for an NMEA receiver"
    if found="$(scan_for_gps)"; then
        read -r d b <<<"$found"
        did "found NMEA on $d at $b baud"
    else
        warn "no NMEA on any real serial port"
        printf '    Real ports on this machine:\n'
        dmesg 2>/dev/null | grep -oE 'ttyS[0-9]+ at I/O 0x[0-9a-f]+ \(irq = [0-9]+' | sed 's/^/      /'
        printf '\n    If none of them carry NMEA, the GPS is either disabled in the BIOS\n'
        printf '    or the receiver is not fitted — it is an option, not standard.\n'
    fi
    printf '\n'
    exit 0
fi

# --- status -----------------------------------------------------------------

report_status() {
    section "GPS status"
    if ! command -v gpspipe >/dev/null 2>&1; then
        warn "gpspipe not installed (dnf install gpsd-clients)"
        return 0
    fi
    local out
    out="$(timeout 20 gpspipe -w -n 15 2>/dev/null || true)"
    if [[ -z "$out" ]]; then
        warn "gpsd produced nothing — is it running? systemctl status gpsd"
        return 0
    fi
    local dev drv sats used mode
    dev="$(printf '%s' "$out" | grep -o '"path":"[^"]*"' | head -1 | cut -d'"' -f4)"
    drv="$(printf '%s' "$out" | grep -o '"driver":"[^"]*"' | head -1 | cut -d'"' -f4)"
    sats="$(printf '%s' "$out" | grep -o '"nSat":[0-9]*' | tail -1 | cut -d: -f2)"
    used="$(printf '%s' "$out" | grep -o '"uSat":[0-9]*' | tail -1 | cut -d: -f2)"
    mode="$(printf '%s' "$out" | grep -o '"mode":[0-9]*' | tail -1 | cut -d: -f2)"
    did "device      ${dev:-unknown} (${drv:-unknown} driver)"
    did "satellites  ${sats:-0} in view, ${used:-0} used"
    case "${mode:-1}" in
        3) did "fix         3D" ;;
        2) did "fix         2D" ;;
        *) warn "fix         none yet" ;;
    esac
    if [[ "${mode:-1}" == "1" ]]; then
        if [[ "${sats:-0}" == "0" ]]; then
            printf '    Zero satellites in view. Indoors that is normal — the receiver is\n'
            printf '    talking, it just cannot hear anything. Take it outside.\n'
        else
            printf '    Satellites are being tracked but there is no fix yet. A cold start\n'
            printf '    needs ~12.5 minutes of clear sky to download the almanac.\n'
        fi
    fi
}

if (( STATUS_ONLY )); then
    report_status
    printf '\n'
    exit 0
fi

# --- setup ------------------------------------------------------------------

(( EUID == 0 )) || die "must run as root — try: sudo bash $0"

section "Packages"
for p in gpsd gpsd-clients; do
    if rpm -q "$p" >/dev/null 2>&1; then
        skip "$p already installed"
    elif (( DRY_RUN )); then
        would "dnf install -y $p"
    elif dnf install -y "$p" >/dev/null 2>&1; then
        did "installed $p"
    else
        warn "could not install $p"
    fi
done

section "Finding the receiver"
if [[ -n "$DEVICE" && -n "$BAUD" ]]; then
    did "using $DEVICE at $BAUD baud (given on the command line)"
else
    if found="$(scan_for_gps)"; then
        read -r d b <<<"$found"
        DEVICE="${DEVICE:-$d}"
        BAUD="${BAUD:-$b}"
        did "NMEA on $DEVICE at $BAUD baud"
    else
        warn "no NMEA found on any serial port"
        printf '\n    Check, in this order:\n'
        printf '      1. BIOS (F2): the GPS entry must be enabled, with its own I/O and\n'
        printf '         IRQ. 0x2E8 / IRQ 5 is a good pick; avoid IRQ 3 and 4, which\n'
        printf '         belong to COM2 and COM1 and are not shareable.\n'
        printf '      2. Whether the receiver is actually fitted — it is a factory\n'
        printf '         option. The BIOS entry appears either way.\n'
        printf '      3. sudo bash %s --scan --secs 15   (slower, more patient scan)\n' "$0"
        exit 1
    fi
fi

section "gpsd"
read -r -d '' gpsd_conf <<CONF || true
# Written by setup-gps-serial.sh
# -n keeps gpsd polling without a client attached, so the receiver stays warm.
GPSD_OPTIONS="-n -s $BAUD"
DEVICES="$DEVICE"
USBAUTO="false"
CONF

if [[ -f "$GPSD_SYSCONFIG" ]] && [[ "$(cat "$GPSD_SYSCONFIG")" == "$gpsd_conf" ]] && (( ! FORCE )); then
    skip "$GPSD_SYSCONFIG already current"
elif (( DRY_RUN )); then
    would "write $GPSD_SYSCONFIG pointing at $DEVICE @ $BAUD"
else
    [[ -f "$GPSD_SYSCONFIG" ]] && cp -a "$GPSD_SYSCONFIG" "$GPSD_SYSCONFIG.bak"
    printf '%s\n' "$gpsd_conf" > "$GPSD_SYSCONFIG"
    did "$GPSD_SYSCONFIG -> $DEVICE @ $BAUD (old saved as .bak)"
fi

if (( ! DRY_RUN )); then
    # gpsd.socket alone only starts gpsd when a client connects. With -n we
    # want the receiver polled from boot, so enable the service too — otherwise
    # nothing runs after a reboot until someone opens cgps.
    systemctl enable gpsd.socket >/dev/null 2>&1 || true
    systemctl enable gpsd.service >/dev/null 2>&1 || true
    systemctl restart gpsd.socket >/dev/null 2>&1 || true
    systemctl restart gpsd >/dev/null 2>&1 || systemctl start gpsd >/dev/null 2>&1 || true
    if systemctl is-active --quiet gpsd; then
        did "gpsd running on $DEVICE"
    else
        warn "gpsd is not active — journalctl -u gpsd"
    fi

    if [[ -n "${SUDO_USER:-}" ]] && getent group dialout >/dev/null 2>&1; then
        if id -nG "$SUDO_USER" 2>/dev/null | tr ' ' '\n' | grep -qx dialout; then
            skip "$SUDO_USER already in dialout"
        else
            usermod -aG dialout "$SUDO_USER"
            did "added $SUDO_USER to dialout (log out and back in)"
        fi
    fi
fi

if (( DRY_RUN )); then
    printf '\n'
    exit 0
fi

report_status

section "Using it"
cat <<NEXT
    cgps -s                      curses client
    gpspipe -w -n 20             raw JSON from gpsd
    gpsmon                       receiver detail
    cat $DEVICE                  raw NMEA (needs dialout membership)
    sudo bash $0 --status        the summary above, any time

    This receiver streams NMEA straight from the UART. It needs a clear view
    of the sky and nothing else.
NEXT
printf '\n'
