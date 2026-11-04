#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)
INSTALLER_URL=https://github.com/gtxaspec/wyze-campan4-sd-install.git
STOCK_ROM=${1:?Usage: $0 stock-full-dump.bin thingino-full.bin uboot.bin uboot-env.bin [output-dir]}
FIRMWARE_BIN=${2:?Usage: $0 stock-full-dump.bin thingino-full.bin uboot.bin uboot-env.bin [output-dir]}
UBOOT_IMAGE=${3:?Usage: $0 stock-full-dump.bin thingino-full.bin uboot.bin uboot-env.bin [output-dir]}
UBOOT_ENV=${4:?Usage: $0 stock-full-dump.bin thingino-full.bin uboot.bin uboot-env.bin [output-dir]}
OUTPUT_DIR=${5:-$REPO_ROOT/output/panv4-sd-card}
PANV4_TEMP_ROOT=${PANV4_TEMP_ROOT:-/tmp}

absolute_path() {
	case "$1" in
		/*) printf '%s\n' "$1" ;;
		*) printf '%s/%s\n' "$(CDPATH='' cd -- "$(dirname -- "$1")" && pwd)" "$(basename -- "$1")" ;;
	esac
}

STOCK_ROM=$(absolute_path "$STOCK_ROM")
FIRMWARE_BIN=$(absolute_path "$FIRMWARE_BIN")
UBOOT_IMAGE=$(absolute_path "$UBOOT_IMAGE")
UBOOT_ENV=$(absolute_path "$UBOOT_ENV")
case "$OUTPUT_DIR" in
	/*) ;;
	*) OUTPUT_DIR=$REPO_ROOT/$OUTPUT_DIR ;;
esac

for input in "$STOCK_ROM" "$FIRMWARE_BIN" "$UBOOT_IMAGE" "$UBOOT_ENV"; do
	[ -f "$input" ] || {
		echo "Input file not found: $input" >&2
		exit 1
	}
done
[ ! -e "$OUTPUT_DIR" ] || {
	echo "Output path already exists: $OUTPUT_DIR" >&2
	exit 1
}
mkdir -p "$OUTPUT_DIR" "$PANV4_TEMP_ROOT"
WORK_DIR=$(mktemp -d "$PANV4_TEMP_ROOT/wyze-panv4-sd-card.XXXXXX")
INSTALLER_DIR=$WORK_DIR/wyze-campan4-sd-install

git clone --depth 1 "$INSTALLER_URL" "$INSTALLER_DIR"

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
		return 0
	fi
	mkdir -p "$target"
	mount -t "$fstype" "$device" "$target"
}

same_hash() {
	hash_one=$(sha256sum "$1") || return 1
	hash_two=$(sha256sum "$2") || return 1
	hash_one=${hash_one%% *}
	hash_two=${hash_two%% *}
	[ "$hash_one" = "$hash_two" ]
}

abort_before_write() {
	echo "ERROR: $1; flash has not been modified"
	sync
	sleep 30
	reboot -f
}

abort_during_install() {
	echo "ERROR: $1; flash may be partially updated"
	echo "Leave the camera powered and use UART recovery"
	while :; do sleep 60; done
}

expect_mtd() {
	expected="$1: $2 00008000 \"$3\""
	while IFS= read -r actual; do
		[ "$actual" = "$expected" ] && return 0
	done < /proc/mtd
	return 1
}

echo "Thingino SD installer - Wyze Cam Pan v4"
mkdir -p /proc /sys /tmp /dev
mount_if_needed /proc proc proc || abort_before_write "cannot mount proc"
mount_if_needed /sys sysfs sysfs || abort_before_write "cannot mount sysfs"
mount_if_needed /tmp tmpfs tmpfs || abort_before_write "cannot mount tmpfs"
mount_if_needed /dev devtmpfs devtmpfs || echo "devtmpfs mount failed; checking existing device nodes"
mkdir -p /tmp/sd
mount_if_needed /tmp/sd vfat /dev/mmcblk0p1 || abort_before_write "cannot mount SD card"

expect_mtd mtd0 00030000 uboot || abort_before_write "unexpected mtd0 layout"
expect_mtd mtd1 00470000 boot || abort_before_write "unexpected mtd1 layout"
expect_mtd mtd2 00580000 system || abort_before_write "unexpected mtd2 layout"
expect_mtd mtd3 00580000 back || abort_before_write "unexpected mtd3 layout"
expect_mtd mtd4 00050000 cfg || abort_before_write "unexpected mtd4 layout"
expect_mtd mtd5 00010000 provisioning || abort_before_write "unexpected mtd5 layout"

for node in /dev/mtd0 /dev/mtd1 /dev/mtd2 /dev/mtd3 /dev/mtd4 /dev/mtd5; do
	[ -c "$node" ] || abort_before_write "missing MTD node $node"
done
[ -f /tmp/sd/autoupdate-full.bin ] || abort_before_write "missing autoupdate-full.bin at SD root"
[ -f /uboot.bin ] || abort_before_write "missing Thingino U-Boot image"
[ -f /uboot-env.bin ] || abort_before_write "missing Thingino U-Boot environment"
command -v flash_eraseall >/dev/null 2>&1 || abort_before_write "flash_eraseall is unavailable"

BACKUP_DIR=/tmp/sd/wyze-backup-panv4
mkdir -p "$BACKUP_DIR"
echo "Backing up and verifying stock MTD partitions before flash writes"
for part in mtd0:uboot mtd1:boot mtd2:system mtd3:back mtd4:cfg mtd5:provisioning; do
	device=${part%%:*}
	name=${part#*:}
	echo "Backing up $device ($name)"
	dd if="/dev/$device" of="$BACKUP_DIR/$name.bin" bs=4096 || abort_before_write "backup read failed for $device"
	dd if="/dev/$device" of="/tmp/$name-verify.bin" bs=4096 2>/dev/null || abort_before_write "verification read failed for $device"
	same_hash "$BACKUP_DIR/$name.bin" "/tmp/$name-verify.bin" || abort_before_write "backup verification failed for $device"
done

cat "$BACKUP_DIR/uboot.bin" "$BACKUP_DIR/boot.bin" "$BACKUP_DIR/system.bin" \
	"$BACKUP_DIR/back.bin" "$BACKUP_DIR/cfg.bin" "$BACKUP_DIR/provisioning.bin" \
	> "$BACKUP_DIR/full-backup.bin" || abort_before_write "could not assemble full backup"
BACKUP_SIZE=$(wc -c < "$BACKUP_DIR/full-backup.bin")
[ "$BACKUP_SIZE" -eq 16777216 ] || abort_before_write "full backup is not 16 MiB"
sha256sum "$BACKUP_DIR/full-backup.bin" > "$BACKUP_DIR/full-backup.sha256" || abort_before_write "could not hash full backup"
sha256sum "$BACKUP_DIR/uboot.bin" "$BACKUP_DIR/boot.bin" "$BACKUP_DIR/system.bin" \
	"$BACKUP_DIR/back.bin" "$BACKUP_DIR/cfg.bin" "$BACKUP_DIR/provisioning.bin" \
	> "$BACKUP_DIR/partitions.sha256" || abort_before_write "could not hash partition backups"
sync
echo "All partition backups verified; beginning bootloader install"

UBOOT_SIZE=$(wc -c < /uboot.bin)
ENV_SIZE=$(wc -c < /uboot-env.bin)
[ "$UBOOT_SIZE" -ge 196608 ] || abort_before_write "U-Boot image is unexpectedly small"
[ "$UBOOT_SIZE" -le 327680 ] || abort_before_write "U-Boot image exceeds 320 KiB"
[ "$ENV_SIZE" -gt 0 ] || abort_before_write "U-Boot environment is empty"
[ "$ENV_SIZE" -le 65536 ] || abort_before_write "U-Boot environment exceeds 64 KiB"

flash_eraseall /dev/mtd0 || abort_during_install "erase mtd0 failed"
flash_eraseall /dev/mtd1 || abort_during_install "erase mtd1 failed"
dd if=/uboot.bin of=/dev/mtd0 bs=256 count=768 || abort_during_install "write U-Boot first segment failed"
dd if=/uboot.bin of=/dev/mtd1 bs=256 skip=768 || abort_during_install "write U-Boot second segment failed"
dd if=/uboot-env.bin of=/dev/mtd1 bs=256 seek=512 || abort_during_install "write U-Boot environment failed"
sync

dd if=/dev/mtd0 of=/tmp/uboot-readback-first.bin bs=256 count=768 || abort_during_install "readback mtd0 failed"
dd if=/dev/mtd1 of=/tmp/uboot-readback-second.bin bs=256 count=512 || abort_during_install "readback mtd1 failed"
cat /tmp/uboot-readback-first.bin /tmp/uboot-readback-second.bin > /tmp/uboot-readback-padded.bin || abort_during_install "assemble U-Boot readback failed"
dd if=/tmp/uboot-readback-padded.bin of=/tmp/uboot-readback.bin bs=1 count="$UBOOT_SIZE" || abort_during_install "trim U-Boot readback failed"
same_hash /uboot.bin /tmp/uboot-readback.bin || abort_during_install "U-Boot readback verification failed"
dd if=/dev/mtd1 of=/tmp/env-readback.bin bs=1 skip=131072 count="$ENV_SIZE" || abort_during_install "readback environment failed"
same_hash /uboot-env.bin /tmp/env-readback.bin || abort_during_install "environment readback verification failed"

echo "Bootloader and environment verified. Rebooting with SD inserted for firmware auto-update."
sync
sleep 3
reboot -f
LINUXRC
chmod 0755 "$INSTALLER_DIR/rootfs/linuxrc"
sh -n "$INSTALLER_DIR/rootfs/linuxrc"

if ! (cd "$INSTALLER_DIR" && ./build.sh "$STOCK_ROM" "$UBOOT_IMAGE" "$UBOOT_ENV") >"$OUTPUT_DIR/build.log" 2>&1; then
	tail -n 100 "$OUTPUT_DIR/build.log" >&2
	exit 1
fi
cp "$INSTALLER_DIR/factory_wcpanv4_uvc" "$OUTPUT_DIR/factory_wcpanv4_uvc"
cp "$FIRMWARE_BIN" "$OUTPUT_DIR/autoupdate-full.bin"
(
	cd "$OUTPUT_DIR"
	sha256sum factory_wcpanv4_uvc autoupdate-full.bin >SHA256SUMS
)
cat >"$OUTPUT_DIR/README.txt" <<'NOTES'
Wyze Cam Pan v4 Thingino SD installer bundle

Copy factory_wcpanv4_uvc and autoupdate-full.bin to the root of a FAT32 SD card.
The installer backs up and verifies the stock MTD partitions before writing the
bootloader. Leave the card inserted through the firmware auto-update reboot.
Remove it after Thingino boots successfully. The stock partition backups are
saved under wyze-backup-panv4/ on the SD card.
NOTES

tail -n 30 "$OUTPUT_DIR/build.log"
echo "SD card files staged at: $OUTPUT_DIR"
echo "Copy the two files there to the root of the FAT32 card."
echo "Build worktree: $WORK_DIR"
