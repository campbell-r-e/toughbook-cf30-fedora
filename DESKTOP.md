# LXQt desktop notes (Fedora 44, Mir/miriway Wayland)

Small desktop fixes for the CF-30 build. `setup-desktop.sh` applies the clock and
icon-theme changes; the rest is documented here because it bit us.

## 12-hour clock

The LXQt panel's **worldclock** plugin defaults to a 24-hour custom format. To
make it 12-hour local time, set in `~/.config/lxqt/panel.conf` under
`[worldclock]`:

```ini
formatType=custom
customFormat="'<b>'h:mm:ss AP'</b><br/><font size=\"-2\">'ddd, d MMM yyyy'<br/>'TT'</font>'"
```

`h:mm:ss AP` is the 12-hour + AM/PM part (`AP` → `AM`/`PM`, `h` → 1–12). The
panel **rewrites `panel.conf` when it exits**, so edit the file only while the
panel is stopped, then relaunch it — otherwise your change is clobbered.

## Desktop icons are blank → wrong icon theme

Symptom: desktop icons (Computer, Home, Trash…) show as text labels with no
images. Cause: `icon_theme=oxygen` in `~/.config/lxqt/lxqt.conf`, but the
installed `oxygen` theme here is a **9-file stub** with none of the standard
icons. Fix — switch to a complete theme (`breeze`, ~7,800 icons, already the
configured fallback):

```ini
# ~/.config/lxqt/lxqt.conf  [General]
icon_theme=breeze
```

Bump `__theme_updated__` to the current epoch-ms in the same file so LXQt apps
reload the theme, then restart `pcmanfm-qt --desktop` and `lxqt-panel`.

## Restarting Wayland GUI apps over SSH — inherit the real environment

Restarting `lxqt-panel` from an SSH shell with a hand-picked environment made the
panel background go transparent (blended into the wallpaper) and its icons go
blank — because it was missing `QT_QPA_PLATFORMTHEME=lxqt`, `XDG_DATA_DIRS`, etc.
The fix is to inherit the **full** environment of the running session, e.g. from
`lxqt-session`:

```sh
SESS=$(pgrep -u "$USER" -x lxqt-session | head -1)
setsid -f bash -c '
  while IFS= read -r -d "" kv; do export "$kv"; done < /proc/'"$SESS"'/environ
  exec /usr/bin/lxqt-panel'
```

`setup-desktop.sh` does exactly this.

## SELinux

This build runs SELinux **permissive** (`/etc/selinux/config` → `SELINUX=permissive`)
because the GPS and desktop daemons kept tripping per-domain denials (and even
a piped `chronyc` triggered a `chronyc_t` popup). The `setroubleshootd` popup
service is masked. Re-enable enforcing anytime with `sudo setenforce 1` and
editing that file back to `enforcing`.
