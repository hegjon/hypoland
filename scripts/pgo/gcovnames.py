#!/usr/bin/env python3
"""Function names for the records of a -fprofile-generate binary: each gcov_fn_info {key, ident, lineno_checksum,
cfg_checksum, ctrs[{num, values}]} points to its counter array __gcov0.<name> (in the symbol table); the key points to
the object's gcov_info, whose filename is the .gcda path. Prints "<gcda file name> <ident> <lineno cs> <cfg cs> <name>".
usage: gcovnames.py <stripped binary> <debug file or unstripped binary>"""
import sys, struct, subprocess
binf, dbg = sys.argv[1], sys.argv[2]
sec = {}
for l in subprocess.run(["readelf", "-SW", binf], capture_output=True, text=True).stdout.splitlines():
    f = l.replace("[ ", "[").split()
    if len(f) > 6 and f[0].startswith("[") and f[2] == "PROGBITS": sec[f[1]] = (int(f[3], 16), int(f[4], 16), int(f[5], 16))
data = open(binf, "rb").read()
def read(addr, n):
    for a, off, size in sec.values():
        if a <= addr < a + size: return data[off + addr - a: off + addr - a + n]
    return None
def cstr(addr):
    b = read(addr, 512); return b.split(b"\0")[0].decode(errors="replace") if b else "?"
ctr = {}
for l in subprocess.run(["nm", dbg], capture_output=True, text=True).stdout.splitlines():
    p = l.split()
    if len(p) == 3 and p[2].startswith("__gcov0."): ctr[int(p[0], 16)] = p[2][len("__gcov0."):]
files = {}
for name in (".data.rel.ro", ".data"):
    if name not in sec: continue
    a, off, size = sec[name]
    words = struct.unpack_from(f"<{size // 8}Q", data, off)
    for i, w in enumerate(words):
        if w not in ctr or i < 4: continue
        base = a + (i - 4) * 8
        key, ident, lcs, ccs = struct.unpack_from("<QIII", data, off + (i - 4) * 8)
        if key not in files: files[key] = cstr(struct.unpack("<Q", read(key + 24, 8))[0]) if read(key + 24, 8) else "?"
        print(files[key].rsplit("/", 1)[-1], ident, f"{lcs:#x}", f"{ccs:#x}", ctr[w])
