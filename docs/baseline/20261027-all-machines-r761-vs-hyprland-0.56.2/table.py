# table.py RUN : compositor CPU, session total and screen fps per workload and machine, Hyprland 0.56.2 -> Hypoland (medians)
import os, sys
run = sys.argv[1]
hosts = ["x200", "t550", "xps", "lianli", "chromebook", "t460s", "galaxybook", "macmini-intel"]
def load(h, v):
    d = {}
    try:
        for line in open(f"{run}/{h}/{v}/values.txt"):
            k, med, lo, hi = line.split()
            d[k] = float(med)
    except FileNotFoundError:
        pass
    return d
data = {h: (load(h, "hyprland"), load(h, "hypoland")) for h in hosts}
wls = sorted({k.split(".")[1] for h in hosts for k in data[h][1] if k.startswith("cpu.")})
for metric, label in (("percent", "compositor CPU %"), ("total_percent", "session total %"), ("screen", "screen fps")):
    print(f"\n### {label}: Hyprland 0.56.2 -> Hypoland")
    print(f"{'workload':22}" + "".join(f"{h:>17}" for h in hosts))
    for w in wls:
        row = f"{w:22}"
        for h in hosts:
            a, b = data[h]
            key = f"fps.{w}.screen" if metric == "screen" else f"cpu.{w}.{metric}"
            if key in a and key in b:
                row += f"{a[key]:>8.1f}>{b[key]:<8.1f}"
            else:
                row += f"{'-':>17}"
        print(row)
print("\n### latency medians ms: Hyprland 0.56.2 -> Hypoland")
lk = sorted({k for h in hosts for k in data[h][1] if k.startswith("latency.") and k.endswith("_ms") and "_p90" not in k})
print(f"{'kind':30}" + "".join(f"{h:>17}" for h in hosts))
for k in lk:
    row = f"{k[8:-3]:30}"
    for h in hosts:
        a, b = data[h]
        row += f"{a[k]:>8.1f}>{b[k]:<8.1f}" if k in a and k in b else f"{'-':>17}"
    print(row)
