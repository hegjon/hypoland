# table.py RUN : the CPU package's power (RAPL) per workload and machine, Hyprland 0.57.2-4 -> Hypoland, medians over the
# blocks of report.sh (RUN/<host>/<compositor>/values.txt). "power" is the package's mean power over the workload's
# 30 s, "net" that minus the idle session around it, "idle" the session with nothing open (power.baseline.W, every
# baseline of the block), and the saving in percent of stock's power. The T460s and T490 also have RAPL's platform zone
# (psys), the whole machine as its power supply delivers it, in tables of their own.
import sys
run = sys.argv[1]
hosts = ["t550", "xps", "chromebook", "macmini-intel", "t460s", "t490", "samsung-i5"]
def load(h, v):
    d = {}
    try:
        for line in open(f"{run}/{h}/{v}/values.txt"):
            parts = line.split()
            if len(parts) != 4:
                continue
            d[parts[0]] = float(parts[1])
    except FileNotFoundError:
        pass
    return d
def blocks(h, v):
    try:
        return len({line.split()[1] for line in open(f"{run}/{h}/{v}/raw.txt")})
    except FileNotFoundError:
        return 0
data = {h: (load(h, "hyprland"), load(h, "hypoland")) for h in hosts}
hosts = [h for h in hosts if data[h][0] and data[h][1]]
print("blocks (Hyprland 0.57.2-4 / Hypoland): " + ", ".join(f"{h} {blocks(h, 'hyprland')}/{blocks(h, 'hypoland')}" for h in hosts))
wls = []
for h in hosts:
    for k in data[h][1]:
        if k.startswith("power.") and k.endswith(".W") and not k.startswith("power.baseline."):
            w = k[6:-2]
            if w not in wls:
                wls.append(w)
order = "idle,gpu-client,video,video-window,gtk3-scroll,gtk4-scroll,qt-quick-scroll,qt-software-scroll,gtk3-x11-scroll,gtk4-spinner,qt-software-sprites,tk-canvas,workspace-switch,idle-windows,dev,notifications,menu,nautilus-scroll".split(",")
wls.sort(key=lambda w: order.index(w) if w in order else len(order))
def cell(a, b, key, pct=True):
    if key not in a or key not in b:
        return f"{'-':>22}"
    s = f"{a[key]:>6.2f}>{b[key]:<6.2f}"
    if pct and a[key] > 0.05:
        s += f"{100 * (b[key] - a[key]) / a[key]:>+7.1f}%"
    else:
        s += f"{b[key] - a[key]:>+7.2f} "
    return f"{s:>22}"
psys = [h for h in hosts if "power.baseline.psys_W" in data[h][1]]
for metric, label, pct, hs in (("W", "CPU package power, W", True, hosts), ("net_W", "CPU package above the idle session, W", False, hosts),
                               ("psys_W", "the whole platform (psys), W", True, psys),
                               ("psys_net_W", "the platform above the idle session, W", False, psys)):
    if not hs:
        continue
    print(f"\n### {label}: Hyprland 0.57.2-4 -> Hypoland")
    print(f"{'workload':20}" + "".join(f"{h:>22}" for h in hs))
    if metric in ("W", "psys_W"):
        print(f"{'(idle session)':20}" + "".join(cell(*data[h], f"power.baseline.{metric}") for h in hs))
    for w in wls:
        print(f"{w:20}" + "".join(cell(*data[h], f"power.{w}.{metric}", pct) for h in hs))
# the energy above the idle session per frame on the screen, per block and then the median over the blocks (the runs of
# 2026-11-12 started before measure.sh reported it as energy.*.net_mJ_per_frame): a compositor that shows more frames
# has its clients draw more, which the power alone counts against it
def per_frame(h, v, w, net):
    by = {}
    try:
        for line in open(f"{run}/{h}/{v}/raw.txt"):
            _, b, k, x = line.split()[:4]
            by.setdefault(b, {})[k] = float(x)
    except FileNotFoundError:
        return None
    vals = sorted(d[f"power.{w}.{net}"] * 1000 / d[f"fps.{w}.screen"] for d in by.values()
                  if f"power.{w}.{net}" in d and d.get(f"fps.{w}.screen", 0) >= 1)
    return vals[(len(vals) - 1) // 2] if vals else None
for net, label, hs in (("net_W", "CPU package above the idle session, mJ per frame on the screen", hosts),
                       ("psys_net_W", "the platform (psys) above the idle session, mJ per frame on the screen", psys)):
    if not hs:
        continue
    print(f"\n### {label}: Hyprland 0.57.2-4 -> Hypoland")
    print(f"{'workload':20}" + "".join(f"{h:>22}" for h in hs))
    for w in wls:
        row = f"{w:20}"
        for h in hs:
            a, b = per_frame(h, "hyprland", w, net), per_frame(h, "hypoland", w, net)
            if a is None or b is None:
                row += f"{'-':>22}"
                continue
            c = f"{a:>6.1f}>{b:<6.1f}" + (f"{100 * (b - a) / a:>+7.1f}%" if a > 0.5 else f"{b - a:>+7.1f} ")
            row += f"{c:>22}"
        print(row)
print("\n### screen fps: Hyprland 0.57.2-4 -> Hypoland")
print(f"{'workload':20}" + "".join(f"{h:>22}" for h in hosts))
for w in wls:
    print(f"{w:20}" + "".join(cell(*data[h], f"fps.{w}.screen", False) for h in hosts))
print("\n### compositor instructions, millions in 30 s: Hyprland 0.57.2-4 -> Hypoland")
print(f"{'workload':20}" + "".join(f"{h:>22}" for h in hosts))
for w in wls:
    row = f"{w:20}"
    for h in hosts:
        a, b = data[h]
        k = f"perf.{w}.Minstructions"
        row += f"{a[k]:>9.0f}>{b[k]:<6.0f}{100 * (b[k] - a[k]) / a[k]:>+6.0f}%" if k in a and k in b and a[k] > 0 else f"{'-':>22}"
    print(row)
