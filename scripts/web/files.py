#!/usr/bin/env python3
# Writes web/files.html: the file managers of the benchmark (Nautilus, Flea, Folio) under Hypoland and stock Hyprland on
# every machine, one table per measure, so no number on the page is typed by hand: Flea and Folio from the lab page's
# night (labdata.py, since 2026-11-15), Nautilus from the night of 2026-11-11 (NAUTILUS_RUN), the last one with Nautilus
# on the machines (Omarchy's update of 2026-11-13 removed it). From 2026-11-13 to 15 Nautilus and Flea came from the lab
# page's two nights and Folio from the night of 2026-11-11 alone; all three from there before. Run it again after a new
# baseline with the file managers, from anywhere: scripts/web/files.py
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from labdata import ROOT, HYPRLAND, RUN, TWO_NIGHTS, RAW, MACHINES, values, has, sessions_text, cell, fmt, E, head, FOOTER

OUT = os.path.join(ROOT, "web", "files.html")
# Omarchy's update of 2026-11-13 removed Nautilus from the machines: its numbers come from the last night that had it,
# where the two compositors alternated too (Hypoland r966, Hyprland 0.57.1-2)
NAUTILUS_RUN = "docs/baseline/20261111-all-machines-r966-vs-hyprland-0.57.1"
NAUTILUS_RUN_TEXT = ("the night of 2026-11-11 to 12, alternating Hypoland master r966 with Hyprland 0.57.1-2, the last night "
                     "with Nautilus on the machines (Omarchy's update of 2026-11-13 removed it)")

# name, version in the night, how it is made, its two workloads: scrolling and the other one, and where its numbers come
# from: None for the lab page's nights, or a baseline of their own
MANAGERS = [
    ("Nautilus", "51.1", "GNOME's file manager, GTK&nbsp;4: drawn with Vulkan or OpenGL into GPU buffers, on the X200 "
     "with cairo into shared memory.", "nautilus-scroll", "nautilus", NAUTILUS_RUN),
    ("Flea", "0.4.2", "A keyboard-first file manager for Omarchy, written in Rust with GPUI (the Zed editor's UI "
     "toolkit) and drawn on the GPU through wgpu.", "flea-scroll", "flea", None),
    ("Folio", "2e2a716 (after 0.5.0)", "Omarchy's own file manager, written in C++ with Qt Quick.",
     "folio-scroll", "folio", None),
]

# id, title, key pattern ({w} is the workload), unit, whether lower is better, which workload (0 scrolling, 1 the other),
# what it says; memory is in kB and shown in MiB
MEASURES = [
    ("scroll-cpu", "Scrolling: the compositor's CPU", "cpu.{w}.percent", "%", True, 0,
     "Percent of one core over the 12&nbsp;s of scrolling: the compositor alone, all its threads."),
    ("scroll-frame", "Scrolling: the compositor's CPU per frame", "cpu.{w}.ms_per_frame", "ms/frame", True, 0,
     "The same per frame the compositor put on the screen, so a compositor that shows more frames is not read as one "
     "that costs more."),
    ("scroll-fps", "Scrolling: frames on the screen", "fps.{w}.screen", "fps", False, 0,
     "The compositor's page flips a second. The file manager moves its cursor 40 times a second (the key repeat of "
     "Omarchy's session), so about 40 is all there is to show; Folio redraws more often than that."),
    ("other-frame", "Icons and paging: the compositor's CPU per frame", "cpu.{w}.ms_per_frame", "ms/frame", True, 1,
     "Nautilus and Folio show a folder of icons in their grid with the window's fullscreen toggled twice a second, Flea "
     "pages through 25000 files with four keys a second. The compositor's CPU per frame on the screen."),
    ("other-fps", "Icons and paging: frames on the screen", "fps.{w}.screen", "fps", False, 1,
     "The compositor's page flips a second: each fullscreen toggle animates the window, a page of Flea is a frame or two."),
    ("client-mem", "The file manager's memory", "mem.{w}.clients_Pss_kB", "MiB", True, 0,
     "Pss of the file manager's processes at the end of the scrolling, with the 5000 files listed and the window open. "
     "The file manager's own memory, which the compositor hardly changes: it tells the three apart."),
]

# the machines with the lab page's numbers; per machine and source (None or NAUTILUS_RUN) the Hypoland and Hyprland
# values, empty for a machine that joined after NAUTILUS_RUN
rows = [m for m in MACHINES if m["baseline"] and has(m["alias"])]
def nautilus_values(alias):
    if not os.path.isdir(os.path.join(ROOT, NAUTILUS_RUN, alias, "hyprland")):
        return ({}, 0), ({}, 0)
    return values(alias, "hypoland", NAUTILUS_RUN), values(alias, "hyprland", NAUTILUS_RUN)
data = {m["alias"]: {None: (values(m["alias"], "hypoland"), values(m["alias"], "hyprland")),
                     NAUTILUS_RUN: nautilus_values(m["alias"])}
        for m in rows}

def counts_flips(v):
    # the Mac mini M1's display driver reports no page flips: no frames on the screen to count there
    return v.get("fps.gpu-client.screen", 0) >= 1

def opened(v, w):
    """Whether the workload's window was there: measured, and where page flips are counted, drawn."""
    if f"cpu.{w}.percent" not in v:
        return None
    return not counts_flips(v) or v.get(f"fps.{w}.screen", 0) >= 1

def value(v, key, w, unit):
    x = v.get(key.format(w=w))
    return x / 1024 if x is not None and unit == "MiB" else x

def tables():
    out = []
    for sid, title, key, unit, lower, which, text in MEASURES:
        body = []
        for m in rows:
            cells = ""
            for name, _, _, scroll, other, run in MANAGERS:
                (hv, _), (sv, _) = data[m["alias"]][run]
                w = (scroll, other)[which]
                ho, so = opened(hv, w), opened(sv, w)
                h, s = value(hv, key, w, unit), value(sv, key, w, unit)
                # the file manager opened its window under one compositor only
                if ho and so is False and h is not None:
                    cells += f'<td class="yes">{fmt(h, unit)} / no window</td>'
                elif so and ho is False and s is not None:
                    cells += f'<td class="no">no window / {fmt(s, unit)}</td>'
                else:
                    cells += cell(h if ho else None, s if so else None, unit, lower)
            body.append(f"          <tr><td>{E(m['name'])}</td>{cells}</tr>")
        heads = "".join(f"<th>{n}</th>" for n, *_ in MANAGERS)
        out.append(f"""  <section class="win full" id="{sid}" aria-labelledby="t-{sid}">
    <h2 class="title" id="t-{sid}">{E(title)}</h2>
    <div class="body">
      <div class="scroll"><table>
        <thead><tr><th>Hypoland / Hyprland {HYPRLAND}</th>{heads}</tr></thead>
        <tbody>
{chr(10).join(body)}
        </tbody>
      </table></div>
      <p class="note">{text}</p>
    </div>
  </section>
""")
    return "\n".join(out)

sessions = [(data[m["alias"]][None][0][1], data[m["alias"]][None][1][1]) for m in rows]
nautilus_sessions = [min(data[m["alias"]][NAUTILUS_RUN][0][1], data[m["alias"]][NAUTILUS_RUN][1][1]) for m in rows
                     if data[m["alias"]][NAUTILUS_RUN][0][1]]
nautilus_missing = [m["name"] for m in rows if not data[m["alias"]][NAUTILUS_RUN][0][1]]
manager_rows = "\n".join(f"          <tr><td>{n}</td><td>{E(v)}</td><td>{d}</td></tr>" for n, v, d, *_ in MANAGERS)
nav = "".join(f'\n    <li><a href="#{sid}">{i + 2}</a></li>' for i, (sid, *_) in enumerate(MEASURES))

page = f"""{head("Hypoland: file managers", "Nautilus, Flea and Folio scrolling a folder of 5000 files under Hypoland and under Hyprland " + HYPRLAND + f" on {len(rows)} machines: the compositor's CPU, its frames and the memory.", "Nautilus, Flea and Folio under Hypoland and Hyprland " + HYPRLAND + f", on {len(rows)} machines.", "files.html")}
<!-- Generated by scripts/web/files.py from the night's values, do not edit by hand. -->
<nav class="bar" aria-label="Sections">
  <ul class="ws">
    <li><a class="on" href="#top">1</a></li>{nav}
  </ul>
  <div class="right">
    <span class="opt">files</span>
    <span><a href="index.html">home</a></span>
    <span><a href="lab.html">lab</a></span>
    <span><a href="terminals.html">terminals</a></span>
    <span><a href="games.html">games</a></span>
    <span><a href="https://github.com/hegjon/hypoland">github</a></span>
  </div>
</nav>

<main class="desk" id="top">

  <section class="win full" aria-labelledby="t-files">
    <h2 class="title" id="t-files">Nautilus, Flea, Folio</h2>
    <div class="body">
      <p>
        Each file manager opens a folder of 5000 empty files in its list view, and the Down key is held for 12 seconds
        on a virtual keyboard: the compositor passes on the one press and the file manager repeats it, about 480 files.
        On every machine of <a href="lab.html">the lab</a>, in Omarchy's session, under Hypoland and under stock
        Hyprland {HYPRLAND}. Every cell is Hypoland / Hyprland: green where Hypoland is at least 5% better, red where it
        is at least 5% worse; a dash where the file manager does not run or there is nothing to count.
      </p>
      <div class="scroll"><table>
        <thead><tr><th>File manager</th><th>Version</th><th>What it is</th></tr></thead>
        <tbody>
{manager_rows}
        </tbody>
      </table></div>
      <p class="note">
        Flea and Folio: medians of {sessions_text(sessions, 1)} per machine, {RUN}. {TWO_NIGHTS} Nautilus: medians of
        {min(nautilus_sessions)} to {max(nautilus_sessions)} fresh sessions of each compositor per machine,
        {NAUTILUS_RUN_TEXT}; {E(" and ".join(nautilus_missing)) or "no machine"} joined after it, and the Mac mini 2014
        ran on a headless output then. Folio is commit 2e2a716 (<a
        href="https://github.com/omacom/folio/pull/79">folio#79</a>, after 0.5.0), built on every machine, which scrolls
        the list to the cursor on Down. The Galaxy Book's and the Mac mini 2014's night had Omarchy's Folio 0.4.0, which
        does not (<a href="https://github.com/omacom/folio/pull/18">folio#18</a>): the cursor walks off the bottom and the
        view stays, so their Folio scrolling cells measure the cursor and the details pane redrawn. Flea opens no window on the X200 (it needs more than OpenGL&nbsp;2.1) and is not installed on the
        Mac mini M1. Under Hyprland Nautilus opened no window on the X200 in its night. On the X200 Hyprland runs with
        Omarchy's GLES&nbsp;3 override (<a href="https://github.com/omacom/omarchy/pull/14764">omarchy#14764</a>), which
        the file managers get too. The Mac mini M1's display driver reports no page flips, so it has no frames on the
        screen.
        {RAW} Nautilus's night: <a href="https://github.com/hegjon/hypoland/tree/master/{NAUTILUS_RUN}">{NAUTILUS_RUN.split("/")[-1]}</a>.
      </p>
    </div>
  </section>

{tables()}
</main>

{FOOTER}
"""
open(OUT, "w").write(page)
print(f"wrote {OUT}: {len(MANAGERS)} file managers, {len(MEASURES)} measures, {len(rows)} machines")
