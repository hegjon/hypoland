# Energy: Hypoland 0.4.0 against Hyprland 0.57.2-4

The numbers of the energy page (`web/energy.html`, `scripts/web/energy.py`, `ENERGY_RUN`) since 2026-11-26.

- Hypoland: the 0.4.0 release package, a plain build (`hypoland-0.4.0-1-x86_64.pkg.tar.zst` of the v0.4.0 GitHub
  release; `binary.size_kB` 12471). scripts/bench from master e771ed393 (no `src/` change since v0.4.0).
- Stock: Hyprland 0.57.2-4 and omarchy-hyprland-titlebars 0.4.0-3, the current packages of Omarchy's repository on
  2026-11-25 (newer than the 0.57.2-2 of the night baselines), seeded into every machine's cache. `pr/` only adds the
  stock quirks file; none of these machines needs the GLES 3 override.
- Both alternated in fresh SDDM sessions from 2026-11-25 17:54 until 2026-11-26 09:00 (`energy.sh`, started by
  `start.sh`): `measure.sh --mode energy --meter rapl`, 30 s per workload with a 10 s idle baseline before and after,
  RAPL read twice a second. Power profile `balanced`, governor left as it was (schedutil; powersave on the T460s and the
  T490), on AC, the system's timers and Omarchy's update checks stopped. Omarchy-dev 4.0.0.r7840, Mesa 26.2.7, kernel
  linux-omarchy 7.2.15-2, Folio 0.6.1-1, Flea 0.4.3-1 under both.

## Machines and sessions

The seven lab machines with a RAPL package zone. The T460s and the T490 also have the platform zone (psys).

| machine | Hypoland | Hyprland |
|---|---|---|
| t550 | 26 | 26 |
| xps | 25 | 25 |
| chromebook | 24 | 24 |
| macmini-intel | 25 | 25 |
| t460s | 25 | 25 |
| t490 | 26 | 26 |
| samsung-i5 | 25 | 25 |

None left out: no invalid workload, no killed measure.sh, no session that did not come up. Not in the run: the X200,
the Turbo-X, the AMD desktop, the HP Notebook (no powercap zone), the Galaxy Book and the Mac mini M1 have no RAPL; the
P14s and the MSI Claw were not in it.

## Files

- per machine `<host>/{hypoland,hyprland}/` (`values.txt` medians, `raw.txt` every session's values, `bench.txt`) and
  `<host>/log` (the run's log on that machine); the block files are not kept.
- `table.txt` (from `table.py`), `report.log` (from `report.sh`), `summary.txt` (the results, below in short).

## Results

- Idle: the same under both, within 2% (0.26 W on the Chromebook to 3.50 W on the Mac mini; psys 1.43 W on the T460s,
  1.99 W on the T490).
- CPU package power under load: lower under Hypoland in nearly every workload on every machine (scrolling -14 to
  -53%, GPU client -3 to -29%, video -2 to -13%, workspace switching -13 to -30%). Where Hypoland draws more, it shows
  about twice the frames (the Chromebook's Qt sprites: +11% W at 26 against 54 fps).
- The one real regression: the T460s's notifications, +26% package power at the same frame rate in all 25 sessions,
  also in the 11-12 run. The compositor itself uses less there; the session's other processes use more (the only
  machine at scale 1.5).
- Against the run of 2026-11-12 (r972 against Hyprland 0.57.1, 1 to 2 sessions per machine): the same picture.
  Nautilus is gone (no longer in Omarchy), and the Mac mini's workspace switching measures again (48 fps; on 11-12 its
  terminals were not on the workspaces it switched between). The Mac mini draws more under both compositors than on
  11-12 (idle session 2.95 against 3.50 W): the machine changed, not either build.
