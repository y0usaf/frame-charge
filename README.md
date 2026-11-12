# frame-charge

Holds a Steam Frame's battery at a charge limit you choose (80, 90 or off) by pausing charging at the limit and resuming a few percent below it, and lifts the limit for one full charge on request.

It won't change charge voltage or current, won't touch Steam's UI or steamos-manager, and doesn't replace Valve's `deckard_charge_daemon`. It writes one control file and puts it back when it stops.

**Status: run against real charging, and it does not give passthrough.** On a Frame at a 15 V/3 A contract, pausing at the limit stops the charge but leaves the pack supplying part of the load, and Valve's daemon answers a pause by dropping to its low-current path and retrying its high-current path every ~40 seconds. The measurements and what they mean are below.

## What the hold actually does (measured)

Measured on a Frame running NixOS (kernel 6.18, `deckard_charge_daemon` from `deckard-charger.service`), 15 V/3 A PD contract, limit 80, pack 78-85 %, sampled every 2 seconds.

Holding (`charging_pause=1`), 73 samples over 150 s at 78 %, headset under its normal load (~9 W on the VPH rail):

- battery current: mean **-180 mA** (median -160, range -308 to -121), pack status `Discharging`, capacity flat at 78 %;
- charger: `status=Charging`, `charge_type=Standard`, `charger_status=131` (full-on), its own charge-current reading chopped between 0 and 0.83 A;
- USB input: 0.94 A mean at 14.7 V (0.43-1.43 A; the bursts are the daemon's retries).

So the cable covers most of the load but not all of it: the pack supplies about 0.15-0.18 A, roughly 1.5 W. The deficit is the load, not the pack: the same pause with the headset idle (~5 W) gives **-8 to -13 mA**, and charging enabled gives **+1.16 A**. The paused path (the daemon's `QPH(1)`) passes about 0.5-0.6 A from the 15 V adapter, ~8 W; anything the headset draws above that comes out of the pack.

Charging enabled, 73 samples over 150 s: the daemon enters `QPH(2)` (`Sel: 2`), stays there without a single QPH2 retry, charges at +1.16 A mean and raises `constant_charge_current` from 1.0 A to 1.35 A on entry.

With the pause held, the daemon logs `Exiting QPH2 - Unknown` at the transition and then retries the high-current path about every 40 seconds: `QPH2 AICL Timeout, Trying anyway` → `QPH2 Timeout, Exiting` → `QPH(1) - Sel: 1->2` → `2->1`. It never enters QPH2 while the pause is set, so the pack keeps covering the shortfall for as long as the limit is held: roughly 0.2 A out of the pack between `limit` and `limit - hysteresis`, then 1.2 A back in when the resume threshold is reached. The hold bounds the cycling, it does not remove it.

The daemon, not this tool, owns the settings that would change that outcome. While it ran, writes of `constant_charge_current` (1.0 → 0.5 A), `constant_charge_voltage` (8.8 → 8.5 V) and `charging_enable` (1 → 0) were all back to the daemon's values within four seconds, and a `constant_charge_voltage` write also made it drop QPH2 and re-enter. `charging_pause` is the one attribute it leaves alone. Passthrough would need the pack on the QPH2 path while charging is paused, or a charge-current limit above the daemon's 1.0 A, and both belong to the daemon (`qph2_allow`/`qph2_resume`, `constant_charge_current`).

That is why `auto` still picks the pause for the Frame, and why `method=enable` is a poor choice there: the daemon rewrites `charging_enable` within seconds, which shows up as `contended=yes` and a restart loop rather than as a hold.

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

The Frame has no standard threshold, so it uses `charging_pause`. The `charging_enable` fallback is only useful where nothing else owns that file; Valve's daemon rewrites it on the Frame, so there it reports as `contended` instead of holding. The value it replaced is kept in `/run/frame-charge/orig` and written back by `release` or when `watch` stops.

## Valve's charger daemon

`deckard_charge_daemon` (`deckard-charger.service`) runs on stock SteamOS and on the NixOS Frame, and writes the same charger files. Measured on the Frame: it keeps `charging_enable=1`, `constant_charge_current` at 1.0 A on the low-current path and 1.35 A on `QPH(2)`, and `constant_charge_voltage` at 8.8 V, and puts any of them back within four seconds if something else writes them (a `constant_charge_voltage` write also makes it leave QPH2 and re-enter). It leaves `charging_pause` alone and answers a pause by leaving QPH2 and retrying it every ~40 seconds.

frame-charge remembers the last value it wrote. If it reads something else on the next pass, it stops with `<file> is X but frame-charge set it to Y: something else is writing it (deckard_charge_ is running)`, restores the control, and the service restarts 60 seconds later. `status` shows `rival=` and `contended=`. A limit that keeps getting overwritten therefore shows up as a restart loop, not as a silent no-op; the pause does not hit this because the daemon does not rewrite it.

## Install

Nix: `nix build`, `nix run . -- status`.

On the Frame's NixOS, import `nixosModules.default` and set the limit; it runs `frame-charge watch` as a service (restarted after 60 seconds if it stops) and writes the config:

```nix
{
  imports = [ frame-charge.nixosModules.default ];
  frame.charge.limit = 80;
}
```

`frame.charge.limit` is `"off"` (no service) or 1-100; `frame.charge.hysteresis` defaults to 3.

Stock SteamOS (untested there), as root, from a checkout:

```
contrib/stock-install install
contrib/stock-install remove
```

It puts the script and config in `/etc/frame-charge/`, a plain `.service` in `/etc/systemd/system/` and `/etc/atomic-update.conf.d/frame-charge.conf` listing `/etc/frame-charge/**`. Atomic updates keep `/etc/systemd/system/*.service` and the listed paths and drop everything else under `/etc`, which is why it is a service and not a timer. `/usr` is untouched.
