#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
INSTALLER_URL=https://github.com/gtxaspec/wyze-campan4-sd-install.git
STOCK_ROM=${1:?Usage: $0 stock-full-dump.bin [output-dir]}
OUTPUT_DIR=${2:-$REPO_ROOT/output/panv4-diag-layout}
PANV4_TEMP_ROOT=${PANV4_TEMP_ROOT:-/tmp}

case "$STOCK_ROM" in
	/*) ;;
	*) STOCK_ROM=$(CDPATH='' cd -- "$(dirname -- "$STOCK_ROM")" && pwd)/$(basename -- "$STOCK_ROM") ;;
esac
case "$OUTPUT_DIR" in
	/*) ;;
	*) OUTPUT_DIR=$REPO_ROOT/$OUTPUT_DIR ;;
esac

[ -f "$STOCK_ROM" ] || {
	echo "Stock dump not found: $STOCK_ROM" >&2
	exit 1
}
[ ! -e "$OUTPUT_DIR" ] || {
	echo "Output path already exists: $OUTPUT_DIR" >&2
	exit 1
}
mkdir -p "$OUTPUT_DIR" "$PANV4_TEMP_ROOT"
WORK_DIR=$(mktemp -d "$PANV4_TEMP_ROOT/wyze-panv4-layout.XXXXXX")
INSTALLER_DIR=$WORK_DIR/wyze-campan4-sd-install

git clone --depth 1 "$INSTALLER_URL" "$INSTALLER_DIR"
cp "$SCRIPT_DIR/wyze-panv4-diagnostics.sh" "$INSTALLER_DIR/rootfs/wyze-panv4-diagnostics.sh"
chmod 0755 "$INSTALLER_DIR/rootfs/wyze-panv4-diagnostics.sh"
printf '%s\n' layout >"$INSTALLER_DIR/rootfs/panv4-diag-mode"

cat >"$INSTALLER_DIR/rootfs/linuxrc" <<'LINUXRC'
#!/bin/sh
export PATH=/bin:/sbin

is_mounted() {
	target=$1
	[ -r /proc/mounts ] || return 1
	while IFS= read -r line; do
		fields=${line#* }
		mountpoint=${fields%% *}
		[ "$mountpoint" = "$target" ] && return 0
	done < /proc/mounts
	return 1
}

mount_if_needed() {
	target=$1
	fstype=$2
	device=$3
	if is_mounted "$target"; then
		echo "$target already mounted"
	else
		mkdir -p "$target"
		mount -t "$fstype" "$device" "$target" || echo "Could not mount $target"
	fi
}

mkdir -p /proc /sys /tmp /dev
mount_if_needed /proc proc proc
mount_if_needed /sys sysfs sysfs
mount_if_needed /tmp tmpfs tmpfs
mount_if_needed /dev devtmpfs devtmpfs
mount_if_needed /tmp/sd vfat /dev/mmcblk0p1

echo "Pan v4 read-only partition diagnostic"
mode=$(cat /panv4-diag-mode 2>/dev/null)
/wyze-panv4-diagnostics.sh "$mode"
sleep 30
reboot -f
LINUXRC
chmod 0755 "$INSTALLER_DIR/rootfs/linuxrc"
cp "$INSTALLER_DIR/rootfs/uboot.bin" "$WORK_DIR/uboot.bin"
cp "$INSTALLER_DIR/rootfs/uboot-env.bin" "$WORK_DIR/uboot-env.bin"

if ! (cd "$INSTALLER_DIR" && ./build.sh "$STOCK_ROM" "$WORK_DIR/uboot.bin" "$WORK_DIR/uboot-env.bin") >"$OUTPUT_DIR/build.log" 2>&1; then
	tail -n 80 "$OUTPUT_DIR/build.log" >&2
	exit 1
fi
cp "$INSTALLER_DIR/factory_wcpanv4_uvc" "$OUTPUT_DIR/factory_wcpanv4_uvc"
tail -n 25 "$OUTPUT_DIR/build.log"
echo "Diagnostic FIT: $OUTPUT_DIR/factory_wcpanv4_uvc"
echo "Build worktree: $WORK_DIR"
