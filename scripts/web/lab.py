#!/usr/bin/env python3
# Writes web/lab.html, the page about the test machines: the hardware table (the facts below), and every machine's
# numbers against stock Hyprland from the regression baseline (docs/baseline/20261027-all-machines-r761-vs-hyprland-0.56.2,
# values.txt and raw.txt per machine and compositor), so no number on the page is typed by hand. Run it again after a
# new baseline, from anywhere: scripts/web/lab.py
import html, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASELINE = "docs/baseline/20261027-all-machines-r761-vs-hyprland-0.56.2"
OUT = os.path.join(ROOT, "web", "lab.html")

# alias, machine, year, CPU, GPU, Mesa driver and GLES level, screen, RAM, what it stands for; baseline: has a column
MACHINES = [
    dict(alias="x200", name="Lenovo ThinkPad X200", year=2008, cpu="Core 2 Duo P8400, 2 cores", gpu="Intel GMA 4500MHD (GM45, Gen 4.5)",
         driver="crocus, GLES 2.0 only", screen="1280x800", ram="6 GB", role="The target and the main test machine: stock Hyprland does not start on it.", baseline=True),
    dict(alias="macmini-intel", name="Apple Mac mini Late 2014", year=2014, cpu="Core i5-4260U, 4 threads", gpu="Intel HD Graphics 5000 (Haswell GT3)",
         driver="crocus, GLES 3.0", screen="1920x1200 over HDMI", ram="4 GB", role="Haswell, the last crocus generation: Mesa copies shm windows through a tiled temporary here.", baseline=True),
    dict(alias="chromebook", name="Dell Chromebook 11 3120", year=2015, cpu="Celeron N2840, 2 cores", gpu="Intel Bay Trail",
         driver="crocus, GLES 3.0", screen="1366x768", ram="4 GB, 16 GB eMMC", role="The low end with GLES 3: two slow cores, little memory, wifi only.", baseline=True),
    dict(alias="t550", name="Lenovo ThinkPad T550", year=2015, cpu="Core i5-5300U, 4 threads", gpu="Intel HD Graphics 5500 (Broadwell)",
         driver="iris, GLES 3.2", screen="1920x1080", ram="16 GB", role="The second machine, a plain iris laptop; the comparison with stock Hyprland on GLES 3 hardware started here.", baseline=True),
    dict(alias="xps", name="Dell XPS 13 9343", year=2015, cpu="Core i5-5300U, 4 threads", gpu="Intel HD Graphics 5500 (Broadwell)",
         driver="iris, GLES 3.2", screen="3200x1800 at scale 2", ram="8 GB", role="The high-resolution one: four times the pixels of the X200 on the same class of GPU.", baseline=True),
    dict(alias="t460s", name="Lenovo ThinkPad T460s", year=2016, cpu="Core i7-6600U, 4 threads", gpu="Intel HD Graphics 520 (Skylake)",
         driver="iris, GLES 3.2", screen="1920x1080 at scale 1.5", ram="20 GB", role="The fractional scale, and the only Skylake: its scanout buffers are render compressed.", baseline=True),
    dict(alias="t490", name="Lenovo ThinkPad T490", year=2019, cpu="Core i5-8265U, 8 threads", gpu="Intel UHD Graphics 620 (Whiskey Lake)",
         driver="iris, GLES 3.2", screen="1920x1080", ram="8 GB", role="Joined on 2026-10-30, the newest Intel GPU of the lab; no baseline yet.", baseline=False),
    dict(alias="lianli", name="Desktop, AMD A8-6600K APU", year=2013, cpu="A8-6600K, 4 cores", gpu="AMD Radeon HD 8570D (TeraScale 3)",
         driver="r600, GLES 3.1", screen="1920x1200", ram="8 GB", role="The AMD machine: the r600 driver with legacy modesetting.", baseline=True),
    dict(alias="galaxybook", name="Samsung Galaxy Book4 Edge 14\"", year=2024, cpu="Snapdragon X Elite, 12 cores, aarch64", gpu="Qualcomm Adreno X1-85",
         driver="freedreno, GLES 3.2", screen="2880x1800 at scale 2, 120 Hz", ram="16 GB", role="The aarch64 machine, with its own package build; 120 Hz.", baseline=True),
]
RETIRED = "An HP EliteBook 8560p (2011, Radeon HD 6470M, r600) was in the lab from 2026-10-22 until its GPU failed on 2026-10-27."

# key in values.txt, label, unit, whether lower is better, scale
METRICS = [
    ("cpu.gpu-client.percent", "GPU client at 60 fps", "%", True, 1),
    ("cpu.terminal-scroll.percent", "terminal scrolling fast", "%", True, 1),
    ("cpu.shm-fullwindow.percent", "Chromium in a full window", "%", True, 1),
    ("cpu.workspace-switch.percent", "workspace switching", "%", True, 1),
    ("mem.start.Pss_kB", "memory (PSS), 60 s after the start", "MiB", True, 1 / 1024),
    ("fps.gtk3-scroll.screen", "frames on the screen, GTK 3 scrolling", "fps", False, 1),
    ("latency.workspace-switch.focus_ms", "a focus change shown", "ms", True, 1),
]

def values(alias, compositor):
    d = os.path.join(ROOT, BASELINE, alias, compositor)
    v = {}
    for line in open(os.path.join(d, "values.txt")):
        parts = line.split()
        if len(parts) >= 2:
            try: v[parts[0]] = float(parts[1])
            except ValueError: pass
    sessions = sum(1 for line in open(os.path.join(d, "raw.txt")) if re.match(r"@ \d+ cpu\.gpu-client\.percent ", line))
    return v, sessions

def fmt(x, unit):
    if unit == "%": return f"{x:.1f}%"
    if unit == "MiB": return f"{x:.0f} MiB"
    if unit == "fps": return f"{x:.0f} fps"
    return f"{x:.1f} ms"

def cell(h, s, unit, lower_better):
    if h is None or s is None: return "<td>&ndash;</td>"
    better = (h <= s * 0.95) if lower_better else (h >= s * 1.05)
    worse = (h >= s * 1.05) if lower_better else (h <= s * 0.95)
    cls = ' class="yes"' if better else (' class="no"' if worse else "")
    return f"<td{cls}>{fmt(h, unit)} / {fmt(s, unit)}</td>"

E = html.escape
rows_hw = []
for m in MACHINES:
    rows_hw.append(f"          <tr><td>{E(m['name'])}</td><td>{m['year']}</td><td>{E(m['cpu'])}</td><td>{E(m['gpu'])}<br><code>{E(m['driver'])}</code></td>"
                   f"<td>{E(m['screen'])}</td><td>{E(m['ram'])}</td><td>{E(m['role'])}</td></tr>")

rows_num, sessions = [], {}
for m in MACHINES:
    if not m["baseline"]: continue
    hv, hs = values(m["alias"], "hypoland")
    sv, ss = values(m["alias"], "hyprland")
    sessions[m["alias"]] = (hs, ss)
    cells = "".join(cell(hv.get(k) * sc if hv.get(k) is not None else None, sv.get(k) * sc if sv.get(k) is not None else None, unit, lower)
                    for k, _, unit, lower, sc in METRICS)
    rows_num.append(f"          <tr><td>{E(m['name'])}</td>{cells}</tr>")
heads = "".join(f"<th>{E(label)}</th>" for _, label, _, _, _ in METRICS)
smin = min(min(v) for v in sessions.values()); smax = max(max(v) for v in sessions.values())

page = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Hypoland: the lab</title>
<meta name="description" content="The test machines Hypoland is measured on, from a 2008 ThinkPad X200 to a Snapdragon X Elite laptop, and every machine's numbers against stock Hyprland.">
<meta name="theme-color" content="#efe6d2">
<meta property="og:site_name" content="Hypoland">
<meta property="og:title" content="Hypoland: the lab">
<meta property="og:description" content="The test machines Hypoland is measured on, and every machine's numbers against stock Hyprland.">
<meta property="og:type" content="website">
<meta property="og:url" content="https://hypoland.org/lab.html">
<meta property="og:image" content="https://hypoland.org/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<link rel="canonical" href="https://hypoland.org/lab.html">
<meta name="robots" content="noindex">
<link rel="icon" type="image/svg+xml" href="icon.svg">
<link rel="icon" type="image/png" sizes="32x32" href="favicon.png">
<link rel="stylesheet" href="style.css">
</head>
<body>

<!-- Generated by scripts/web/lab.py from the hardware facts in it and the baseline's values, do not edit by hand. -->
<nav class="bar" aria-label="Sections">
  <ul class="ws">
    <li><a class="on" href="#top">1</a></li>
    <li><a href="#numbers">2</a></li>
    <li><a href="#method">3</a></li>
  </ul>
  <div class="right">
    <span class="opt">the lab</span>
    <span><a href="index.html">home</a></span>
    <span><a href="https://github.com/hegjon/hypoland">github</a></span>
  </div>
</nav>

<main class="desk" id="top">

  <section class="win full" aria-labelledby="t-machines">
    <h2 class="title" id="t-machines">lshw: the test machines</h2>
    <div class="body">
      <p>
        Hypoland is measured on real machines, each with Omarchy installed and its full session running, reached over
        ssh from one desktop. The oldest one is the target; the others make sure that what helps the X200 costs nothing
        on the GPUs and drivers people actually have.
      </p>
      <div class="scroll"><table>
        <thead><tr><th>Machine</th><th>Year</th><th>CPU</th><th>GPU, Mesa driver</th><th>Screen</th><th>RAM</th><th>What it stands for</th></tr></thead>
        <tbody>
{chr(10).join(rows_hw)}
        </tbody>
      </table></div>
      <p class="note">
        {E(RETIRED)} An Apple Mac mini M1 is being set up for Omarchy on Apple Silicon. Not in the lab: NVIDIA
        (<code>nouveau</code>), AMD GCN and newer (<code>radeonsi</code>, <code>amdgpu</code>), and the two other Intel
        generations that stop at GLES 2.0, GMA X3100 (965GM) and Ironlake. Reports from any of them are welcome.
      </p>
    </div>
  </section>

  <section class="win full" id="numbers" aria-labelledby="t-numbers">
    <h2 class="title" id="t-numbers">bench: Hypoland against Hyprland 0.56.2, per machine</h2>
    <div class="body">
      <div class="scroll"><table>
        <thead><tr><th>Hypoland / Hyprland 0.56.2</th>{heads}</tr></thead>
        <tbody>
{chr(10).join(rows_num)}
        </tbody>
      </table></div>
      <p class="note">
        Compositor CPU in percent of one core, medians of {smin} to {smax} fresh sessions of each compositor per machine,
        alternating through the night of 2026-10-27 (Hypoland r761). Green where Hypoland is at least 5% better, red
        where it is at least 5% worse. On the X200, Hyprland ran with Omarchy's GLES&nbsp;3 override
        (<a href="https://github.com/omacom/omarchy/pull/14764">omarchy#14764</a>), since it does not start there
        otherwise. The frames are the compositor's own page flips; the Galaxy Book's screen runs at 120 Hz. Hyprland
        drives the Mac mini's and the Galaxy Book's small moving windows cheaper (not shown); the memory holds the
        shell's shared pages too. Later builds improved on these numbers: terminals and Qt windows are shown without a
        copy and panels are drawn only where they have pixels since 2026-10-29.
        <a href="https://github.com/hegjon/hypoland/tree/master/{BASELINE}">Raw data, every session's values and the scripts</a>.
      </p>
    </div>
  </section>

  <section class="win third" id="method" aria-labelledby="t-method">
    <h2 class="title" id="t-method">measure.sh: how it is measured</h2>
    <div class="body">
      <p>
        Every number comes from a fresh session: the machine's display manager is restarted, the desktop settles for
        a minute, then the benchmark runs its workloads with the compositor's real clients (foot, Alacritty, Chromium,
        GTK&nbsp;3 and 4, Qt&nbsp;Quick, Tk through Xwayland, Omarchy's shell). Keys and pointer motions come from a
        uinput device, the same path as a real keyboard. Latencies are the time from an input event to the first
        screen-capture frame that shows its effect. Two builds alternate through a night, so a drift of the machine
        hits both the same.
      </p>
    </div>
  </section>

  <section class="win third" aria-labelledby="t-tools">
    <h2 class="title" id="t-tools">perf: what else is looked at</h2>
    <div class="body">
      <ul class="pixel-list">
        <li>GPU time per frame, by the compositor's own pass profile and the i915 busy counter</li>
        <li>Power, by RAPL or the battery's discharge rate, net of an idle baseline</li>
        <li>Memory: PSS, heap, threads and the GPU buffers the compositor holds</li>
        <li>Profiles with <code>perf</code> and the kernel's and Mesa's symbols</li>
        <li>Every machine's journal and kernel log stream to the desktop, so a machine that dies leaves its last words</li>
      </ul>
    </div>
  </section>

  <section class="win third" aria-labelledby="t-data">
    <h2 class="title" id="t-data">ls docs/baseline: the data</h2>
    <div class="body">
      <ul class="pixel-list">
        <li><a href="https://github.com/hegjon/hypoland/tree/master/docs/baseline">docs/baseline</a>: every comparison with stock Hyprland, with the raw values and the scripts that made them</li>
        <li><a href="https://github.com/hegjon/hypoland/tree/master/scripts/bench">scripts/bench</a>: the benchmark, its workloads and clients</li>
        <li><a href="https://github.com/hegjon/hypoland/blob/master/AGENTS.md">AGENTS.md</a>: the engineering notes, with what was tried, measured and dropped</li>
        <li><a href="https://github.com/hegjon/hypoland/blob/master/CHANGELOG.md">CHANGELOG.md</a>: the changes per release with their measured effect</li>
      </ul>
    </div>
  </section>

</main>

<footer>
  <p>
    <img src="favicon.png" width="16" height="16" alt="">
    Hypoland is BSD 3-Clause licensed, like Hyprland.
    <a href="https://github.com/hegjon/hypoland">Source</a> &middot;
    <a href="https://github.com/hegjon/hypoland/releases">Releases</a> &middot;
    <a href="https://github.com/hegjon/hypoland/issues">Issues</a> &middot;
    <a href="https://github.com/hegjon/hypoland/blob/master/LICENSE">License</a>
  </p>
  <p>This page has no JavaScript, no web fonts and no trackers. It should load fine on an X200 too.</p>
</footer>

</body>
</html>
"""
open(OUT, "w").write(page)
print(f"wrote {OUT}: {len(rows_hw)} machines, {len(rows_num)} with numbers, {smin} to {smax} sessions each")
