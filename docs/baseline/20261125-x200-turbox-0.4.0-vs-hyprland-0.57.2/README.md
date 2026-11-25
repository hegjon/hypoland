# X200 and Turbo-X: Hypoland 0.4.0 against Hyprland 0.57.2-2

The lab pages' numbers for the ThinkPad X200 and the Turbo-X Sirus Duo since 2026-11-25 (`scripts/web/labdata.py`,
`X200_TURBOX_RUN` in `FALLBACK`). The other machines' numbers come from the same packages' night,
`20261124-all-machines-0.4.0-vs-hyprland-0.57.2`.

- Hypoland: the 0.4.0 release package, a plain build (`hypoland-0.4.0-1-x86_64.pkg.tar.zst` of the v0.4.0 GitHub
  release, tag v0.4.0, commit 8c78483ff; `/usr/bin/hypoland` 12770928 B). scripts/bench of the same commit.
- Stock: Hyprland 0.57.2-2 and omarchy-hyprland-titlebars 0.4.0-1 from Omarchy's repository, with Omarchy's GLES 3
  override (omarchy#14764, `pr/`), since stock does not start on these GLES 2.0 GPUs otherwise; on the Turbo-X the same
  override with its GPU check widened to ATI R300-R500 (`pr-r300/`).
- Both alternated in fresh SDDM sessions (`abnight.sh`), the same as every night baseline. Apps: Folio 0.6.1-1, Flea
  0.4.3-1 (Flea opens no window on either machine). Mesa and Omarchy as installed on 2026-11-24.

## Sessions, from two runs

| machine | Hypoland | Hyprland | from |
|---|---|---|---|
| x200 | 5 | 5 | night-20261124-040: 3 + 3; night-20261125: 2 + 2 (blocks 101, 102) |
| turbox | 12 | 12 | night-20261124-040: 11 + 10; night-20261125: 1 + 2 (blocks 101, 102) |

- night-20261124-040 (2026-11-24 16:50, fourteen machines): both of these hung during a stock Hyprland block. The X200
  stopped completely at 20:12 in its 4th stock block (ElectroBench running; no ping, logs end with ordinary lines, its
  6 GB were not short). The Turbo-X livelocked out of memory at 03:32 in its 11th stock block (1 GB; memory pressure
  from 02:03, hung tasks from 03:35). The hung blocks are left out (`skip/*-night1.skip`).
- night-20261125 (2026-11-25 13:29, these two only): the Turbo-X was stopped at 15:33 at the user's request (its fan),
  its cut-short Hypoland block 2 left out; the X200 was still running when this was made (its block 3 left out). The
  X200's numbers are to be replaced by that night's full set (its morning report on 11-26).

`combine.sh` builds each machine's `hypoland/` and `hyprland/` (values.txt: key, median, min, max over the sessions;
raw.txt: every session's values; bench.txt; results.om is not committed) from the two runs' block files, as
`report.sh` does; night 2's blocks are numbered from 101. Per machine also the session checks and abnight's logs of both
runs (`*-night1`, `*-night2`) and `compare.txt` (`bench.sh --compare`, Hyprland -> Hypoland).

## Notes for reading them

- The Turbo-X has 1 GB of RAM: part of either compositor sits in swap, so its memory (PSS) reads low for both and does
  not compare with other machines. Chromium (`shm-fullwindow`) opens no window there in any session (an empty clients
  list, 0 frames on the screen), so the lab page leaves that cell empty.
- The X200's 5 sessions of each are fewer than a night's. Against the r1030 PGO night of 11-18 on the lab page's
  columns: Hypoland 2 to 8 % more CPU and 8 % more memory at the start (the plain build: PGO measured 4 to 7 % less CPU
  and 6 to 8 % less memory), the same frames on the screen; stock within 3 %.
