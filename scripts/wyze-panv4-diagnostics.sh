#!/bin/sh

show_file() {
	label="$1"
	file="$2"
	echo "--- $label ---"
	if [ -r "$file" ]; then
		cat "$file"
	else
		echo "unavailable: $file"
	fi
}

mount_state() {
	label="$1"
	path="$2"
	state=$(awk -v path="$path" '$2 == path { found = 1 } END { if (found) print "mounted"; else print "not mounted" }' /proc/mounts)
	echo "$label ($path): $state"
}

echo "Wyze Cam Pan v4 diagnostics (read-only)"
show_file "kernel command line" /proc/cmdline
show_file "MTD partitions" /proc/mtd

echo "--- MTD device nodes ---"
ls -l /dev/mtd* /dev/mtdblock* 2>&1

echo "--- mount status ---"
mount_state proc /proc
mount_state sysfs /sys
mount_state tmpfs /tmp
mount_state devtmpfs /dev
mount_state sdcard /tmp/sd
show_file mounts /proc/mounts
show_file block devices /proc/partitions
