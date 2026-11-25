# The facts and helpers the generated pages about the lab share (scripts/web/lab.py, terminals.py, games.py): the
# machines, the baseline their numbers come from, its values, and the page's head and footer.
import html, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HYPRLAND = "0.57.2"
# Since 2026-11-25 every page compares nothing but the Hypoland 0.4.0 release (a plain build) against Hyprland
# 0.57.2-2 (the user's decision): BASELINE is the night of 2026-11-24 to 25 on twelve machines. The X200 and the Turbo-X
# hung in a stock session that night, so theirs (FALLBACK) pool the sessions of that night and of 11-25, the same
# packages (X200_TURBOX_RUN, built by its combine.sh, README.md there). The P14s was not in those runs and has no row.
# Before, the pages mixed builds: from 2026-11-24 the r1030 PGO night of 11-18 with r1029 and r992 nights for four
# machines, from 11-21 the r1029 night of 11-17, from 11-15 the r992 night of 11-14; from 2026-11-13 to 15 Hypoland's
# numbers came from docs/baseline/20261112-all-machines-r991-realtime-off-vs-on and Hyprland's from
# docs/baseline/20261111-all-machines-r966-vs-hyprland-0.57.1 (HYPOLAND_RUN and HYPOLAND_BLOCKS stay for such a pair:
# Hypoland's blocks are HYPOLAND_RUN/<machine>/<HYPOLAND_BLOCKS.get(machine, "hypoland")>).
BASELINE = "docs/baseline/20261124-all-machines-0.4.0-vs-hyprland-0.57.2"
X200_TURBOX_RUN = "docs/baseline/20261125-x200-turbox-0.4.0-vs-hyprland-0.57.2"
FALLBACK = {"x200": X200_TURBOX_RUN, "turbox": X200_TURBOX_RUN}
HYPOLAND_RUN = BASELINE
HYPOLAND_BLOCKS = {}
# the runs the numbers come from, for the pages' notes
RUN = ("the Hypoland 0.4.0 release against Hyprland " + HYPRLAND + "-2, alternating through the night of 2026-11-24 to 25")
# what that means for reading them
TWO_NIGHTS = ("The two alternated in fresh sessions, so a drift of the machine hits both. The X200 and the Turbo-X hung in "
              "a Hyprland session that night; theirs add the sessions of 11-25.")
# the raw data of the nights, for the pages' notes
_link = lambda d: f'<a href="https://github.com/hegjon/hypoland/tree/master/{d}">{d.split("/")[-1]}</a>'
RAW = f"Raw data and scripts: {_link(BASELINE)}, {_link(X200_TURBOX_RUN)}."

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
         driver="iris, GLES 3.2", screen="1920x1080", ram="8 GB", role="Whiskey Lake, the newest of the lab's Gen 9 Intel GPUs.", baseline=True),
    dict(alias="lianli", name="Desktop, AMD A8-6600K APU", year=2013, cpu="A8-6600K, 4 cores", gpu="AMD Radeon HD 8570D (TeraScale 3)",
         driver="r600, GLES 3.1", screen="1920x1200", ram="8 GB", role="The AMD machine: the r600 driver with legacy modesetting.", baseline=True),
    dict(alias="galaxybook", name="Samsung Galaxy Book4 Edge 14\"", year=2024, cpu="Snapdragon X Elite, 12 cores, aarch64", gpu="Qualcomm Adreno X1-85",
         driver="freedreno, GLES 3.2", screen="2880x1800 at scale 2, 120 Hz", ram="16 GB", role="The aarch64 machine, with its own package build; 120 Hz.", baseline=True),
    dict(alias="samsung-i5", name="Samsung Series 7 Ultra (NP730U3E)", year=2013, cpu="Core i5-3337U, 4 threads", gpu="Intel HD Graphics 4000 (Ivy Bridge)",
         driver="crocus, GLES 3.0", screen="1920x1080", ram="4 GB", role="Ivy Bridge: the crocus generation between Bay Trail and Haswell.", baseline=True),
    dict(alias="macmini-m1", name="Apple Mac mini M1", year=2020, cpu="Apple M1, 8 cores, aarch64", gpu="Apple M1 GPU (G13)",
         driver="asahi, GLES 3.2", screen="2560x1440 over HDMI", ram="8 GB", role="Apple Silicon with the Asahi kernel and Mesa; no cursor plane, and its display driver reports no page flips to count.", baseline=True),
    dict(alias="hp-amd", name="HP Notebook (A6-7310)", year=2016, cpu="AMD A6-7310, 4 cores", gpu="AMD Radeon R4 (Carrizo-L, GCN 2)",
         driver="radeonsi on amdgpu, GLES 3.2", screen="1920x1080 at scale 1.5", ram="8 GB, 1 GB of it for the GPU", role="The oldest GPU on radeonsi, the driver every newer Radeon uses.", baseline=True),
    dict(alias="p14s", name="Lenovo ThinkPad P14s Gen 2a", year=2021, cpu="Ryzen 7 PRO 5850U, 16 threads", gpu="AMD Radeon Vega 8 (Cezanne)",
         driver="radeonsi, GLES 3.2", screen="3840x2160 at scale 2", ram="16 GB, 4 GB of it for the GPU", role="Radeonsi on a Zen 3 APU, and the lab's first 4K screen.", baseline=False,
         nodata="was not in the 0.4.0 runs"),
    dict(alias="turbox", name="Turbo-X Sirus Duo", year=2006, cpu="Core 2 Duo T5500, 2 cores", gpu="ATI Mobility Radeon X1600 (RV530, R500)",
         driver="r300, GLES 2.0 only", screen="1280x800", ram="1 GB", role="The oldest machine and the only R500: GLES 2.0 like the X200, with 1 GB of RAM and a spinning disk; stock Hyprland does not start on it.", baseline=True),
    dict(alias="msi-claw", name="MSI Claw A1M", year=2024, cpu="Core Ultra 7 155H, 22 threads", gpu="Intel Arc Graphics (Meteor Lake, Xe-LPG)",
         driver="iris, GLES 3.2", screen="1920x1080 at scale 2, 120 Hz", ram="16 GB", role="The handheld, and the newest Intel GPU of the lab: Arc on Meteor Lake; 120 Hz.", baseline=True),
]
# both tables list the machines by year, the oldest first (sorted is stable: same-year machines keep the order above)
MACHINES.sort(key=lambda m: m["year"])
RETIRED = "An HP EliteBook 8560p (2011, Radeon HD 6470M, r600) was in the lab from 2026-10-22 until its GPU failed on 2026-10-27."

def values(alias, compositor, baseline=None):
    """A machine's medians and its count of sessions: by default Hypoland's from HYPOLAND_RUN and Hyprland's from
    BASELINE, with a baseline directory the compositor's from there."""
    if baseline is not None:
        d = os.path.join(ROOT, baseline, alias, compositor)
    elif alias in FALLBACK:
        d = os.path.join(ROOT, FALLBACK[alias], alias, compositor)
    elif compositor == "hypoland":
        d = os.path.join(ROOT, HYPOLAND_RUN, alias, HYPOLAND_BLOCKS.get(alias, "hypoland"))
    else:
        d = os.path.join(ROOT, BASELINE, alias, compositor)
    v = {}
    for line in open(os.path.join(d, "values.txt")):
        parts = line.split()
        if len(parts) >= 2:
            try: v[parts[0]] = float(parts[1])
            except ValueError: pass
    sessions = sum(1 for line in open(os.path.join(d, "raw.txt")) if re.match(r"@ \d+ cpu\.gpu-client\.percent ", line))
    return v, sessions

def has(alias):
    """Whether the night (or both nights, or the machine's FALLBACK night) has the machine."""
    if alias in FALLBACK:
        return all(os.path.isdir(os.path.join(ROOT, FALLBACK[alias], alias, c)) for c in ("hypoland", "hyprland"))
    return (os.path.isdir(os.path.join(ROOT, HYPOLAND_RUN, alias, HYPOLAND_BLOCKS.get(alias, "hypoland")))
            and os.path.isdir(os.path.join(ROOT, BASELINE, alias, "hyprland")))

def sessions_text(pairs, few):
    """'8 to 12 fresh sessions of Hypoland and 13 to 18 of Hyprland' over the (Hypoland, Hyprland) session counts of the
    machines that have at least few of each."""
    full = [p for p in pairs if min(p) >= few]
    span = lambda xs: f"{min(xs)}" if min(xs) == max(xs) else f"{min(xs)} to {max(xs)}"
    return f"{span([h for h, _ in full])} fresh sessions of Hypoland and {span([s for _, s in full])} of Hyprland"

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
