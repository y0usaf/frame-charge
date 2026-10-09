# frame-charge

Holds a Steam Frame's battery at a charge limit you choose (80, 90 or off) by pausing charging at the limit and resuming a few percent below it, and lifts the limit for one full charge on request.

It won't change charge voltage or current, won't touch Steam's UI or steamos-manager, and doesn't replace Valve's `deckard_charge_daemon`. It writes one control file and puts it back when it stops.

**Status: not yet run against real charging.** Discovery, the hold/resume logic, `full` and clean release are exercised against a directory laid out like sysfs, and `status` and `apply -n` have run read-only on a Frame. Whether pausing really stops charge current on the Frame, and whether Valve's daemon lets the pause stand, is the open experiment (`scratch` probe, below).

## Use

```
frame-charge status        key=value state, read-only
frame-charge apply [-n]    one pass; -n prints the writes instead of making them
frame-charge watch         apply every interval seconds; restores the control on TERM/INT
frame-charge full          charge to 100% once, then the limit applies again
frame-charge release       put the control back where it was
```

Writing the control needs root; `status` and `apply -n` don't.

## Config

`/etc/frame-charge/config` (override with `FRAME_CHARGE_CONFIG`), `key=value` lines, re-read every pass. A missing file means `limit=off`.

| key | default | meaning |
|---|---|---|
| `limit` | `off` | `off` or 1-100 |
| `hysteresis` | `3` | resume charging this many percent below `limit` |
| `interval` | `30` | seconds between passes in `watch` |
| `method` | `auto` | `auto`, `threshold`, `pause` or `enable` |

Unknown keys and bad values stop it with a message.

## How it picks a control

It finds the battery (type `Battery` with a `capacity`) and the control under `/sys/class/power_supply` (`FRAME_CHARGE_SYSFS`); no names are built in. `auto` takes the first that exists:

1. `charge_control_end_threshold`, the standard attribute; the kernel does the hysteresis.
2. `charging_pause`, held at the limit and released at `limit - hysteresis`.
3. `charging_enable`, the same with the opposite sense.

The Frame has no standard threshold, so it uses `charging_pause`. The value it replaced is kept in `/run/frame-charge/orig` and written back by `release` or when `watch` stops.

## Valve's charger daemon

`deckard_charge_daemon` (`deckard-charger.service`) runs on stock SteamOS and on the NixOS Frame, and writes the same charger files (observed: `constant_charge_current` changed on its own between two reads). frame-charge remembers the last value it wrote. If it reads something else on the next pass, it stops with `<file> is X but frame-charge set it to Y: something else is writing it (deckard_charge_ is running)`, restores the control, and the service restarts 60 seconds later. `status` shows `rival=` and `contended=`. A limit that keeps getting overwritten therefore shows up as a restart loop, not as a silent no-op.

## Install

Nix, on the Frame's NixOS: `nix build`, `nix run . -- status`, and a service running `frame-charge watch` with `FRAME_CHARGE_CONFIG` pointing at a store file.

Stock SteamOS (untested there), as root, from a checkout:

```
contrib/stock-install install
contrib/stock-install remove
```

It puts the script and config in `/etc/frame-charge/`, a plain `.service` in `/etc/systemd/system/` and `/etc/atomic-update.conf.d/frame-charge.conf` listing `/etc/frame-charge/**`. Atomic updates keep `/etc/systemd/system/*.service` and the listed paths and drop everything else under `/etc`, which is why it is a service and not a timer. `/usr` is untouched.
