#!/bin/bash
# puts back the session env files changed for HYPOLAND_SCANOUT_DEBUG on 2026-11-11 evening (t550, t460s had none; xps and
# galaxybook had an empty one, saved as /root/night-env.orig)
for h in t550 xps t460s galaxybook; do
    ssh root@$h 'F=/home/a/.config/uwsm/env; if [ -e /root/night-env.none ]; then rm -f $F /root/night-env.none; elif [ -e /root/night-env.orig ]; then cp /root/night-env.orig $F && chown a:a $F && rm /root/night-env.orig; fi; echo "$(hostname): $(cat $F 2>/dev/null | wc -l) lines"'
done
