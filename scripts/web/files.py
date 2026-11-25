#!/usr/bin/env python3
# Writes web/files.html: the file managers of the benchmark (Flea, Folio) under Hypoland and stock Hyprland on every
# machine, one table per measure, from the lab page's runs (labdata.py), so no number on the page is typed by hand. Since
# 2026-11-25 only the Hypoland 0.4.0 release against Hyprland 0.57.2, so Nautilus is gone from the page: its numbers came
# from the night of 2026-11-11 (r966 against 0.57.1, docs/baseline/20261111-all-machines-r966-vs-hyprland-0.57.1), the last
# with Nautilus on the machines (Omarchy's update of 2026-11-13 removed it). Run it again after a new baseline with the
# file managers, from anywhere: scripts/web/files.py
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from labdata import ROOT, HYPRLAND, RUN, TWO_NIGHTS, RAW, MACHINES, values, has, sessions_text, cell, fmt, E, head, FOOTER, bar

OUT = os.path.join(ROOT, "web", "files.html")
# name, version in the night, how it is made, its two workloads: scrolling and the other one, and where its numbers come
# from: None for the lab page's nights, or a baseline of their own
MANAGERS = [
    ("Flea", "0.4.3", "A keyboard-first file manager for Omarchy, written in Rust with GPUI (the Zed editor's UI "
     "toolkit) and drawn on the GPU through wgpu.", "flea-scroll", "flea", None),
    ("Folio", "0.6.1 (0.7.1 on the MSI Claw)", "Omarchy's own file manager, written in C++ with Qt Quick.",
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
     "Folio shows a folder of icons in its grid with the window's fullscreen toggled twice a second, Flea "
     "pages through 25000 files with four keys a second. The compositor's CPU per frame on the screen."),
    ("other-fps", "Icons and paging: frames on the screen", "fps.{w}.screen", "fps", False, 1,
     "The compositor's page flips a second: each fullscreen toggle animates the window, a page of Flea is a frame or two."),
    ("client-mem", "The file manager's memory", "mem.{w}.clients_Pss_kB", "MiB", True, 0,
     "Pss of the file manager's processes at the end of the scrolling, with the 5000 files listed and the window open. "
     "The file manager's own memory, which the compositor hardly changes: it tells the three apart."),
]

# the machines with the lab page's numbers; per machine and source (None: the lab page's runs) the Hypoland and Hyprland
# values
rows = [m for m in MACHINES if m["baseline"] and has(m["alias"])]
data = {m["alias"]: {None: (values(m["alias"], "hypoland"), values(m["alias"], "hyprland"))} for m in rows}
# cells left empty: on the Turbo-X's 1 GB most of the file manager sits in swap, which PSS does not count
BLANK = {("turbox", "client-mem")}

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
                if (m["alias"], sid) in BLANK:
                    ho = so = None
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
manager_rows = "\n".join(f"          <tr><td>{n}</td><td>{E(v)}</td><td>{d}</td></tr>" for n, v, d, *_ in MANAGERS)
nav = [(sid, i + 2) for i, (sid, *_) in enumerate(MEASURES)]

page = f"""{head("Hypoland: file managers", "Flea and Folio scrolling a folder of 5000 files under Hypoland and under Hyprland " + HYPRLAND + f" on {len(rows)} machines: the compositor's CPU, its frames and the memory.", "Flea and Folio under Hypoland and Hyprland " + HYPRLAND + f", on {len(rows)} machines.", "files.html")}
<!-- Generated by scripts/web/files.py from the night's values, do not edit by hand. -->
{bar(nav, "files.html")}

<main class="desk" id="top">

  <section class="win full" aria-labelledby="t-files">
    <h2 class="title" id="t-files">Flea, Folio</h2>
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
        Medians of {sessions_text(sessions, 1)} per machine, {RUN}. {TWO_NIGHTS} Flea opens no window on those two (it
        needs more than OpenGL&nbsp;2.1), where Hyprland runs with Omarchy's GLES&nbsp;3 override (<a
        href="https://github.com/omacom/omarchy/pull/14764">omarchy#14764</a>). The Mac mini M1 reports no page flips;
        the Turbo-X's file manager is mostly in swap, so it has no memory cell. Nautilus left Omarchy on 2026-11-13.
        {RAW}
      </p>
    </div>
  </section>

{tables()}
</main>

{FOOTER}
"""
open(OUT, "w").write(page)
print(f"wrote {OUT}: {len(MANAGERS)} file managers, {len(MEASURES)} measures, {len(rows)} machines")
