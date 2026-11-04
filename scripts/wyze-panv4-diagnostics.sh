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
	state="not mounted"
	while IFS= read -r line; do
		remainder=${line#* }
		mountpoint=${remainder%% *}
		if [ "$mountpoint" = "$path" ]; then
			state="mounted"
			break
		fi
	done </proc/mounts
	echo "$label ($path): $state"
}

echo "Wyze Cam Pan v4 diagnostics (read-only)"

show_layout() {
	show_file "kernel command line" /proc/cmdline
	show_file "MTD partitions" /proc/mtd
	echo "--- MTD device nodes ---"
	ls -l /dev/mtd* /dev/mtdblock* 2>&1
}

show_mounts() {
	echo "--- mount status ---"
	mount_state proc /proc
	mount_state sysfs /sys
	mount_state tmpfs /tmp
	mount_state devtmpfs /dev
	mount_state sdcard /tmp/sd
	show_file mounts /proc/mounts
	show_file "block devices" /proc/partitions
	show_file "MTD partitions" /proc/mtd
}

case "${1:-all}" in
	layout) show_layout ;;
	mounts) show_mounts ;;
	all)
		show_layout
		show_mounts
		;;
	*)
		echo "Usage: $0 [layout|mounts|all]" >&2
		exit 2
		;;
esac
