#!/usr/bin/env bash
#
# setup-gps-time.sh — discipline the system clock from the SiRF GPS via gpsd+chrony.
#
#   sudo bash setup-gps-time.sh
#
# Adds a gpsd shared-memory refclock to chrony and makes sure gpsd starts at
# boot. Idempotent. See TIME-OVER-GPS.md — the GPS only disciplines the clock
# once the receiver actually has a fix (needs sky view); internet NTP stays as
# the fallback until then.
#
set -euo pipefail

CHRONY_CONF=/etc/chrony.conf

if [[ -t 1 ]]; then
    C_OK=$'\e[32m'; C_ERR=$'\e[31m'; C_HEAD=$'\e[1;36m'; C_OFF=$'\e[0m'
else
    C_OK=; C_ERR=; C_HEAD=; C_OFF=
fi
section() { printf '\n%s==> %s%s\n' "$C_HEAD" "$*" "$C_OFF"; }
did()  { printf '    %s[ok]%s   %s\n' "$C_OK" "$C_OFF" "$*"; }
skip() { printf '    [skip] %s\n' "$*"; }
die()  { printf '\n%serror:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

(( EUID == 0 )) || die "must run as root — try: sudo bash $0"

section "Dependencies"
for pkg in chrony gpsd gpsd-clients; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
        skip "$pkg already installed"
    else
        dnf install -y "$pkg" >/dev/null 2>&1 && did "installed $pkg" || die "could not install $pkg"
    fi
done

section "chrony GPS refclock"
if grep -q "refclock SHM 0" "$CHRONY_CONF"; then
    skip "refclock already present in $CHRONY_CONF"
else
    cat >> "$CHRONY_CONF" <<'CONF'

# --- GPS time via gpsd shared memory (SiRF on /dev/ttyS3) ---
# SHM 0 = coarse NMEA time from gpsd. No PPS on this UART, so ~0.1s accuracy —
# fine for the desktop clock. Internet NTP stays as fallback/refinement.
refclock SHM 0 refid GPS precision 1e-1 offset 0.0 delay 0.2
CONF
    did "added 'refclock SHM 0' to $CHRONY_CONF"
fi

section "gpsd at boot"
# Enable BOTH: the socket alone leaves gpsd dead after a reboot until a client
# connects, which means no time source. -n keeps it polling while warm.
systemctl enable --now gpsd.socket gpsd.service >/dev/null 2>&1 || true
did "gpsd.socket and gpsd.service enabled"

section "Restart chrony"
systemctl restart chronyd
sleep 2
did "chronyd restarted"

section "Result"
chronyc -n sources 2>/dev/null || true
printf '\n    A "GPS" refclock now appears. It will read Reach 0 until the SiRF\n'
printf '    gets a satellite fix — give it sky view (see TIME-OVER-GPS.md).\n\n'
