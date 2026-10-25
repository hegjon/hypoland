#!/bin/bash
# Sends the logs of the test machines to the desktop, so the last minutes before a machine dies (the T550
# switched itself off during a soak on 2026-10-24 and kept nothing) can be read there. soak.sh logs the CPU
# temperature to the journal every minute for that. Run the machine step for every new test machine.
#
#   sudo ./forward-logs.sh desktop               on the desktop: receive both, see below
#   ./forward-logs.sh machine <desktop address> <ssh host>...   send from these machines (over ssh as root)
#
# Two ways, for two kinds of death:
# - The journal, with systemd-journal-upload over http to port 19532. Complete and reliable: a machine that loses
#   the desktop (switched off, asleep) retries every 30 s and catches up from where it stopped. But only what
#   journald already wrote gets out, a machine that dies loses its last seconds. The desktop keeps one journal
#   per sending address in /var/log/journal/remote/ (readable by the group systemd-journal-remote):
#     journalctl -D /var/log/journal/remote _HOSTNAME=aa -b -1 -e
# - The kernel log, with netconsole over UDP to port 6666 (netconsole-desktop.sh). The kernel sends every message
#   the moment it is printed, also from an oops or a panic, without disk or user space; journald forwards its
#   notice and higher messages (soak.sh's temperature line too) into the kernel log, so they go out the same way.
#   UDP is not resent, but the kernel's sequence numbers show every lost message. Over wifi the last words of a
#   panic or a hard lockup may still not get out, the driver needs too much of the machine for that. The desktop
#   writes one file per machine to /var/log/netconsole/<hostname>.log (netconsole-receiver.py).
# Nothing gets out when the firmware cuts the power (an overheating cut-off): then the temperature trail is all.
set -eu
here=$(dirname "$(realpath "$0")")

case "${1:-}" in
desktop)
    [ "$(id -u)" = 0 ] || { echo "run as root" >&2; exit 1; }
    # the journal receiver loads it at runtime for http, without it the socket's service fails at once
    pacman -S --needed --noconfirm libmicrohttpd
    mkdir -p /etc/systemd/system/systemd-journal-remote.service.d
    cat >/etc/systemd/system/systemd-journal-remote.service.d/http.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/lib/systemd/systemd-journal-remote --listen-http=-3 --output=/var/log/journal/remote/
EOF
    # the netconsole receiver runs as the user who ran sudo, so the logs are theirs to read
    user=${SUDO_USER:-root}
    install -Dm755 "$here/netconsole-receiver.py" /usr/local/lib/hypoland/netconsole-receiver.py
    install -d -o "$user" -m 755 /var/log/netconsole
    cat >/etc/systemd/system/netconsole-receiver.service <<EOF
[Unit]
Description=netconsole messages of the Hypoland test machines
After=network.target

[Service]
User=$user
ExecStart=/usr/local/lib/hypoland/netconsole-receiver.py /var/log/netconsole 6666
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl reset-failed systemd-journal-remote.socket systemd-journal-remote.service 2>/dev/null || true
    systemctl enable --now systemd-journal-remote.socket
    systemctl enable netconsole-receiver.service
    systemctl restart netconsole-receiver.service # also to load a new receiver
    if command -v ufw >/dev/null; then
        ufw allow from 192.168.1.0/24 to any port 19532 proto tcp comment journal-remote
        ufw allow from 192.168.1.0/24 to any port 6666 proto udp comment netconsole
    fi
    systemctl --no-pager is-active systemd-journal-remote.socket netconsole-receiver.service
    ;;
machine)
    desktop=$2
    shift 2
    for h in "$@"; do
        echo "== $h"
        # the journal
        ssh "root@$h" "mkdir -p /etc/systemd/journal-upload.conf.d &&
            printf '[Upload]\nURL=http://$desktop:19532\n' >/etc/systemd/journal-upload.conf.d/desktop.conf &&
            mkdir -p /etc/systemd/system/systemd-journal-upload.service.d &&
            printf '[Unit]\nStartLimitIntervalSec=0\n[Service]\nRestart=always\nRestartSec=30\n' \
                >/etc/systemd/system/systemd-journal-upload.service.d/retry.conf &&
            systemctl daemon-reload && { systemctl reset-failed systemd-journal-upload.service 2>/dev/null || true; } &&
            systemctl enable systemd-journal-upload.service && systemctl restart systemd-journal-upload.service"
        # netconsole: at boot and whenever NetworkManager brings a link up or changes an address
        ssh "root@$h" "install -m 755 /dev/stdin /usr/local/sbin/netconsole-desktop" <"$here/netconsole-desktop.sh"
        ssh "root@$h" "set -e
            echo DESKTOP=$desktop >/etc/netconsole-desktop.conf
            cat >/etc/systemd/system/netconsole-desktop.service <<'EOF'
[Unit]
Description=Send kernel messages to the desktop (netconsole)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/netconsole-desktop

[Install]
WantedBy=multi-user.target
EOF
            mkdir -p /etc/NetworkManager/dispatcher.d
            printf '#!/bin/sh\ncase \"\$2\" in up | down | dhcp4-change) exec /usr/local/sbin/netconsole-desktop ;; esac\n' \
                >/etc/NetworkManager/dispatcher.d/90-netconsole-desktop
            chmod 755 /etc/NetworkManager/dispatcher.d/90-netconsole-desktop
            # every kernel message to the consoles (Omarchy boots quiet, with 0), so netconsole sends them all
            echo 'kernel.printk = 8 4 1 7' >/etc/sysctl.d/90-netconsole.conf
            sysctl -q -p /etc/sysctl.d/90-netconsole.conf
            mkdir -p /etc/systemd/journald.conf.d
            printf '[Journal]\nForwardToKMsg=yes\nMaxLevelKMsg=notice\n' >/etc/systemd/journald.conf.d/kmsg.conf
            systemctl restart systemd-journald
            systemctl daemon-reload
            systemctl enable netconsole-desktop.service
            /usr/local/sbin/netconsole-desktop
            echo \"<5>netconsole test from \$(hostname)\" >/dev/kmsg
            journalctl -t netconsole-desktop -n 1 -o cat"
    done
    ;;
*)
    sed -n '2,/^[^#]/s/^# \{0,1\}//p' "$0"
    exit 1
    ;;
esac
