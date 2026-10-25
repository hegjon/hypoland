#!/bin/sh
i=0
while [ $i -lt 120 ]; do printf '\033[48;2;255;0;255m%400s' ''; i=$((i + 1)); done
sleep 60
