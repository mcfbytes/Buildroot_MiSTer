#!/bin/sh
# Delete the phantom SCSI LUN a JMicron JMS583 exposes with an empty slot (it is
# never-ready and stalls SCSI shutdown). A populated drive registers a block
# device and is skipped.

s="/sys/class/scsi_device/$1/device"
[ -d "$s" ] || exit 0

d=$(readlink -f "$s")
while [ -n "$d" ] && [ "$d" != "/" ]; do
	[ -f "$d/idVendor" ] && break
	d=$(dirname "$d")
done
[ "$(cat "$d/idVendor" 2>/dev/null)" = "152d" ] || exit 0
[ "$(cat "$d/idProduct" 2>/dev/null)" = "0583" ] || exit 0

n=0
while [ "$n" -lt 15 ]; do
	[ -d "$s" ] || exit 0
	[ -n "$(ls "$s/block" 2>/dev/null)" ] && exit 0
	sleep 1
	n=$((n + 1))
done

echo offline > "$s/state" 2>/dev/null
echo 1 > "$s/delete" 2>/dev/null
