# table.py RUN : compositor CPU (also per frame on the screen), session total and screen fps per workload and machine, the
# latencies and the compositor's memory, Hyprland 0.57.0 -> Hypoland (medians)
import os, sys
run = sys.argv[1]
hosts = ["x200", "t550", "xps", "lianli", "chromebook", "t460s", "galaxybook", "macmini-intel"]
def load(h, v):
    d = {}
    try:
        for line in open(f"{run}/{h}/{v}/values.txt"):
            parts = line.split()
            if len(parts) != 4:  # a key without a numeric median (a value the bench script prints as text)
                continue
            k, med, lo, hi = parts
            d[k] = float(med)
    except FileNotFoundError:
        pass
    return d
data = {h: (load(h, "hyprland"), load(h, "hypoland")) for h in hosts}
wls = sorted({k.split(".")[1] for h in hosts for k in data[h][1] if k.startswith("cpu.")})
for metric, label in (("percent", "compositor CPU %"), ("ms_per_frame", "compositor CPU ms per frame on the screen"),
                      ("total_percent", "session total %"), ("screen", "screen fps")):
    print(f"\n### {label}: Hyprland 0.57.0 -> Hypoland")
    print(f"{'workload':22}" + "".join(f"{h:>17}" for h in hosts))
    for w in wls:
        row = f"{w:22}"
        for h in hosts:
            a, b = data[h]
            key = f"fps.{w}.screen" if metric == "screen" else f"cpu.{w}.{metric}"
            if key in a and key in b and (metric != "ms_per_frame" or min(a[key], b[key]) >= 0):
                row += f"{a[key]:>8.1f}>{b[key]:<8.1f}"
            else:
                row += f"{'-':>17}"
        print(row)
print("\n### latency medians ms: Hyprland 0.57.0 -> Hypoland")
lk = sorted({k for h in hosts for k in data[h][1] if k.startswith("latency.") and k.endswith("_ms") and "_p90" not in k})
print(f"{'kind':30}" + "".join(f"{h:>17}" for h in hosts))
for k in lk:
    row = f"{k[8:-3]:30}"
    for h in hosts:
        a, b = data[h]
        row += f"{a[k]:>8.1f}>{b[k]:<8.1f}" if k in a and k in b else f"{'-':>17}"
    print(row)
print("\n### compositor memory, MiB (threads: count): Hyprland 0.57.0 -> Hypoland")
print(f"{'':30}" + "".join(f"{h:>17}" for h in hosts))
for label, k in (("Pss at start", "mem.start.Pss_kB"), ("Pss anonymous at start", "mem.start.Pss_Anon_kB"),
                 ("heap at start", "mem.start.heap_kB"), ("threads at start", "mem.start.threads"),
                 ("GPU at start", "mem.start.gpu_kB"), ("Pss with 40 windows", "mem.many-windows-40.Pss_kB"),
                 ("Pss at end", "mem.end.Pss_kB"), ("Pss anonymous at end", "mem.end.Pss_Anon_kB"),
                 ("heap at end", "mem.end.heap_kB"), ("GPU at end", "mem.end.gpu_kB")):
    row = f"{label:30}"
    for h in hosts:
        a, b = data[h]
        if k in a and k in b:
            x, y = (a[k], b[k]) if k.endswith("threads") else (a[k] / 1024, b[k] / 1024)
            row += f"{x:>8.{0 if k.endswith('threads') else 1}f}>{y:<8.{0 if k.endswith('threads') else 1}f}"
        else:
            row += f"{'-':>17}"
    print(row)
