#!/usr/bin/env python3
"""The linker's section order for a profile guided build, from the functions that ran in the training (executed.py's
output) and the symbols of a build that used the profile (nm -S): the functions' own sections first, the hottest (arc
counts) before the rest in the order they first ran, then their cold parts (.text.unlikely.<name>). A function that
ran and whose whole body sits among the cold parts in that build (a COMDAT copy from an object where it never ran, or
one GCC thought cold) goes with the functions that ran. usage: order.py executed.txt syms.txt > order.ld"""
import sys

rows = [(n, int(c), int(f)) for n, c, f in (l.split() for l in open(sys.argv[1]))]
names = {r[0] for r in rows}
syms = [(int(p[0], 16), p[3]) for p in (l.split() for l in open(sys.argv[2])) if len(p) == 4]
cold = [a for a, n in syms if ".cold" in n and n.split(".cold")[0] in names]
zone = (min(cold), max(cold)) if cold else (0, -1)
whole = {n for a, n in syms if n in names and zone[0] <= a <= zone[1]}
hot = sorted((r for r in rows if r[1] >= 100000), key=lambda r: -r[1])
rest = sorted((r for r in rows if r[1] < 100000), key=lambda r: (r[2] == 0, r[2]))
print(".text : {")
for n, _, _ in hot + rest:
    print(f"  *(.text.hot.{n} .text.{n} .text.startup.{n}{' .text.unlikely.' + n if n in whole else ''})")
for n, _, _ in hot + rest:
    if n not in whole:
        print(f"  *(.text.unlikely.{n})")
print("}")
print(f"{len(hot)} hot, {len(rest)} others, {len(whole)} of them whole in the cold zone", file=sys.stderr)
