#!/usr/bin/python3 -I
"""Receives netconsole messages (extended format) from the test machines and appends them to one log per
machine in the directory given as the first argument. Installed on the desktop by forward-logs.sh.

Every line is: receive time, sender address, <level>, kernel sequence number, message. The machines send every
kernel message (console log level 8), so a gap in the sequence numbers is a lost packet and is logged as LOST;
a sequence number going back means the machine rebooted.
"""
import os
import socket
import sys
import time

out = sys.argv[1]
port = int(sys.argv[2]) if len(sys.argv) > 2 else 6666
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.bind(("", port))
last_seq = {}
# the host name of every address, for the fragments of a long message, which come without it
host_of = {}
files = {}

while True:
    data, (addr, _) = sock.recvfrom(65535)
    lines = data.decode(errors="replace").rstrip("\n").split("\n")
    head, _, msg = lines[0].partition(";")
    # continuation lines start with a space: the kernel's dictionary and the userdata (host=)
    host = host_of.get(addr, addr)
    extra = []
    for line in lines[1:]:
        if line.startswith(" host="):
            host = host_of[addr] = line[6:].strip() or addr
        else:
            extra.append(line)
    fields = head.split(",")
    try:
        level, seq = int(fields[0]) & 7, int(fields[1])
    except (ValueError, IndexError):
        level, seq, msg = "?", None, lines[0]
    fragment = any(f.startswith("ncfrag=") for f in fields)

    f = files.get(host)
    if f is None:
        f = files[host] = open(os.path.join(out, host + ".log"), "a", buffering=1)
    stamp = time.strftime("%F %T")
    prev = last_seq.get(host)
    if seq is not None and prev is not None and not fragment:
        if seq > prev + 1:
            f.write(f"{stamp} {addr} LOST {seq - prev - 1} messages ({prev + 1} to {seq - 1})\n")
        elif seq < prev:
            f.write(f"{stamp} {addr} sequence went back from {prev} to {seq}: rebooted\n")
    if seq is not None:
        last_seq[host] = seq
    f.write(f"{stamp} {addr} <{level}> {seq} {msg}\n")
    for line in extra:
        f.write(f"{stamp} {addr}     {line.strip()}\n")
