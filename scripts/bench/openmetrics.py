#!/usr/bin/env python3
"""The benchmark's results in OpenMetrics (https://prometheus.io/docs/specs/om/open_metrics_spec/), written and read.

measure.sh prints its values as "@ <round> <key> <value>" lines, e.g. "@ 2 cpu.folio-scroll.ms_per_frame 0.61". bench.sh
and a night's report.sh keep them (bench.txt, raw.txt) and their medians (values.txt, "<key> <median> <min> <max>").
results.om holds every value of every round or block with what it was measured on as labels, one file a run:

    # TYPE hypoland_cpu_ms_per_frame gauge
    # UNIT hypoland_cpu_ms_per_frame ms_per_frame
    hypoland_cpu_ms_per_frame{machine="x200",compositor="hypoland",version="0.3.0.r992.g92942ceba-1",run="...",block="7",workload="folio-scroll"} 0.61 1794839880

A key maps to a metric and back: its first part is the group (cpu, mem, fps, ...), its last the statistic (ms_per_frame,
Pss_kB, screen, ...), the part between the workload (the phase start / end for mem). The metric is hypoland_<group>_<stat>,
the middle part a label; keys of two parts are hypoland_<group>_<stat> (binary.size_kB) or, for fps and invalid,
hypoland_<group>{workload=...} (fps.gpu-client, the client's own frame rate). hypoland_run_info carries the lines about the
machine and the compositor (machine:, compositor:, package:, ...). The values are the text measure.sh printed, nan as NaN.

Usage:
  openmetrics.py write DIR [--label NAME=VALUE]... [--time T] [--out FILE]
      writes DIR/results.om (or FILE) from DIR/raw.txt (a night's blocks) or DIR/bench.txt (bench.sh's rounds), the lines about the
      machine from DIR/bench.txt (or a night's first block next to DIR). Labels given here win over those found in the files (machine, compositor, variant,
      version, run), <compositor>.NAME=VALUE only that compositor's (hyprland.version=0.57.2-2). T is seconds since the epoch or YYYY-MM-DD[ HH:MM], the time of every sample; without it the start
      of the compositor (its instance signature), else the time in a bench-YYYYmmdd-HHMMSS directory's name
  openmetrics.py values FILE [--label NAME=VALUE]...
      prints values.txt from it: "<key> <median> <min> <max>" over the blocks (with an even count the lower middle value,
      nan first, as sort -g), of the samples with those labels
  openmetrics.py keys FILE
      prints every key with its labels, one sample a line
"""

import glob
import math
import os
import re
import sys
import time
from collections import namedtuple

PREFIX = "hypoland_"
# groups whose key of two parts names a workload, not a statistic
WORKLOAD_GROUPS = ("fps", "flips", "invalid")
# the label of a key's middle part
MIDDLE = {"mem": "phase"}
# a statistic's unit, the end of its name (OpenMetrics wants a metric with a unit to end in it)
UNIT = re.compile(r"(?:^|_)(ms_per_frame|mJ_per_frame|kB|ms|s|W|J|percent)$")
KEY = re.compile(r"^([a-z]+)\.([A-Za-z0-9_-]+)(?:\.([A-Za-z0-9_]+))?$")
VALUE = re.compile(r"^(-?[0-9]+(\.[0-9]*)?([eE][-+]?[0-9]+)?|-?nan|-?inf)$", re.IGNORECASE)
NAME = re.compile(r"^[a-zA-Z_:][a-zA-Z0-9_:]*$")
# the labels every sample of a run carries, in this order
RUN_LABELS = ("machine", "compositor", "variant", "version", "run")

Sample = namedtuple("Sample", "name labels text value timestamp")


def escape(value):
    return value.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')


def label_text(labels):
    return ",".join(f'{n}="{escape(v)}"' for n, v in labels.items())


def unescape(value):
    return re.sub(r"\\(.)", lambda m: "\n" if m[1] == "n" else m[1], value)


def metric(key):
    """(metric name, middle label name, middle value) of a key, None for a key that is not one"""
    m = KEY.match(key)
    if not m:
        return None
    group, second, third = m.groups()
    if third is not None:
        return PREFIX + group + "_" + third, MIDDLE.get(group, "workload"), second
    if group in WORKLOAD_GROUPS:
        return PREFIX + group, "workload", second
    if "-" in second:
        return None
    return PREFIX + group + "_" + second, None, None


def key(sample):
    """the measure.sh key of a sample, None for hypoland_run_info"""
    if not sample.name.startswith(PREFIX) or sample.name == PREFIX + "run_info":
        return None
    group, _, stat = sample.name[len(PREFIX):].partition("_")
    middle = next((sample.labels[n] for n in ("workload", "phase") if n in sample.labels), None)
    return ".".join(p for p in (group, middle, stat) if p)


def om_value(text):
    """measure.sh's text of a value as OpenMetrics writes it: nan and inf as NaN and +Inf"""
    t = text.lower()
    if t.lstrip("-") == "nan":
        return "NaN"
    if t.lstrip("+-") == "inf":
        return "-Inf" if t.startswith("-") else "+Inf"
    return text


def parse_time(text):
    if re.fullmatch(r"[0-9]+", text):
        return int(text)
    for f in ("%Y-%m-%d %H:%M", "%Y-%m-%d"):
        try:
            return int(time.mktime(time.strptime(text, f)))
        except ValueError:
            pass
    raise SystemExit(f"openmetrics.py: not a time: {text}")


def run_lines(text):
    """the "@" lines (block, key, value) and the lines about the run ("name: text") of measure.sh's output, raw.txt or
    the old A/B format of docs/baseline/t550-vs-stock-hyprland-0.56.2 ("<compositor> <round> <workload> <line>"), then
    the count of "@" lines left out as broken (two writers at once, an empty value)"""
    values, info, broken = [], {}, 0
    for line in text.splitlines():
        compositor = None
        m = re.match(r"^(hypoland|hyprland) [0-9]+ \S+ (.*)$", line)
        if m:
            compositor, line = m[1], m[2]
        if line.startswith("@"):
            parts = line.split()
            if len(parts) != 4 or not VALUE.match(parts[3]) or not metric(parts[2]):
                broken += 1
                continue
            values.append((compositor, parts[1], parts[2], parts[3]))
            continue
        m = re.match(r"^([a-z]+): (.*)$", line)
        if m and m[1] in ("machine", "compositor", "package", "clocksource", "governor"):
            info.setdefault(m[1], m[2])
    return values, info, broken


def info_labels(info):
    """labels from the lines about the run"""
    labels = {}
    m = re.match(r"^([^,]+), ([^,]+), ([0-9]+) cores, ([0-9]+) MiB$", info.get("machine", ""))
    if m:
        labels.update(machine=m[1], hostname=m[1], kernel=m[2], cores=m[3], memory_mib=m[4])
    m = re.match(r"^(\S+), pid [0-9]+, user \S+, instance (\S+)$", info.get("compositor", ""))
    if m:
        labels.update(binary=m[1], instance=m[2])
    for n in ("package", "clocksource", "governor"):
        if n in info:
            labels[n] = info[n]
    return labels


def write(directory, given, when=None, out=None):
    """writes results.om of a run directory, returns (samples, broken lines)"""
    source = next((os.path.join(directory, f) for f in ("raw.txt", "bench.txt") if os.path.exists(os.path.join(directory, f))), None)
    if source is None:
        raise SystemExit(f"openmetrics.py: no raw.txt or bench.txt in {directory}")
    values, info, broken = run_lines(open(source, errors="replace").read())
    if os.path.basename(source) == "raw.txt" and os.path.exists(os.path.join(directory, "bench.txt")):
        for n, v in run_lines(open(os.path.join(directory, "bench.txt"), errors="replace").read())[1].items():
            info.setdefault(n, v)
    if os.path.basename(source) == "raw.txt" and "compositor" not in info:
        # a night's report.sh before 2026-11-16 kept only the machine line: the first block of the compositor or arm, next
        # to the directory as <name>-<block>.txt, has the rest
        name = os.path.basename(os.path.abspath(directory))
        blocks = glob.glob(os.path.join(os.path.dirname(os.path.abspath(directory)), glob.escape(name) + "-[0-9]*.txt"))
        blocks.sort(key=lambda f: int(re.match(r"[0-9]+", f[f.rindex(name + "-") + len(name) + 1:])[0]))
        if blocks:
            for n, v in run_lines(open(blocks[0], errors="replace").read())[1].items():
                info.setdefault(n, v)
    meta = info_labels(info)

    # where the directory is: a bench.sh run (bench-<time>-<label>/), a night's compositor or arm of a machine
    # (<run>/<machine>/<hypoland|hyprland|off|on|...>/raw.txt), or an old A/B with both compositors in one raw.txt
    name = os.path.basename(os.path.abspath(directory))
    labels = {}
    if "machine" in meta:
        labels["machine"] = meta["machine"]
    compositor = os.path.basename(meta.get("binary", "")).lower() or "hypoland"
    mixed = any(v[0] for v in values)
    if os.path.basename(source) == "raw.txt" and not mixed:
        parent = os.path.dirname(os.path.abspath(directory))
        labels["machine"] = os.path.basename(parent)
        labels["run"] = os.path.basename(os.path.dirname(parent))
        if name in ("hypoland", "hyprland"):
            compositor = name
        else:
            labels["variant"] = name
    else:
        labels["run"] = name
    labels["compositor"] = compositor
    if when is None and "instance" in meta:
        m = re.match(r"^[0-9a-f]+_([0-9]+)_", meta["instance"])
        if m:
            when = int(m[1])
    # the lines about the compositor of a raw.txt with both are the first block's
    if mixed:
        labels.pop("compositor")
        for n in ("binary", "instance", "package"):
            meta.pop(n, None)
    if "package" in meta:
        labels["version"] = meta["package"].split()[-1]
    elif "instance" in meta:
        labels["version"] = "g" + meta["instance"][:9]
    labels.update({n: v for n, v in given.items() if "." not in n})

    if when is None:
        m = re.match(r"^bench-([0-9]{8})-([0-9]{6})", name)
        if m:
            when = int(time.mktime(time.strptime(m[1] + m[2], "%Y%m%d%H%M%S")))

    families, seen = {}, set()
    for comp, block, k, text in values:
        name_, middle, middle_value = metric(k)
        sample = {n: labels[n] for n in RUN_LABELS if n in labels}
        if comp:
            sample["compositor"] = comp
        # labels given for one compositor: hyprland.version=0.56.2-4
        for n, v in given.items():
            c, _, n = n.rpartition(".")
            if c and c == sample["compositor"]:
                sample[n] = v
        sample = {n: sample[n] for n in (*RUN_LABELS, "block") if n in sample} | sample
        sample["block"] = block
        if middle:
            sample[middle] = middle_value
        # a key measured twice in one block (a workload listed twice) keeps both
        ident = (name_, tuple(sample.items()))
        n = 2
        while ident in seen:
            sample["repeat"] = str(n)
            ident, n = (name_, tuple(sample.items())), n + 1
        seen.add(ident)
        families.setdefault(name_, []).append((sample, om_value(text)))

    stamp = f" {when}" if when is not None else ""
    lines = []
    for name_, samples in families.items():
        lines.append(f"# TYPE {name_} gauge")
        unit = UNIT.search(name_[len(PREFIX):])
        if unit:
            lines.append(f"# UNIT {name_} {unit[1]}")
        for sample, text in samples:
            lines.append(f"{name_}{{{label_text(sample)}}} {text}{stamp}")
    run = {n: labels[n] for n in RUN_LABELS if n in labels}
    run.update({n: v for n, v in meta.items() if n not in run})
    lines.append(f"# TYPE {PREFIX}run info")
    lines.append(f"# HELP {PREFIX}run What the run measured and on what: the machine, the compositor and its package.")
    lines.append(f"{PREFIX}run_info{{{label_text(run)}}} 1{stamp}")
    lines.append("# EOF")
    out = out or os.path.join(directory, "results.om")
    with open(out, "w") as f:
        f.write("\n".join(lines) + "\n")
    return sum(len(s) for s in families.values()), broken


SAMPLE = re.compile(r"^([a-zA-Z_:][a-zA-Z0-9_:]*)(?:\{(.*)\})? (\S+)(?: (\S+))?$")
LABEL = re.compile(r'([a-zA-Z_][a-zA-Z0-9_]*)="((?:[^"\\]|\\.)*)"')


def read(path):
    """the samples of a results.om"""
    samples = []
    for line in open(path):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        m = SAMPLE.match(line)
        if not m:
            raise ValueError(f"{path}: not a sample: {line}")
        name, labels, text, stamp = m.groups()
        labels = {n: unescape(v) for n, v in LABEL.findall(labels or "")}
        samples.append(Sample(name, labels, text, float(text), int(stamp) if stamp else None))
    return samples


def values(samples, **labels):
    """{key: (median, min, max)} as values.txt has them, of the samples with these labels: the texts of the values,
    sorted as sort -g sorts them (nan first), with an even count the lower middle one"""
    keys = {}
    for s in samples:
        k = key(s)
        if k is None or any(s.labels.get(n) != v for n, v in labels.items()):
            continue
        keys.setdefault(k, []).append(s)
    result = {}
    for k, v in keys.items():
        v.sort(key=lambda s: (not math.isnan(s.value), s.value))
        text = lambda s: "nan" if s.text == "NaN" else s.text
        result[k] = (text(v[(len(v) + 1) // 2 - 1]), text(v[0]), text(v[-1]))
    return result


def label_args(args):
    labels = {}
    for a in args:
        n, sep, v = a.partition("=")
        if not sep or not NAME.match(n.rpartition(".")[2]):
            raise SystemExit(f"openmetrics.py: not a label: {a}")
        labels[n] = v
    return labels


def main(argv):
    if len(argv) < 2 or argv[0] not in ("write", "values", "keys"):
        sys.exit(__doc__.split("Usage:\n")[1].rstrip())
    command, target, rest = argv[0], argv[1], argv[2:]
    given, when, out = [], None, None
    while rest:
        option = rest.pop(0)
        if not rest:
            sys.exit(f"openmetrics.py: {option} needs a value")
        if option == "--label":
            given.append(rest.pop(0))
        elif option == "--time" and command == "write":
            when = parse_time(rest.pop(0))
        elif option == "--out" and command == "write":
            out = rest.pop(0)
        else:
            sys.exit(f"openmetrics.py: unknown argument: {option}")
    if command == "write":
        n, broken = write(target, label_args(given), when, out)
        if broken:
            print(f"{target}: {broken} broken lines left out", file=sys.stderr)
        return
    samples = read(target)
    if command == "values":
        for k, (median, low, high) in sorted(values(samples, **label_args(given)).items()):
            print(k, median, low, high)
        return
    for s in samples:
        print(key(s) or s.name, " ".join(f"{n}={v}" for n, v in s.labels.items()), s.text)


if __name__ == "__main__":
    main(sys.argv[1:])
