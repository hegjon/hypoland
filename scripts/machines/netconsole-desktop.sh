#!/bin/bash
# Points netconsole at the desktop over the interface that reaches it, installed on the test machines as
# /usr/local/sbin/netconsole-desktop by forward-logs.sh. Runs at boot and from NetworkManager whenever a link
# comes up or changes its address; does nothing when the target is already right.
# The desktop's address is in /etc/netconsole-desktop.conf (DESKTOP=...), the port is 6666.
set -u
. /etc/netconsole-desktop.conf
T=/sys/kernel/config/netconsole/desktop

modprobe netconsole || exit 1
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config

route=$(ip -4 route get "$DESKTOP" 2>/dev/null | head -1)
dev=$(grep -o 'dev [^ ]*' <<<"$route" | cut -d' ' -f2)
src=$(grep -o 'src [^ ]*' <<<"$route" | cut -d' ' -f2)
via=$(grep -o 'via [^ ]*' <<<"$route" | cut -d' ' -f2)
[ -n "$dev" ] && [ -n "$src" ] || exit 0
# the MAC of the next hop: frames to a single address are acknowledged and resent on wifi, broadcast ones are not
hop=${via:-$DESKTOP}
ping -c 1 -W 1 -I "$dev" "$hop" >/dev/null 2>&1
mac=$(ip neigh show "$hop" dev "$dev" | grep -o 'lladdr [^ ]*' | cut -d' ' -f2)
[ -n "$mac" ] || mac=ff:ff:ff:ff:ff:ff

if [ -d $T ] && [ "$(cat $T/enabled)" = 1 ] && [ "$(cat $T/dev_name)" = "$dev" ] &&
    [ "$(cat $T/local_ip)" = "$src" ] && [ "$(cat $T/remote_mac)" = "$mac" ]; then
    exit 0
fi
[ -d $T ] || mkdir $T
[ "$(cat $T/enabled)" = 1 ] && echo 0 >$T/enabled
echo "$dev" >$T/dev_name
echo "$src" >$T/local_ip
echo "$DESKTOP" >$T/remote_ip
echo 6666 >$T/remote_port
echo "$mac" >$T/remote_mac
# sequence numbers (to count lost messages) and the host name with every message
echo 1 >$T/extended
mkdir -p $T/userdata/host
hostname >$T/userdata/host/value
echo 1 >$T/enabled
logger -t netconsole-desktop "sending kernel messages to $DESKTOP:6666 over $dev ($src, next hop $mac)"
