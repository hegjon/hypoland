#!/usr/bin/env python3
# Writes web/games.html: the games and 3D benchmarks of the benchmark (Xonotic, GravityMark, SuperTuxKart, Yamagi Quake II,
# vkmark, ElectroBench) under Hypoland and stock Hyprland on every machine, one table per benchmark, from the lab page's
# baseline (labdata.py) and, for the benchmarks that night did not have, the short run of 2026-11-11 (GAMES_RUN), so no
# number on the page is typed by hand. Run it again after a new baseline, from anywhere: scripts/web/games.py
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from labdata import ROOT, BASELINE, HYPRLAND, RUN, MACHINES, values, cell, fmt, E, head, FOOTER

OUT = os.path.join(ROOT, "web", "games.html")
GAMES_RUN = "docs/baseline/20261111-games-r964-vs-hyprland-0.57.1"
GAMES_RUN_TEXT = ("2 fresh sessions of each compositor per machine (Hypoland 3 on some), in the afternoon of 2026-11-11, "
                  "Hypoland r964 (the compositor of r957 with two small fixes) against Hyprland " + HYPRLAND + "-2")

# the columns a table can have: key pattern ({w} is the workload), heading, unit, whether lower is better
GAME = ("fps.{w}", "The game's frame rate", "game fps", False)
SCORE = ("fps.{w}", "Score", "score", False)
SCREEN = ("fps.{w}.screen", "Frames on the screen", "fps", False)
STEADY = ("fps.{w}.steady", "Steady FPS", "game fps", False)

# section id, title, data directory, [(workload, column)...] or None for the standard columns of one workload, the
# workload, the text above the table
SECTIONS = [
    ("xonotic-low", "Xonotic, Low", BASELINE, "xonotic-low", [GAME, SCREEN],
     "Xonotic 0.8.6 plays its benchmark demo <code>the-big-keybench</code> fullscreen without vsync at the Low effects "
     "preset, as Phoronix's test does: a native Wayland client through SDL&nbsp;2. The demo is stopped after the "
     "measurement; the game's frame rate is what it drew until then."),
    ("xonotic-ultimate", "Xonotic, Ultimate", BASELINE, "xonotic-ultimate", [GAME, SCREEN],
     "The same demo at the Ultimate preset. Not on the AMD machine: its r600 GPU locked up under the presets above Low."),
    ("gravitymark-gl", "GravityMark, OpenGL", BASELINE, "gravitymark-gl", [GAME, SCREEN],
     "Tellusim's GravityMark 1.89 fullscreen without vsync, an X11 client through Xwayland, its own mean frame rate over "
     "its 167&nbsp;s run. Its OpenGL renderer needs OpenGL&nbsp;4.5 and crashes on several machines, so few rows."),
    ("gravitymark-vk", "GravityMark, Vulkan", BASELINE, "gravitymark-vk", [GAME, SCREEN],
     "The same with its Vulkan renderer: not on the AMD machine (no Vulkan) nor the X200."),
    ("supertuxkart-vk", "SuperTuxKart, Vulkan", GAMES_RUN, "supertuxkart-vk", [GAME, STEADY, SCREEN],
     "SuperTuxKart 1.5's <code>--benchmark</code>: the replay of a race on black_forest, Vulkan, Ultimate effects, no frame "
     "limit and no vsync, fullscreen at the monitor's size. The game's frame rate is the race's frames over its time; "
     "its Steady FPS, one of Phoronix's two charts, is a rate most of the race's frames reach, so a few long stalls make "
     "it 0."),
    ("yquake2-gl3", "Yamagi Quake II, OpenGL 3", GAMES_RUN, "yquake2-gl3", [GAME, SCREEN],
     "Yamagi Quake II 8.10 plays the timedemo of <code>q2demo1.dm2</code> over and over, fullscreen, with 16x anisotropic "
     "filtering and 16x multisampling (8x on Intel), as Phoronix's test does."),
    ("yquake2-vk", "Yamagi Quake II, Vulkan", GAMES_RUN, "yquake2-vk", [GAME, SCREEN],
     "The same with its Vulkan renderer (ref_vk 1.0.2; 4x multisampling on the Adreno)."),
    ("vkmark", "vkmark", GAMES_RUN, "vkmark", [SCORE, SCREEN],
     "vkmark 2025.01 runs its 13 scenes of 10&nbsp;s each fullscreen in mailbox mode: it draws as fast as it can and the "
     "screen shows the newest frame. The score is its own."),
] + [
    (f"electrobench-{s}", f"ElectroBench, {t}", BASELINE, None,
     [(f"electrobench-{s}", GAME[:1] + ("Frame rate, fullscreen",) + GAME[2:]),
      (f"electrobench-{s}-window", GAME[:1] + ("Frame rate, in a window",) + GAME[2:])],
     text)
    for s, t, text in [
        ("guns", "guns", "ElectroBench's first scene, OpenGL&nbsp;2.1, so the X200 too: 110 guns drawn face by face with "
         "<code>glBegin</code>, 60&nbsp;s without vsync, fullscreen and in a window, a native Wayland client. The frame "
         "rate is the scene's own mean."),
        ("ocean", "ocean", "Scene 2, OpenGL&nbsp;3.3 core, 45&nbsp;s, fullscreen and in a window."),
        ("pool", "pool", "Scene 3, OpenGL&nbsp;3.3 core, 45&nbsp;s."),
        ("lines", "lines", "Scene 4, OpenGL&nbsp;3.3 core, 45&nbsp;s."),
    ]
]

def present(run, alias):
    return os.path.isdir(os.path.join(ROOT, run, alias, "hypoland"))

cache = {}
def load(run, alias):
    if (run, alias) not in cache:
        cache[run, alias] = (values(alias, "hypoland", run), values(alias, "hyprland", run))
    return cache[run, alias]

def section_cells(run, alias, columns):
    (hv, _), (sv, _) = load(run, alias)
    cells, any_value = "", False
    for w, (key, _, unit, lower) in columns:
        k = key.format(w=w)
        h, s = hv.get(k), sv.get(k)
        # the game ran under one compositor and gave no result under the other
        if h is None and s is not None and hv.get(f"invalid.{w}"):
            cells += f'<td class="no">no result / {fmt(s, unit)}</td>'
            any_value = True
            continue
        if s is None and h is not None and sv.get(f"invalid.{w}"):
            cells += f'<td class="yes">{fmt(h, unit)} / no result</td>'
            any_value = True
            continue
        if unit == "game fps" and key == STEADY[0] and h is not None and s is not None:
            # a Steady FPS of 0 is a result (a stall), not a missing count
            better, worse = h >= s * 1.05 and h > 0, h <= s * 0.95
            cls = ' class="yes"' if better else (' class="no"' if worse else "")
            cells += f"<td{cls}>{fmt(h, unit)} / {fmt(s, unit)}</td>"
        else:
            cells += cell(h, s, unit, lower)
        any_value |= h is not None or s is not None
    return cells, any_value

def tables():
    out = []
    for i, (sid, title, run, w, columns, text) in enumerate(SECTIONS):
        columns = [(w, c) for c in columns] if w else columns
        body = []
        for m in MACHINES:
            if not present(run, m["alias"]) or (run == BASELINE and not m["baseline"]):
                continue
            cells, any_value = section_cells(run, m["alias"], columns)
            # a machine where the benchmark did not run under either compositor gets no row
            first = columns[0][1][0].format(w=columns[0][0])
            (hv, _), (sv, _) = load(run, m["alias"])
            if first not in hv and first not in sv and not hv.get(f"invalid.{columns[0][0]}"):
                continue
            name = E(m["name"]) + (' <span class="opt">(headless)</span>' if m["alias"] == "macmini-intel" else "")
            body.append(f"          <tr><td>{name}</td>{cells}</tr>")
        heads = "".join(f"<th>{E(c[1])}</th>" for _, c in columns)
        source = (f"Medians of the fresh sessions of {RUN}." if run == BASELINE
                  else f"Medians, which over two sessions are the lower value: {GAMES_RUN_TEXT}.")
        out.append(f"""  <section class="win full" id="{sid}" aria-labelledby="t-{sid}">
    <h2 class="title" id="t-{sid}">{E(title)}</h2>
    <div class="body">
      <p>{text}</p>
      <div class="scroll"><table>
        <thead><tr><th>Hypoland / Hyprland {HYPRLAND}</th>{heads}</tr></thead>
        <tbody>
{chr(10).join(body)}
        </tbody>
      </table></div>
      <p class="note">{source}{NOTES.get(sid, "")}</p>
    </div>
  </section>
""")
    return "\n".join(out)

NOTES = {
    "supertuxkart-vk": " The stalls come with Hypoland's measured direct scanout (<code>render:direct_scanout = auto</code>, "
                       "the default) and are being looked into; on the Mac mini M1 the game cannot make its swapchain "
                       "under it and gives no result, with direct scanout off it runs.",
    "yquake2-vk": " On the Mac mini M1 the game outruns the display on the plane under Hypoland: more frames drawn.",
}

nav = "".join(f'\n    <li><a href="#{sid}">{i + 2}</a></li>' for i, (sid, *_) in enumerate(SECTIONS))
index = "\n".join(f'          <li><a href="#{sid}">{E(title)}</a></li>' for sid, title, *_ in SECTIONS)

page = f"""{head("Hypoland: games and 3D", "Xonotic, GravityMark, SuperTuxKart, Yamagi Quake II, vkmark and ElectroBench under Hypoland and under Hyprland " + HYPRLAND + ": the games' frame rates and the frames on the screen.", "Games and 3D benchmarks under Hypoland and Hyprland " + HYPRLAND + ", on the machines of the lab.", "games.html")}
<!-- Generated by scripts/web/games.py from the baselines' values, do not edit by hand. -->
<nav class="bar" aria-label="Sections">
  <ul class="ws">
    <li><a class="on" href="#top">1</a></li>{nav}
  </ul>
  <div class="right">
    <span class="opt">games</span>
    <span><a href="index.html">home</a></span>
    <span><a href="lab.html">lab</a></span>
    <span><a href="terminals.html">terminals</a></span>
    <span><a href="https://github.com/hegjon/hypoland">github</a></span>
  </div>
</nav>

<main class="desk" id="top">

  <section class="win full" aria-labelledby="t-games">
    <h2 class="title" id="t-games">Games and 3D</h2>
    <div class="body">
      <p>
        Games and 3D benchmarks, fullscreen and without vsync, in Omarchy's session on every machine of
        <a href="lab.html">the lab</a>, under Hypoland and under stock Hyprland {HYPRLAND}. Every cell is
        Hypoland / Hyprland: green where Hypoland is at least 5% better, red where it is at least 5% worse; a dash where
        the benchmark does not run or there is nothing to count. The game's frame rate is what the game drew;
        the frames on the screen are the compositor's page flips a second, which stop at the screen's refresh rate
        (120&nbsp;Hz on the Galaxy Book).
      </p>
      <ul>
{index}
      </ul>
      <p class="note">
        Xonotic, GravityMark and ElectroBench are from the night of the lab page, {RUN}; SuperTuxKart, Yamagi Quake II and
        vkmark came to the benchmark after it and are from a short run, {GAMES_RUN_TEXT}: few sessions, so read those
        tables as a first look. A fullscreen game under Hypoland can go straight to the screen (direct scanout): Hypoland
        measures each fullscreen window both ways and keeps the better. The Mac mini 2014 had no monitor
        for either run (it has a headless output in the short run, so no frames on the screen); the Mac mini M1's display
        driver reports no page flips. On the X200 Hyprland runs with Omarchy's GLES&nbsp;3 override
        (<a href="https://github.com/omacom/omarchy/pull/14764">omarchy#14764</a>), which the games get too.
        Raw data, every session's values and the scripts:
        <a href="https://github.com/hegjon/hypoland/tree/master/{BASELINE}">the night</a>,
        <a href="https://github.com/hegjon/hypoland/tree/master/{GAMES_RUN}">the short run</a>.
      </p>
    </div>
  </section>

{tables()}
</main>

{FOOTER}
"""
open(OUT, "w").write(page)
print(f"wrote {OUT}: {len(SECTIONS)} tables")
