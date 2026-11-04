#!/bin/sh

set -eu

CAMERA=wyze_campan4_t32nq_sc835hai_atbm6162s
REPO_URL=${THINGINO_REPO_URL:-https://github.com/McSanyo93/thingino-firmware.git}
PANV4_TEMP_ROOT=${PANV4_TEMP_ROOT:-/tmp}

if printf '%s' "$PATH" | awk -v RS=: '$0 ~ /[[:space:]]/ { found = 1 } END { exit !found }'; then
	PATH=$(printf '%s' "$PATH" | awk -v RS=: '$0 !~ /[[:space:]]/ { if (path != "") path = path ":"; path = path $0 } END { print path }')
	export PATH
	echo "Removed PATH entries containing whitespace for Buildroot compatibility."
fi

if [ "$#" -gt 1 ]; then
	echo "Usage: $0 [work-dir]" >&2
	exit 2
fi

mkdir -p "$PANV4_TEMP_ROOT"
if [ "$#" -eq 1 ]; then
	WORK_DIR=$1
	case "$WORK_DIR" in
		/*) ;;
		*) WORK_DIR=$PWD/$WORK_DIR ;;
	esac
	[ ! -e "$WORK_DIR" ] || {
		echo "Work path already exists: $WORK_DIR" >&2
		exit 1
	}
	mkdir -p "$WORK_DIR"
else
	WORK_DIR=$(mktemp -d "$PANV4_TEMP_ROOT/wyze-panv4-firmware.XXXXXX")
fi

REPO_DIR=$WORK_DIR/thingino-firmware
OUTPUT_DIR=$WORK_DIR/firmware-output
git clone --recurse-submodules "$REPO_URL" "$REPO_DIR"

if ! (cd "$REPO_DIR" && WORKFLOW=1 make update) >"$WORK_DIR/update.log" 2>&1; then
	tail -n 80 "$WORK_DIR/update.log" >&2
	exit 1
fi
tail -n 25 "$WORK_DIR/update.log"

if ! (cd "$REPO_DIR" && WORKFLOW=1 CAMERA="$CAMERA" GROUP=exp PRISTINE=1 THINGINO_OUTPUT_DIR="$OUTPUT_DIR" make br-uboot) >"$WORK_DIR/uboot.log" 2>&1; then
	tail -n 80 "$WORK_DIR/uboot.log" >&2
	exit 1
fi
tail -n 25 "$WORK_DIR/uboot.log"

if ! (cd "$REPO_DIR" && WORKFLOW=1 CAMERA="$CAMERA" GROUP=exp PRISTINE=1 THINGINO_OUTPUT_DIR="$OUTPUT_DIR" make fast) >"$WORK_DIR/firmware.log" 2>&1; then
	tail -n 100 "$WORK_DIR/firmware.log" >&2
	exit 1
fi
tail -n 40 "$WORK_DIR/firmware.log"

UBOOT_IMAGE=
for candidate in u-boot-lzo-with-spl.bin u-boot-with-spl-lzma.bin u-boot-with-tpl-lzma.bin; do
	if [ -f "$OUTPUT_DIR/images/$candidate" ]; then
		UBOOT_IMAGE=$OUTPUT_DIR/images/$candidate
		break
	fi
done
UBOOT_ENV=$OUTPUT_DIR/images/u-boot-env.bin
FIRMWARE_BIN=$OUTPUT_DIR/images/thingino-$CAMERA.bin
[ -n "$UBOOT_IMAGE" ] || {
	echo "Could not find the built U-Boot image under $OUTPUT_DIR/images" >&2
	exit 1
}
[ -f "$UBOOT_ENV" ] || {
	echo "U-Boot environment not found: $UBOOT_ENV" >&2
	exit 1
}
[ -f "$FIRMWARE_BIN" ] || {
	echo "Full firmware image not found: $FIRMWARE_BIN" >&2
	exit 1
}

cat >"$WORK_DIR/artifacts.txt" <<EOF
FIRMWARE_BIN=$FIRMWARE_BIN
UBOOT_IMAGE=$UBOOT_IMAGE
UBOOT_ENV=$UBOOT_ENV
EOF

echo "Build worktree: $WORK_DIR"
echo "Full firmware: $FIRMWARE_BIN"
echo "U-Boot image: $UBOOT_IMAGE"
echo "U-Boot env: $UBOOT_ENV"
echo "Artifact list: $WORK_DIR/artifacts.txt"
