#!/usr/bin/env python3
# Writes web/energy.html: the power Hypoland and stock Hyprland draw on the machines with RAPL, from the energy run of
# 2026-11-12 (ENERGY_RUN), so no number on the page is typed by hand. ENERGY_RUN in the environment points it at another
# run with report.sh's layout (<run>/<host>/<compositor>/values.txt and raw.txt). Run it again after a new energy run,
# from anywhere: scripts/web/energy.py
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from labdata import ROOT, HYPRLAND, MACHINES, values, cell, fmt, E, head, FOOTER

OUT = os.path.join(ROOT, "web", "energy.html")
ENERGY_RUN = os.environ.get("ENERGY_RUN", "docs/baseline/20261112-energy-r972-vs-hyprland-0.57.1")
ENERGY_RUN_TEXT = ("alternating on 2026-11-12 from 11:51 to 17:30, Hypoland master r972 (after 0.3.0) against Hyprland "
                   + HYPRLAND + "-2")
# ENERGY_PRELIMINARY=1: a run still going; the page says so and asks search engines to leave it out
PRELIMINARY = os.environ.get("ENERGY_PRELIMINARY") == "1"
if PRELIMINARY:
    ENERGY_RUN_TEXT = ("alternating on 2026-11-12 from 11:51, Hypoland master r972 (after 0.3.0) against Hyprland "
                       + HYPRLAND + "-2")

# workload, label, what it is; in the order of the benchmark
WORKLOADS = [
    ("idle", "Idle", "The session with nothing open: Omarchy's bar, wallpaper and shell."),
    ("gpu-client", "GPU client", "<code>weston-simple-egl</code>, a spinning triangle drawn with OpenGL at 60 frames a second."),
    ("video", "Video, fullscreen", "mpv playing a 30 fps clip fullscreen."),
    ("video-window", "Video, window", "The same clip in a tiled window."),
    ("gtk3-scroll", "GTK 3 scrolling", "A GTK&nbsp;3 window scrolling a long text, the whole window redrawn every frame."),
    ("gtk4-scroll", "GTK 4 scrolling", "The same in GTK&nbsp;4, drawn on the GPU."),
    ("qt-quick-scroll", "Qt Quick scrolling", "The same in Qt Quick, drawn on the GPU."),
    ("qt-software-scroll", "Qt software scrolling", "The same with Qt Quick's software backend, drawn on the CPU into shared memory."),
    ("gtk3-x11-scroll", "GTK 3 through X11", "The GTK&nbsp;3 window as an X11 client, through Xwayland."),
    ("gtk4-spinner", "GTK 4 spinner", "A GTK&nbsp;4 window with only a spinner moving."),
    ("qt-software-sprites", "Qt sprites", "60 small squares moving in a Qt software window: many small updates a frame."),
    ("tk-canvas", "Tk canvas", "The same squares on a Tk canvas, an X11 client through Xwayland."),
    ("workspace-switch", "Workspace switching", "Three terminals, switching between two workspaces with Omarchy's slide animation."),
    ("dev", "Developer's screen", "An editor scrolling, a console typed into and a log printing 200 lines a second, the focus moving between them."),
    ("notifications", "Notifications", "A notification a second from four senders, sliding in and out of the shell's column."),
    ("menu", "Omarchy's menu", "Omarchy's menu opened and closed every second."),
    ("nautilus-scroll", "Nautilus scrolling", "Nautilus scrolling a folder of 5000 files with the Down key held."),
]
LOAD = [w for w, *_ in WORKLOADS if w != "idle"]
# cells left out, with why: on the Mac mini 2014 the workspace switching found none of its terminals on the workspaces
# it switched between, in every session of both compositors (windows.py: "the focus is not on one of the windows"), so
# it switched near-empty workspaces at 5 frames a second instead of about 49
SKIP = {("macmini-intel", "workspace-switch"): "On the Mac mini 2014 the workspace switching is left out: in every "
        "session of both compositors its terminals were not on the workspaces it switched between, so it measured "
        "almost nothing (5 frames a second instead of about 49 in earlier runs). Not yet looked into."}

data = {m["alias"]: (values(m["alias"], "hypoland", ENERGY_RUN), values(m["alias"], "hyprland", ENERGY_RUN))
        for m in MACHINES if os.path.isdir(os.path.join(ROOT, ENERGY_RUN, m["alias"], "hypoland"))}
rows = [m for m in MACHINES if m["alias"] in data]
psys = [m for m in rows if "power.baseline.psys_W" in data[m["alias"]][0][0]]

def raw(alias, compositor):
    """Every block's values: {block: {key: value}}."""
    blocks = {}
    for line in open(os.path.join(ROOT, ENERGY_RUN, alias, compositor, "raw.txt")):
        parts = line.split()
        if len(parts) >= 4:
            try: blocks.setdefault(parts[1], {})[parts[2]] = float(parts[3])
            except ValueError: pass
    return blocks

RAW = {m["alias"]: (raw(m["alias"], "hypoland"), raw(m["alias"], "hyprland")) for m in rows}

def per_frame(blocks, w, net="net_W"):
    """The energy above the idle session per frame on the screen in mJ: per block, then the median over the blocks, so
    the energy and the frames come from the same session."""
    v = sorted(b[f"power.{w}.{net}"] * 1000 / b[f"fps.{w}.screen"] for b in blocks.values()
               if f"power.{w}.{net}" in b and b.get(f"fps.{w}.screen", 0) >= 1)
    return v[(len(v) - 1) // 2] if v else None

def change(h, s):
    return 100 * (h - s) / s if h is not None and s and s > 0 else None

def median(xs):
    xs = sorted(x for x in xs if x is not None)
    if not xs: return None
    n = len(xs)
    return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2

def pct(x):
    if x is None: return "<td>&ndash;</td>"
    cls = ' class="yes"' if x <= -5 else (' class="no"' if x >= 5 else "")
    return f"<td{cls}>{x:+.0f}%</td>"

def section(sid, title, intro, table, note):
    return f"""  <section class="win full" id="{sid}" aria-labelledby="t-{sid}">
    <h2 class="title" id="t-{sid}">{E(title)}</h2>
    <div class="body">
{intro}      <div class="scroll"><table class="wide">
{table}
      </table></div>
      <p class="note">{note}</p>
    </div>
  </section>
"""

def glance():
    body = []
    for m in rows:
        (hv, _), (sv, _) = data[m["alias"]]
        hr, sr = RAW[m["alias"]]
        load = [w for w in LOAD if (m["alias"], w) not in SKIP]
        power = median(change(hv.get(f"power.{w}.W"), sv.get(f"power.{w}.W")) for w in load)
        frame = median(change(per_frame(hr, w), per_frame(sr, w)) for w in load if w != "menu")
        body.append(f"          <tr><td>{E(m['name'])}</td><td>{E(m['gpu'])}</td>"
                    + cell(hv.get("power.baseline.W"), sv.get("power.baseline.W"), "W", True) + pct(power) + pct(frame) + "</tr>")
    return ("        <thead><tr><th>Machine</th><th>GPU</th><th>Idle session, Hypoland / Hyprland " + HYPRLAND
            + "</th><th>Under load: power</th><th>Under load: energy per frame</th></tr></thead>\n        <tbody>\n"
            + "\n".join(body) + "\n        </tbody>")

def by_machine(value, unit, workloads, machines=None):
    """A table with a row per machine and a column per workload."""
    machines = machines or rows
    labels = [(w, label) for w, label, _ in WORKLOADS if w in workloads]
    heads = "".join(f"<th>{E(label)}</th>" for _, label in labels)
    body = []
    for m in machines:
        cells = "".join("<td>&ndash;</td>" if (m["alias"], w) in SKIP else cell(*value(m["alias"], w), unit, unit != "fps")
                        for w, _ in labels)
        body.append(f"          <tr><td>{E(m['name'])}</td>{cells}</tr>")
    return (f"        <thead><tr><th>Hypoland / Hyprland {HYPRLAND}</th>{heads}</tr></thead>\n        <tbody>\n"
            + "\n".join(body) + "\n        </tbody>")

def watts(key):
    return lambda a, w: (data[a][0][0].get(f"power.{w}.{key}"), data[a][1][0].get(f"power.{w}.{key}"))

def joules(net):
    return lambda a, w: (per_frame(RAW[a][0], w, net), per_frame(RAW[a][1], w, net))

def psys_watts(a, w):
    key = "power.baseline.psys_W" if w == "idle" else f"power.{w}.psys_W"
    return data[a][0][0].get(key), data[a][1][0].get(key)

sessions = [min(data[m["alias"]][0][1], data[m["alias"]][1][1]) for m in rows]
SESSIONS = (f"{min(sessions)}" if min(sessions) == max(sessions) else f"{min(sessions)} to {max(sessions)}") + \
    (" fresh session" if max(sessions) == 1 else " fresh sessions")
machine_names = ", ".join(E(m["name"]) for m in rows[:-1]) + " and " + E(rows[-1]["name"])
workload_rows = "\n".join(f"          <tr><td>{E(l)}</td><td>{d}</td></tr>" for _, l, d in WORKLOADS)

SECTIONS = [
    ("glance", "At a glance",
     "",
     glance(),
     "The idle session is the mean power with nothing open, between the workloads. Under load: the median over the "
     f"{len(LOAD)} workloads of how much less (or more) the package draws under Hypoland than under Hyprland; per frame "
     "the same for the energy above the idle session per frame on the screen (without the menu, see below)."),
    ("power", "The CPU package's power",
     "",
     by_machine(lambda a, w: ((data[a][0][0].get("power.baseline.W"), data[a][1][0].get("power.baseline.W")) if w == "idle"
                               else watts("W")(a, w)), "W", [w for w, *_ in WORKLOADS]),
     "Watts over the workload's 30&nbsp;seconds: the cores, the GPU and the memory controller, which share the CPU "
     "package on these machines. The idle column is the idle session between the workloads."),
    ("per-frame", "Energy per frame on the screen",
     "",
     by_machine(joules("net_W"), "mJ", [w for w in LOAD if w != "menu"]),
     "Millijoules above the idle session for each frame the compositor put on the screen, per session and then the "
     "median: a compositor that shows more frames has its clients draw more, which the power alone counts against it. "
     "The idle machine's power is taken off first, or spreading it over more frames would make any compositor that "
     "shows more of them look cheaper. Not the menu: it shows 5 to 10 frames a second, and its energy is the shell "
     "building the menu, not frames."),
]
if psys:
    SECTIONS.append(("platform", "The whole machine's power",
                     f"      <p>{' and '.join(E(m['name']) for m in psys)} also have RAPL's platform zone (psys): what the "
                     "whole machine draws from its power supply, the screen and the rest of the board included. It is the "
                     "closest these figures come to a battery's.</p>\n",
                     by_machine(psys_watts, "W", [w for w, *_ in WORKLOADS], psys),
                     "Watts over the workload's 30&nbsp;seconds; the idle column is the idle session between the "
                     "workloads. The batteries were full or held at their charge limit throughout, so no charging is "
                     "counted."))
    SECTIONS.append(("platform-frame", "The whole machine's energy per frame",
                     "",
                     by_machine(joules("psys_net_W"), "mJ", [w for w in LOAD if w != "menu"], psys),
                     "Millijoules above the idle session per frame on the screen, as for the CPU package above."))

RAW_LINK = ("The raw data, every session's values and the scripts go to "
            "<a href=\"https://github.com/hegjon/hypoland/tree/master/docs/baseline\">docs/baseline</a> when the run ends."
            if PRELIMINARY else
            f'<a href="https://github.com/hegjon/hypoland/tree/master/{ENERGY_RUN}">Raw data, every session\'s values and the scripts</a>.')
PRELIMINARY_NOTE = (f"""
      <p>
        <strong>Preliminary:</strong> the run is still going, these are its first {SESSIONS} of each compositor per
        machine.
      </p>""" if PRELIMINARY else "")
nav = "".join(f'\n    <li><a href="#{sid}">{i + 2}</a></li>' for i, (sid, *_) in enumerate(SECTIONS))
nav += f'\n    <li><a href="#method">{len(SECTIONS) + 2}</a></li>'

page = f"""{head("Hypoland: energy", "The power the CPU package and the whole machine draw under Hypoland and under Hyprland " + HYPRLAND + f" on {len(rows)} machines, measured by RAPL: idle, video, toolkits, workspace switching and more.", "The power drawn under Hypoland and Hyprland " + HYPRLAND + f", on {len(rows)} machines.", "energy.html")}
<!-- Generated by scripts/web/energy.py from the run's values, do not edit by hand. -->
<nav class="bar" aria-label="Sections">
  <ul class="ws">
    <li><a class="on" href="#top">1</a></li>{nav}
  </ul>
  <div class="right">
    <span class="opt">energy</span>
    <span><a href="index.html">home</a></span>
    <span><a href="lab.html">lab</a></span>
    <span><a href="terminals.html">terminals</a></span>
    <span><a href="games.html">games</a></span>
    <span><a href="files.html">files</a></span>
    <span><a href="https://github.com/hegjon/hypoland">github</a></span>
  </div>
</nav>

<main class="desk" id="top">

  <section class="win full" aria-labelledby="t-energy">
    <h2 class="title" id="t-energy">Energy</h2>
    <div class="body">
      <p>
        What the processor draws under Hypoland and under stock Hyprland {HYPRLAND}, in Omarchy's session, on the
        {len(rows)} machines of <a href="lab.html">the lab</a> whose CPUs count their energy (RAPL): the {machine_names}.
        The same workloads under both, each 30&nbsp;seconds, with the power profile Omarchy picks on battery
        (<code>balanced</code>). Every cell is Hypoland / Hyprland: green where Hypoland is at least 5% better, red where
        it is at least 5% worse.
      </p>{PRELIMINARY_NOTE}
      <p>
        RAPL counts the CPU package: the cores, the integrated GPU and the memory controller, which is where a compositor
        spends its energy. The screen, the disk and the rest of the machine draw the same under both, so a battery lasts
        longer by a smaller share than these figures show; the whole machine is in the last table, on the two laptops
        that report it.
      </p>
    </div>
  </section>

{"".join(section(sid, title, intro, table, note) for sid, title, intro, table, note in SECTIONS)}
  <section class="win full" id="method" aria-labelledby="t-method">
    <h2 class="title" id="t-method">How it was measured</h2>
    <div class="body">
      <p>
        Medians of {SESSIONS} of each compositor per machine, {ENERGY_RUN_TEXT}.
        Each session started 60&nbsp;seconds before the first workload and ran every workload once, with the power over
        the workload read from RAPL's counters twice a second and an idle baseline of 10&nbsp;seconds before and after it.
        The machines ran on their chargers (RAPL does not need the battery), with the system's timers and Omarchy's update
        checks stopped. The workloads are those whose clients do the same work under any compositor: they draw at the
        screen's rate, at a video's, or by a timer or key repeat. Not the terminals' print loops or the games, which
        do more work under a compositor that takes their frames faster, so their energy says nothing about the
        compositor's (their frames are on <a href="terminals.html">terminals</a> and <a href="games.html">games</a>).
        The X200, the AMD desktop, the Galaxy Book and the Mac mini M1 have no RAPL and are not here.
        {" ".join(SKIP[k] for k in sorted(SKIP) if k[0] in data)}
        {RAW_LINK}
      </p>
      <div class="scroll"><table>
        <thead><tr><th>Workload</th><th>What it is</th></tr></thead>
        <tbody>
{workload_rows}
        </tbody>
      </table></div>
    </div>
  </section>
</main>

{FOOTER}
"""
if PRELIMINARY:
    page = page.replace('<meta name="theme-color"', '<meta name="robots" content="noindex">\n<meta name="theme-color"', 1)
open(OUT, "w").write(page)
print(f"wrote {OUT}: {len(rows)} machines ({len(psys)} with psys), {len(WORKLOADS)} workloads, {min(sessions)} to {max(sessions)} sessions")
