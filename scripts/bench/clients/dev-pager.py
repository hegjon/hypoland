# pages through what comes on stdin the way holding space in less does, ten pages a second for as many seconds as
# the first argument says
import os
import sys
import time

lines = sys.stdin.read().splitlines()
rows = os.get_terminal_size(1).lines - 1
end = time.monotonic() + float(sys.argv[1])
for n in range(0, len(lines), rows):
    sys.stdout.write("\033[H\033[2J" + "\n".join(lines[n : n + rows]))
    sys.stdout.flush()
    time.sleep(0.1)
    if time.monotonic() > end:
        break
print()
