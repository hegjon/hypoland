# table.py RUN : compositor CPU, session total and screen fps per workload and machine, off -> on (medians)
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
data = {h: (load(h, "off"), load(h, "on")) for h in hosts}
wls = sorted({k.split(".")[1] for h in hosts for k in data[h][1] if k.startswith("cpu.")})
def cell(h, key):
    a, b = data[h][0].get(key), data[h][1].get(key)
    return "-" if a is None or b is None else f"{a:g} -> {b:g}"
for title, keys in [("compositor CPU, percent of one core", lambda w: f"cpu.{w}.percent"),
                    ("whole session CPU (user@<uid>.service)", lambda w: f"cpu.{w}.total_percent"),
                    ("frames on the screen per second", lambda w: f"fps.{w}.screen")]:
    print(f"## {title}, off -> on\n")
    print("| workload | " + " | ".join(hosts) + " |")
    print("|---|" + "---|" * len(hosts))
    for w in wls:
        print(f"| {w} | " + " | ".join(cell(h, keys(w)) for h in hosts) + " |")
    print()
print("## memory at the start (60 s after the compositor started) and after the idle windows, KiB, off -> on\n")
print("| key | " + " | ".join(hosts) + " |")
print("|---|" + "---|" * len(hosts))
for key in ["mem.start.Pss_kB", "mem.start.heap_kB", "mem.start.threads", "mem.end.Pss_kB", "mem.idle-windows.gpu_added_kB", "mem.end.gpu_kB"]:
    print(f"| {key} | " + " | ".join(cell(h, key) for h in hosts) + " |")
print()
print("## latency medians, ms, off -> on\n")
lats = sorted({k for h in hosts for k in data[h][1] if k.startswith("latency.") and k.endswith("_ms") and "p90" not in k})
print("| key | " + " | ".join(hosts) + " |")
print("|---|" + "---|" * len(hosts))
for key in lats:
    print(f"| {key} | " + " | ".join(cell(h, key) for h in hosts) + " |")
