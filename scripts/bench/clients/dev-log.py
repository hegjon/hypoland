# a busy server's log: 200 lines a second, and every 10 s the trace of a failing request, 400 lines at once
import sys
import time

i = 0
while True:
    stamp = time.strftime("%H:%M:%S")
    for _ in range(10):
        i += 1
        level = "\033[33mWARN\033[0m " if i % 37 == 0 else "INFO "
        sys.stdout.write(f"{stamp}.{i * 7 % 1000:03d} {level} worker-{i % 8}: GET /api/items/{i * 7919 % 100000} 200 in {i % 97 + 3} ms\n")
    if i % 2000 == 0:
        sys.stdout.write(f"{stamp} \033[31mERROR\033[0m worker-{i % 8}: request {i} failed\n")
        sys.stdout.writelines(f"    at f{(i + k) % 14000 + 1:05d} (items.c:{(i * k) % 210000 + 1})\n" for k in range(400))
    sys.stdout.flush()
    time.sleep(0.05)
