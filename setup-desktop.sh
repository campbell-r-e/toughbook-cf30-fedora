#!/usr/bin/env bash
#
# setup-desktop.sh — LXQt desktop tweaks for the CF-30: 12-hour clock and a
# working icon theme. Run as your normal user (NOT root):
#
#   bash setup-desktop.sh
#
# Idempotent. See DESKTOP.md for the why behind each step.
#
set -euo pipefail

if [[ -t 1 ]]; then
    C_OK=$'\e[32m'; C_ERR=$'\e[31m'; C_HEAD=$'\e[1;36m'; C_OFF=$'\e[0m'
else
    C_OK=; C_ERR=; C_HEAD=; C_OFF=
fi
section() { printf '\n%s==> %s%s\n' "$C_HEAD" "$*" "$C_OFF"; }
did()  { printf '    %s[ok]%s   %s\n' "$C_OK" "$C_OFF" "$*"; }
die()  { printf '\n%serror:%s %s\n' "$C_ERR" "$C_OFF" "$*" >&2; exit 1; }

(( EUID == 0 )) && die "run as your normal user, not root"

CFG="$HOME/.config/lxqt"
PANEL="$CFG/panel.conf"
LXQT="$CFG/lxqt.conf"
ICON_THEME="${ICON_THEME:-breeze}"

[[ -f "$PANEL" ]] || die "no $PANEL — is this an LXQt session?"

# Inherit the full graphical environment of the running session so restarted
# apps get QT_QPA_PLATFORMTHEME, XDG_DATA_DIRS, etc. (see DESKTOP.md).
SESS=$(pgrep -u "$USER" -x lxqt-session | head -1 || true)

restart_app() {  # $1 = exact process name, $2.. = command line to launch
    local name="$1"; shift
    pkill -TERM -u "$USER" -x "$name" 2>/dev/null || true
    for _ in $(seq 1 20); do pgrep -u "$USER" -x "$name" >/dev/null || break; sleep 0.3; done
    pgrep -u "$USER" -x "$name" >/dev/null && { pkill -KILL -u "$USER" -x "$name"; sleep 1; }
    if [[ -n "$SESS" ]]; then
        setsid -f bash -c '
            while IFS= read -r -d "" kv; do export "$kv"; done < /proc/'"$SESS"'/environ
            exec '"$*"'' >/dev/null 2>&1 || true
    fi
}

section "Icon theme -> $ICON_THEME"
if [[ -d "/usr/share/icons/$ICON_THEME" ]]; then
    if grep -q '^icon_theme=' "$LXQT" 2>/dev/null; then
        sed -i "s/^icon_theme=.*/icon_theme=$ICON_THEME/" "$LXQT"
    else
        printf '\n[General]\nicon_theme=%s\n' "$ICON_THEME" >> "$LXQT"
    fi
    STAMP=$(date +%s%3N)
    if grep -q '^__theme_updated__=' "$LXQT" 2>/dev/null; then
        sed -i "s/^__theme_updated__=.*/__theme_updated__=$STAMP/" "$LXQT"
    else
        printf '__theme_updated__=%s\n' "$STAMP" >> "$LXQT"
    fi
    did "icon_theme=$ICON_THEME (oxygen here is an incomplete stub — see DESKTOP.md)"
else
    die "icon theme '$ICON_THEME' not installed under /usr/share/icons"
fi

section "12-hour clock (worldclock plugin)"
# The panel rewrites panel.conf on exit, so stop it BEFORE editing the file.
pkill -TERM -u "$USER" -x lxqt-panel 2>/dev/null || true
for _ in $(seq 1 20); do pgrep -u "$USER" -x lxqt-panel >/dev/null || break; sleep 0.3; done
pgrep -u "$USER" -x lxqt-panel >/dev/null && { pkill -KILL -u "$USER" -x lxqt-panel; sleep 1; }

python3 - "$PANEL" <<'PY'
import re, sys
p = sys.argv[1]
fmt = r'''customFormat="'<b>'h:mm:ss AP'</b><br/><font size=\"-2\">'ddd, d MMM yyyy'<br/>'TT'</font>'"'''
lines = open(p, encoding='utf-8').read().splitlines()
out, i, found = [], 0, False
while i < len(lines):
    ln = lines[i]
    if ln.strip() == '[worldclock]':
        found = True
        out.append(ln); i += 1
        keep = []
        while i < len(lines) and not lines[i].strip().startswith('['):
            k = lines[i]
            if k.strip() and not re.match(r'\s*(formatType|customFormat)\s*=', k):
                keep.append(k)
            i += 1
        out.append('formatType=custom')
        out.append(fmt)
        out.extend(keep)
        continue
    out.append(ln); i += 1
if not found:
    out += ['', '[worldclock]', 'alignment=Right', 'formatType=custom', fmt]
open(p, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
print('  panel.conf worldclock -> 12-hour custom format')
PY
did "worldclock set to h:mm:ss AP"

section "Restart desktop + panel"
if [[ -n "$SESS" ]]; then
    restart_app pcmanfm-qt /usr/bin/pcmanfm-qt --desktop --profile=lxqt
    restart_app lxqt-panel /usr/bin/lxqt-panel
    sleep 2
    did "pcmanfm-qt and lxqt-panel restarted"
else
    printf '    [note] no running lxqt-session found — log out and back in to apply.\n'
fi

printf '\n    Done. Clock reads 12-hour local time; desktop icons use %s.\n\n' "$ICON_THEME"
