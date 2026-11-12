# Hypoland r966 vs Hyprland 0.57.1 on eleven machines, 2026-11-11 to 12

Hypoland master r966 (`136e12ff8`) against stock Hyprland 0.57.1-2: every workload of `scripts/bench/measure.sh` with the
games, ElectroBench and the file managers (Nautilus, Flea and Folio), on every test machine, 13 to 18 fresh sessions of
each per machine, alternating from 17:04 on 2026-11-11 to 08:59 on 2026-11-12. It was made the same way as
`../20261110-all-machines-r957-vs-hyprland-0.57.1/`, which the lab, terminals and games pages take their numbers from;
the file manager page (`web/files.html`, `scripts/web/files.py`) takes its numbers from here, since this is the first
night with Folio (`folio`) on every machine. Compare a later build with `<machine>/hypoland/values.txt` to see whether
it got slower, and with `<machine>/hyprland/values.txt` to see where it stands against Hyprland 0.57.1.

## Setup

- Hypoland: `hypoland 0.3.0.r966.g136e12ff8-1`, master `136e12ff8` with the game workloads; the Galaxy Book built its own
  aarch64 package of the same commit. macmini-m1 ran r967, r966 with `eda9bccf5` (no scanout tranche in the dmabuf
  feedback when the outputs are not on the render device), which is on master now.
- Hyprland: `hyprland 0.57.1-2` and `omarchy-hyprland-titlebars 0.3.0-4` from each machine's pacman cache, with
  `quirks:skip_non_kms_dmabuf_formats = false` (`pr/stock-quirks.lua`) and on the X200 Omarchy's GLES 3 override
  (omacom/omarchy#14764, `pr/`).
- Omarchy-dev r7677 (the Galaxy Book Omarchy 4.5.0-3), which exports `HYPRLAND_NO_RT=1`, so both compositors ran without
  realtime scheduling except on the Galaxy Book. Mesa 26.2.6 (macmini-m1 mesa-aurora 26.3.0).
- The file managers: Nautilus 51.1, Flea 0.4.1, Folio 0.1.1 on x86 and 0.2.0 on aarch64. The X200 ran without Flea
  (it needs Vulkan or OpenGL above 2.1 and opens no window on GM45), macmini-m1 has no Flea and samsung-i5 no Folio.
- macmini-intel had no monitor (its HDMI goes to a KVM): `headless-helper.sh` gave each session a headless output.
- `HYPOLAND_SCANOUT_DEBUG=1` was in the session environment of the T550, the XPS, the T460s and the Galaxy Book from their
  second session (it prints the choices of the measured direct scanout to the journal; Hyprland ignores it), taken out
  again by `restore-env.sh` at 08:58.
- The runner is `abnight.sh` (`start.sh` starts it), with the deploy check in the first round
  (`<machine>/hypoland-check.txt`, `hyprland-check.txt`); `<machine>/log` is the runner's log. `report.sh` fetched the
  blocks and wrote `<machine>/<compositor>/values.txt` (`<key> <median> <min> <max>` over the blocks; with an even count
  the lower middle value), `raw.txt` (every block's values, `@ <block> <key> <value>`) and `bench.txt`; `table.py` wrote
  `table.txt`. The block files are not kept here.
- Left out (`x200.skip`): the X200's Hyprland blocks 11 and 13 (stock hung after an Xwayland GPU hang and was killed at
  the hour) and Hypoland block 13 (its GPU context hung three times in 6 s at 03:25 in `dev`, and crocus aborted it in
  `glFlush()` after the kernel banned the context).

## What it shows

Session checks (first round): Hypoland passed all on ten machines; macmini-m1 failed `render fullscreen left`, its
software cursor in the corner where the check parks the pointer (fixed in the checks since, `6476b3cc5`). Hyprland failed
3 to 58.

Compositor CPU per frame on the screen, workloads at least 10% cheaper / within 10% / at least 10% dearer under Hypoland:

| x200 | t550 | xps | lianli | chromebook | t460s | t490 | samsung-i5 | galaxybook | macmini-intel | macmini-m1 |
|---|---|---|---|---|---|---|---|---|---|---|
| 23/2/0 | 45/1/0 | 45/1/0 | 26/14/0 | 37/3/0 | 45/2/0 | 40/7/0 | 42/0/0 | 31/11/4 | 44/0/2 | 36/3/0 |

Dearer: the Galaxy Book's menu (Hypoland 6.70 against Hyprland 4.39 ms, as in the baselines before), Flea (1.15 against
0.96), Xonotic low and ultimate; the Mac mini 2014's vkmark and Xonotic ultimate. Pss at the start 42 to 49 MiB against 115 to 146.

The games' own frame rates are higher under Hypoland nearly everywhere (vkmark samsung-i5 364 against 235, Mac mini 2014
759 against 447, Galaxy Book 3721 against 2652). SuperTuxKart's race stalled under Hypoland's measured direct scanout
(Steady FPS 0 in 15 of 15 races on the Galaxy Book, 7 of 13 on the T460s, 3 of 13 on the T490, 1 on the T550 and the
XPS, never under Hyprland): every change of a fullscreen window's dmabuf feedback made the game rebuild its Vulkan
swapchain. Fixed the next morning (`f934dd1ea`), see AGENTS.md, fullscreen games.

The file managers: under Hyprland 0.57.1 Nautilus opened no window on the X200 in any session (no client in either
workload; not looked into), so the X200 has Nautilus under Hypoland only. Folio 0.1.1 and 0.2.0 do not scroll the list
to the cursor on Down (omacom/folio#18), so `folio-scroll` measures the cursor and the details pane redrawn, not
scrolling.

Crashes and hangs: no compositor crash on ten machines; the X200's GPU hang of Hypoland above, and its GPU hung in
Xwayland (twice under Hyprland, which then hung both times, once under Hypoland, which kept running) and in Xonotic.

`cpu.<workload>.clients_percent` is about 100 points too high in nearly every workload (not in `idle` and `gpu-client`),
under both compositors, also where the client never opened (the X200's Nautilus under Hyprland: 98.6%): something in the clients'
slice keeps a core busy. The r957 baseline has the same. Read the clients' CPU of these nights as about 100 points less.
