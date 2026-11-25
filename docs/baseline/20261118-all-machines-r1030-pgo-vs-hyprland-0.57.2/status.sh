#!/bin/bash
# status.sh : one line per machine of the night-20261118 run: blocks done, the last log line, checks, core dumps since the start
for h in ${HOSTS:-x200 t550 xps lianli chromebook t460s t490 samsung-i5 macmini-m1 hp-amd p14s macmini-intel}; do
    printf '%-11s ' $h
    timeout 20 ssh -o BatchMode=yes -o ConnectTimeout=6 root@$h 'R=/root/abnight/night-20261118; [ -d ${R}b ] && R=${R}b; cd $R 2>/dev/null || { echo no run; exit; }
        printf "hyp=%s stock=%s %s | " $(ls hypoland-[0-9]*.txt 2>/dev/null | grep -vc startup) $(ls hyprland-[0-9]*.txt 2>/dev/null | grep -vc startup) "$([ -e done ] && echo DONE)"
        for c in hypoland-check.txt hyprland-check.txt; do [ -e $c ] && printf "%s %s/%s " ${c%%-*} $(grep -c ^PASS $c) $(grep -c ^FAIL $c); done
        printf "cores=%s | " "$(coredumpctl list --since "2026-11-18 20:34" --no-legend 2>/dev/null | awk "{print \$(NF-1)}" | xargs -r -n1 basename | sort | uniq -c | tr -s " " | tr "\n" ",")"
        tail -1 log | cut -c12-110' 2>&1 | tail -1 || echo unreachable
done
