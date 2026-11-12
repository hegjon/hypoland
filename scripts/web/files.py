#!/usr/bin/env python3
# Writes web/files.html: the file managers of the benchmark (Nautilus, Flea, Folio) under Hypoland and stock Hyprland on
# every machine, one table per measure, from the night of 2026-11-11 (FILES_RUN), the first with Folio on every machine,
# so no number on the page is typed by hand. Run it again after a new baseline with the file managers, from anywhere:
# scripts/web/files.py
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from labdata import ROOT, HYPRLAND, MACHINES, values, cell, fmt, E, head, FOOTER

OUT = os.path.join(ROOT, "web", "files.html")
FILES_RUN = "docs/baseline/20261111-all-machines-r966-vs-hyprland-0.57.1"
FILES_RUN_TEXT = ("alternating from 2026-11-11 17:04 to 11-12 08:59, Hypoland master r966 (after 0.3.0) against Hyprland "
                  + HYPRLAND + "-2")

# name, version in the night, how it is made, its two workloads: scrolling and the other one
MANAGERS = [
    ("Nautilus", "51.1", "GNOME's, GTK&nbsp;4: GPU buffers drawn with Vulkan or OpenGL, on the X200 cairo into shared memory.",
     "nautilus-scroll", "nautilus"),
    ("Flea", "0.4.1", "Omarchy's file manager until 2026-11-10, a Quickshell window (Qt Quick), which picks Qt's Vulkan or "
     "OpenGL backend itself.", "flea-scroll", "flea"),
    ("Folio", "0.1.1 (0.2.0 on aarch64)", "Omarchy's file manager since 2026-11-10, C++ and Qt Quick.",
     "folio-scroll", "folio"),
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
    ("comp-mem", "The compositor's memory", "mem.{w}.Pss_kB", "MiB", True, 0,
     "Pss of the compositor at the same moment, with everything the session ran before it in the night's list."),
]

data = {m["alias"]: (values(m["alias"], "hypoland", FILES_RUN), values(m["alias"], "hyprland", FILES_RUN))
        for m in MACHINES if os.path.isdir(os.path.join(ROOT, FILES_RUN, m["alias"], "hypoland"))}
rows = [m for m in MACHINES if m["alias"] in data]

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
            (hv, _), (sv, _) = data[m["alias"]]
            cells = ""
            for name, _, _, *ws in MANAGERS:
                w = ws[which]
                ho, so = opened(hv, w), opened(sv, w)
                h, s = value(hv, key, w, unit), value(sv, key, w, unit)
                # the file manager opened its window under one compositor only
                if ho and so is False and h is not None:
                    cells += f'<td class="yes">{fmt(h, unit)} / no window</td>'
                elif so and ho is False and s is not None:
                    cells += f'<td class="no">no window / {fmt(s, unit)}</td>'
                else:
                    cells += cell(h if ho else None, s if so else None, unit, lower)
            name = E(m["name"]) + (' <span class="opt">(headless)</span>' if m["alias"] == "macmini-intel" else "")
            body.append(f"          <tr><td>{name}</td>{cells}</tr>")
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

sessions = [min(data[m["alias"]][0][1], data[m["alias"]][1][1]) for m in rows]
manager_rows = "\n".join(f"          <tr><td>{n}</td><td>{E(v)}</td><td>{d}</td></tr>" for n, v, d, *_ in MANAGERS)
nav = "".join(f'\n    <li><a href="#{sid}">{i + 2}</a></li>' for i, (sid, *_) in enumerate(MEASURES))
index = "\n".join(f'          <li><a href="#{sid}">{E(title)}</a></li>' for sid, title, *_ in MEASURES)

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
      <ul>
{index}
      </ul>
      <p class="note">
        Medians of {min(sessions)} to {max(sessions)} fresh sessions of each compositor per machine, {FILES_RUN_TEXT}.
        Folio 0.1.1 and 0.2.0 do not scroll the list to the cursor on Down
        (<a href="https://github.com/omacom/folio/pull/18">folio#18</a>): the cursor walks off the bottom and the view
        stays, so for Folio the scrolling tables measure the cursor and the details pane redrawn, and do not compare with
        the other two. Flea opens no window on the X200 (it needs more than OpenGL&nbsp;2.1) and is not installed on the
        Mac mini M1, Folio is not installed on the Samsung. Under Hyprland Nautilus opened no window on the X200 in that
        night. On the X200 Hyprland runs with Omarchy's GLES&nbsp;3 override
        (<a href="https://github.com/omacom/omarchy/pull/14764">omarchy#14764</a>), which the file managers get too. The
        Mac mini 2014 had no monitor that night and ran on a headless output; the Mac mini M1's display driver reports
        no page flips, so it has no frames on the screen.
        <a href="https://github.com/hegjon/hypoland/tree/master/{FILES_RUN}">Raw data, every session's values and the scripts</a>.
      </p>
    </div>
  </section>

{tables()}
</main>

{FOOTER}
"""
open(OUT, "w").write(page)
print(f"wrote {OUT}: {len(MANAGERS)} file managers, {len(MEASURES)} measures, {len(rows)} machines")
