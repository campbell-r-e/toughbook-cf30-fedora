# Pulling time from GPS

The CF-30 has a built-in **SiRF Star III serial GPS** on `/dev/ttyS3` (4800 baud)
— see `setup-gps-serial.sh`. Once it has a fix, `chrony` can discipline the
system clock from it. `setup-gps-time.sh` wires that up.

## How it works

`gpsd` exports the GPS time into a **shared-memory NTP refclock** (SHM unit 0).
`chrony` reads that segment:

```
# /etc/chrony.conf
refclock SHM 0 refid GPS precision 1e-1 offset 0.0 delay 0.2
```

`SHM 0` is gpsd's coarse NMEA time. There is **no PPS** wired on this UART, so
accuracy is ~0.1 s — plenty for a desktop clock, but that is why internet NTP is
kept as a fallback/refinement rather than removed. Run `setup-gps-time.sh` to add
the refclock and make sure both `gpsd.socket` **and** `gpsd.service` are enabled
(the socket alone leaves gpsd dead after a reboot until something connects).

```sh
sudo bash setup-gps-time.sh
chronyc -n sources          # a "GPS" refclock line appears
```

## It won't lock without sky view

`chronyc sources` will show the `GPS` source at **`Reach 0`** until the SiRF
actually acquires satellites. Indoors on the internal antenna it typically sees
**one** satellite (`mode:1`, no fix), so gpsd has no valid time to hand chrony
and GPS never disciplines the clock — the wiring is correct, the receiver just
needs a clear view of the sky (or the external GPS antenna connected). You can
watch acquisition with:

```sh
gpspipe -w | grep -o '"nSat":[0-9]*'      # need >=4 for a 3D fix
```

Until then, internet NTP keeps the clock correct, so nothing is broken while you
wait for a fix.
