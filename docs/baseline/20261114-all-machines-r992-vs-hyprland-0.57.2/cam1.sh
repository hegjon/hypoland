#!/bin/bash
# cam1.sh OUT UNTIL : a picture of the XPS's screen from the camera cam1 (NETWORK.md, "Screen camera") every 30 s
# until UNTIL (a date(1) time), as OUT/YYYYmmdd-HHMMSS.jpg, for what the night's sessions really showed there.
# Pictures the camera does not answer are left out (cam1.log says so). Run detached on the desktop:
#   setsid -f nohup bash cam1.sh OUT "2026-11-15 07:30" >/dev/null 2>&1 </dev/null
OUT=$1 UNTIL=$2
END=$(date -d "$UNTIL" +%s)
mkdir -p "$OUT"
exec >>"$OUT/cam1.log" 2>&1
echo "$(date '+%F %T') until $(date -d "@$END" '+%F %T')"
while [ "$(date +%s)" -lt "$END" ] && [ ! -e "$OUT/stop" ]; do
    f=$OUT/$(date +%Y%m%d-%H%M%S).jpg
    if timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=5 cam1 prudyntctl snapshot -c 0 -q 70 >"$f.part" && [ -s "$f.part" ]; then
        mv "$f.part" "$f"
    else
        rm -f "$f.part"
        echo "$(date '+%F %T') no picture"
    fi
    sleep 30
done
echo "$(date '+%F %T') done"
