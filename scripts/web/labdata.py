# The facts and helpers the generated pages about the lab share (scripts/web/lab.py, terminals.py, games.py): the
# machines, the baseline their numbers come from, its values, and the page's head and footer.
import html, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASELINE = "docs/baseline/20261110-all-machines-r957-vs-hyprland-0.57.1"
HYPRLAND = "0.57.1"
# the run the numbers come from, for the pages' notes
RUN = "alternating from 2026-11-10 23:09 to 11-11 07:30, Hypoland master r957 (after 0.3.0) against Hyprland " + HYPRLAND + "-2"

# alias, machine, year, CPU, GPU, Mesa driver and GLES level, screen, RAM, what it stands for; baseline: has a column
MACHINES = [
    dict(alias="x200", name="Lenovo ThinkPad X200", year=2008, cpu="Core 2 Duo P8400, 2 cores", gpu="Intel GMA 4500MHD (GM45, Gen 4.5)",
         driver="crocus, GLES 2.0 only", screen="1280x800", ram="6 GB", role="The target and the main test machine: stock Hyprland does not start on it.", baseline=True),
    dict(alias="macmini-intel", name="Apple Mac mini Late 2014", year=2014, cpu="Core i5-4260U, 4 threads", gpu="Intel HD Graphics 5000 (Haswell GT3)",
         driver="crocus, GLES 3.0", screen="1920x1200 over HDMI", ram="4 GB", role="Haswell, the last crocus generation: Mesa copies shm windows through a tiled temporary here.", baseline=False,
         nodata="had no monitor in the night of the baseline (its HDMI went to a KVM), so its numbers are left out"),
    dict(alias="chromebook", name="Dell Chromebook 11 3120", year=2015, cpu="Celeron N2840, 2 cores", gpu="Intel Bay Trail",
         driver="crocus, GLES 3.0", screen="1366x768", ram="4 GB, 16 GB eMMC", role="The low end with GLES 3: two slow cores, little memory, wifi only.", baseline=True),
    dict(alias="t550", name="Lenovo ThinkPad T550", year=2015, cpu="Core i5-5300U, 4 threads", gpu="Intel HD Graphics 5500 (Broadwell)",
         driver="iris, GLES 3.2", screen="1920x1080", ram="16 GB", role="The second machine, a plain iris laptop; the comparison with stock Hyprland on GLES 3 hardware started here.", baseline=True),
    dict(alias="xps", name="Dell XPS 13 9343", year=2015, cpu="Core i5-5300U, 4 threads", gpu="Intel HD Graphics 5500 (Broadwell)",
         driver="iris, GLES 3.2", screen="3200x1800 at scale 2", ram="8 GB", role="The high-resolution one: four times the pixels of the X200 on the same class of GPU.", baseline=True),
    dict(alias="t460s", name="Lenovo ThinkPad T460s", year=2016, cpu="Core i7-6600U, 4 threads", gpu="Intel HD Graphics 520 (Skylake)",
         driver="iris, GLES 3.2", screen="1920x1080 at scale 1.5", ram="20 GB", role="The fractional scale, and the only Skylake: its scanout buffers are render compressed.", baseline=True),
    dict(alias="t490", name="Lenovo ThinkPad T490", year=2019, cpu="Core i5-8265U, 8 threads", gpu="Intel UHD Graphics 620 (Whiskey Lake)",
         driver="iris, GLES 3.2", screen="1920x1080", ram="8 GB", role="Joined on 2026-10-30, the newest Intel GPU of the lab.", baseline=True),
    dict(alias="lianli", name="Desktop, AMD A8-6600K APU", year=2013, cpu="A8-6600K, 4 cores", gpu="AMD Radeon HD 8570D (TeraScale 3)",
         driver="r600, GLES 3.1", screen="1920x1200", ram="8 GB", role="The AMD machine: the r600 driver with legacy modesetting.", baseline=True),
    dict(alias="galaxybook", name="Samsung Galaxy Book4 Edge 14\"", year=2024, cpu="Snapdragon X Elite, 12 cores, aarch64", gpu="Qualcomm Adreno X1-85",
         driver="freedreno, GLES 3.2", screen="2880x1800 at scale 2, 120 Hz", ram="16 GB", role="The aarch64 machine, with its own package build; 120 Hz.", baseline=True),
    dict(alias="samsung-i5", name="Samsung Series 7 Ultra (NP730U3E)", year=2013, cpu="Core i5-3337U, 4 threads", gpu="Intel HD Graphics 4000 (Ivy Bridge)",
         driver="crocus, GLES 3.0", screen="1920x1080", ram="4 GB", role="Joined on 2026-10-31, Ivy Bridge: the crocus generation between Bay Trail and Haswell.", baseline=True),
    dict(alias="macmini-m1", name="Apple Mac mini M1", year=2020, cpu="Apple M1, 8 cores, aarch64", gpu="Apple M1 GPU (G13)",
         driver="asahi, GLES 3.2", screen="1920x1080 over HDMI", ram="8 GB", role="Apple Silicon with the Asahi kernel and Mesa, joined on 2026-11-10; no cursor plane, and its display driver reports no page flips to count.", baseline=True),
]
# both tables list the machines by year, the oldest first (sorted is stable: same-year machines keep the order above)
MACHINES.sort(key=lambda m: m["year"])
RETIRED = "An HP EliteBook 8560p (2011, Radeon HD 6470M, r600) was in the lab from 2026-10-22 until its GPU failed on 2026-10-27."

def values(alias, compositor, baseline=BASELINE):
    d = os.path.join(ROOT, baseline, alias, compositor)
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
    # a game's own frame rate: a decimal where it is low (ElectroBench's first scene draws 0.4 on the X200)
    if unit == "game fps": return f"{x:.1f} fps" if x < 100 else f"{x:.0f} fps"
    if unit == "score": return f"{x:.0f}"
    if unit == "ms/frame": return f"{x:.2f} ms"
    # the energy page: the CPU package's power, and the energy above the idle session per frame on the screen
    if unit == "W": return f"{x:.2f} W"
    if unit == "mJ": return f"{x:.1f} mJ" if x < 100 else f"{x:.0f} mJ"
    return f"{x:.1f} ms"

def cell(h, s, unit, lower_better):
    if h is None or s is None: return "<td>&ndash;</td>"
    # no frames counted (the M1's display driver reports no page flips): nothing to compare
    if unit == "fps" and (h <= 0 or s <= 0): return "<td>&ndash;</td>"
    better = (h <= s * 0.95) if lower_better else (h >= s * 1.05)
    worse = (h >= s * 1.05) if lower_better else (h <= s * 0.95)
    cls = ' class="yes"' if better else (' class="no"' if worse else "")
    return f"<td{cls}>{fmt(h, unit)} / {fmt(s, unit)}</td>"

E = html.escape

def head(title, description, og_description, path):
    """The page's <head> and the opening <body>; path is its file name under web/."""
    attr = lambda x: html.escape(x, quote=False).replace('"', "&quot;")
    return HEAD.format(title=attr(title), description=attr(description), og_description=attr(og_description), path=path)

HEAD = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<meta name="theme-color" content="#efe6d2">
<meta property="og:site_name" content="Hypoland">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{og_description}">
<meta property="og:type" content="website">
<meta property="og:url" content="https://hypoland.org/{path}">
<meta property="og:image" content="https://hypoland.org/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<link rel="canonical" href="https://hypoland.org/{path}">
<link rel="icon" type="image/svg+xml" href="icon.svg">
<link rel="icon" type="image/png" sizes="32x32" href="favicon.png">
<link rel="stylesheet" href="style.css">
</head>
<body>"""

FOOTER = """<footer>
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
</html>"""
