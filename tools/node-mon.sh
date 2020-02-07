#!/usr/bin/env bash

trap "exit" INT TERM ERR
trap "kill 0" EXIT


/usr/share/bcc/tools/tcptop -C 1 >/var/log/io-tcptop.log 2>&1 &
/usr/share/bcc/tools/ext4slower -j 1 >/var/log/io-ext4slower-machine.log 2>&1 &
/usr/share/bcc/tools/ext4dist 1 >/var/log/io-ext4dist.log 2>&1 &
/usr/share/bcc/tools/biotop -C 1 >/var/log/io-biosnoop.log 2>&1 &
iotop -botqk >/var/log/io-iotop.log 2>&1 &
top -ba >/var/log/io-topbymem.log 2>&1 &


wait
