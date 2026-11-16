#!/usr/bin/env python3
"""Functions that ran in the training, from the merged profile and gcovnames.txt: prints
"<name> <arc count sum> <first run order>" for every function with a nonzero counter, most frequent first.
usage: executed.py <profile dir> <gcovnames.txt>"""
import sys, subprocess, pathlib, re, collections
names = {}
for l in open(sys.argv[2]):
    f, ident, lcs, ccs, n = l.split()
    names[(f, int(ident), int(lcs, 16), int(ccs, 16))] = n
total = collections.Counter(); first = {}
for p in sorted(pathlib.Path(sys.argv[1]).glob("*.gcda")):
    out = subprocess.run(["gcov-dump", "-l", str(p)], capture_output=True, text=True).stdout
    cur = None; kind = None
    for line in out.splitlines():
        line = line.split(":", 1)[1] if line.startswith(str(p)) else line
        m = re.search(r"FUNCTION ident=(\d+), lineno_checksum=(0x[0-9a-f]+), cfg_checksum=(0x[0-9a-f]+)", line)
        if m:
            cur = names.get((p.name, int(m.group(1)), int(m.group(2), 16), int(m.group(3), 16))); continue
        m = re.search(r"COUNTERS (\w+) \d+ counts", line)
        if m: kind = m.group(1); continue
        m = re.match(r"\s+\d+: ([\d ]+)$", line)
        if m and cur:
            v = [int(x) for x in m.group(1).split()]
            if kind == "arcs": total[cur] += sum(v)
            elif kind == "time_profiler" and v[0]: first[cur] = min(first.get(cur, 1 << 62), v[0])
ran = set(total[n] and n for n in total) - {0} | set(first)
for n in sorted(ran, key=lambda n: -total[n]): print(n, total[n], first.get(n, 0))
print(f"{len(ran)} functions ran, {len(names)} known", file=sys.stderr)
