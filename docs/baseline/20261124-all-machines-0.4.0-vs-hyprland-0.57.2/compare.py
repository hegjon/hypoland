#!/usr/bin/env python3
# compare.py : the Hypoland 0.4.0 release (plain build, night-20261124-040) against master r1029 (plain, night-20261117,
# the like-for-like build type) and r1030 PGO (night-20261118, about 5% less CPU than plain), from the block files.
#   N24 = night-20261124-040: 0.4.0 vs Hyprland 0.57.2-2 (this run; x200 and turbox hung, not fetched)
#   N18 = night-20261118: r1030 PGO vs the same Hyprland 0.57.2-2
#   N17 = night-20261117: r1029 plain vs the same Hyprland 0.57.2-2 (chromebook and hp-amd: the b blocks are merged
#         into night-20261117/night-20261117/<host> already)
# Per machine and metric group: the median ratio 0.4.0/r1029 and 0.4.0/PGO, each next to stock's own drift (the
# control), and Hypoland against stock in this night and 11-17. Then the metrics where 0.4.0 moved against r1029,
# stock did not, and 0.4.0's median lies outside r1029's per-block range.
import glob, os, re, statistics, sys
T = os.path.dirname(os.path.abspath(__file__)) + "/.."
HOSTS = ["t550", "xps", "lianli", "chromebook", "t460s", "t490", "samsung-i5", "macmini-m1", "hp-amd", "macmini-intel",
         "msi-claw", "galaxybook"]
def blocks(d, prefix):
    """{key: [value per block]} over prefix-N.txt and prefix-N-startup.txt"""
    vals = {}
    for f in glob.glob(f"{d}/{prefix}-[0-9]*.txt"):
        for line in open(f, errors="replace"):
            p = line.split()
            if len(p) < 4 or p[0] != "@": continue
            try: v = float(p[3])
            except ValueError: continue
            vals.setdefault(p[2], []).append(v)
    return vals
def med(vals, k, n=3):
    v = vals.get(k)
    return statistics.median(v) if v and len(v) >= n else None
N = {
    "h24": lambda h: blocks(f"{T}/night-20261124-040/night-20261124-040/{h}", "hypoland"),
    "s24": lambda h: blocks(f"{T}/night-20261124-040/night-20261124-040/{h}", "hyprland"),
    "h18": lambda h: blocks(f"{T}/night-20261118/night-20261118/{h}", "hypoland"),
    "s18": lambda h: blocks(f"{T}/night-20261118/night-20261118/{h}", "hyprland"),
    "h17": lambda h: blocks(f"{T}/night-20261117/night-20261117/{h}", "hypoland"),
    "s17": lambda h: blocks(f"{T}/night-20261117/night-20261117/{h}", "hyprland"),
}
GROUPS = [("cpu %", r"^cpu\.[^.]*\.percent$"), ("cpu ms/frame", r"^cpu\..*\.ms_per_frame$"),
          ("latency", r"^latency\..*(?<!p90)_ms$"), ("fps", r"^fps\.[^.]*(\.screen)?$"),
          ("pss start", r"^mem\.start\.Pss_kB$"), ("startup", r"^startup\..*_ms$")]
data = {h: {n: f(h) for n, f in N.items()} for h in HOSTS}
def ratio(h, k, a, b, floor=0.0):
    x, y = med(data[h][a], k), med(data[h][b], k)
    if x is None or y is None or y <= floor or x < 0: return None
    return x / y
def gmed(h, rx, a, b):
    r = [x for k in data[h][a] if re.search(rx, k) for x in [ratio(h, k, a, b, 0.05)] if x]
    return "%.3f (%d)" % (statistics.median(r), len(r)) if r else "-"
cols = [("0.4.0/r1029", "h24", "h17"), ("stock 24/17", "s24", "s17"), ("0.4.0/PGO", "h24", "h18"),
        ("stock 24/18", "s24", "s18"), ("hyp/stock 11-24", "h24", "s24"), ("hyp/stock 11-17", "h17", "s17")]
print("blocks per machine (0.4.0 / stock 11-24, PGO / stock 11-18, r1029 / stock 11-17):")
for h in HOSTS:
    c = lambda n: max((len(v) for k, v in data[h][n].items() if k.startswith("cpu.")), default=0)
    print("  %-13s %3d / %3d   %3d / %3d   %3d / %3d" % (h, c("h24"), c("s24"), c("h18"), c("s18"), c("h17"), c("s17")))
for g, rx in GROUPS:
    print(f"\n### {g}: median ratio over the metrics (count); below 1 is less (better for cpu, latency, pss; worse for fps)")
    print("%-13s" % "" + "".join("%18s" % c[0] for c in cols))
    for h in HOSTS:
        print("%-13s" % h + "".join("%18s" % gmed(h, rx, a, b) for _, a, b in cols))
print("\n### metrics where 0.4.0 moved against r1029 by more than 10%, stock moved less than half as much,")
print("### and 0.4.0's median is outside r1029's per-block range (out=yes)")
print("%-13s %-46s %10s %10s %8s %8s %18s %4s" % ("machine", "metric", "r1029", "0.4.0", "ratio", "stock", "r1029 range", "out"))
rows = []
for h in HOSTS:
    for k in data[h]["h24"]:
        if not re.search(r"ms_per_frame$|^latency\..*(?<!p90)_ms$|^fps\.[^.]*(\.screen)?$|^cpu\.[^.]*\.percent$|^mem\.start\.Pss_kB$|^startup\..*_ms$", k): continue
        r = ratio(h, k, "h24", "h17", 0.3)
        if r is None or 0.91 < r < 1.10: continue
        s = ratio(h, k, "s24", "s17", 0.05)
        if s is not None and abs(s - 1) > abs(r - 1) / 2: continue
        old = data[h]["h17"].get(k)
        if not old: continue
        m = med(data[h]["h24"], k)
        out = m < min(old) or m > max(old)
        rows.append((out, abs(r - 1), h, k, med(data[h]["h17"], k), m, r, s, min(old), max(old)))
for out, _, h, k, x, y, r, s, lo, hi in sorted(rows, reverse=True)[:int(sys.argv[1]) if len(sys.argv) > 1 else 60]:
    f = lambda v: "%.3f" % v if v is not None else "-"
    print("%-13s %-46s %10.2f %10.2f %8s %8s %8.2f..%-8.2f %4s" % (h, k[:46], x, y, f(r), f(s), lo, hi, "yes" if out else "no"))
