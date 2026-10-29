#!/usr/bin/env python3
"""Holds a key on the benchmark's uinput keyboard: holdkey.py KEY SECONDS. Prints "down" once the key is down, so the
caller can start measuring, and "up" after the release. The compositor forwards the one press and the client repeats it
at the session's rate (wl_keyboard.repeat_info), as it does for a finger resting on the key. uinput needs root."""

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
from latency import KEYS, Keyboard  # noqa: E402


def main():
    key, seconds = sys.argv[1], float(sys.argv[2])
    keyboard = Keyboard()
    keyboard.key(KEYS[key], 1)
    print("down", flush=True)
    time.sleep(seconds)
    keyboard.key(KEYS[key], 0)
    print("up", flush=True)
    time.sleep(0.2)
    keyboard.close()


main()
