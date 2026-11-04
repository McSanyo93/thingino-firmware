Wyze Cam Pan v4
===============

## Hardware

- SoC: Ingenic T32NQ (T32 family)
- Image sensor: SmartSens SC835HAI
- Wi-Fi: ATBM6162S
- Flash: 16 MiB SPI NOR
- Thingino profile: `wyze_campan4_t32nq_sc835hai_atbm6162s`

The profile is experimental. The stock-to-Thingino SD-card installation below
was confirmed on one camera running stock firmware. It is not a general
recovery procedure for other Pan v4 hardware or firmware revisions.

## Build a firmware image from a fresh clone

Use an x86_64 or aarch64 Linux host with the packages listed by
`scripts/dep_check.sh`. Clone the main repo, initialize submodules, and run
the repository update step:

```sh
git clone --recurse-submodules https://github.com/McSanyo93/thingino-firmware.git
cd thingino-firmware
make update
```

Build the experimental Pan v4 profile with the top-level Makefile:

```sh
CAMERA=wyze_campan4_t32nq_sc835hai_atbm6162s GROUP=exp make
```

The full image is named
`thingino-wyze_campan4_t32nq_sc835hai_atbm6162s.bin` and is 16 MiB. Use the
path printed by the build; output directories vary by branch, kernel, and libc.

## Stock dump and build inputs

The diagnostic and installer FITs are built from a full 16 MiB stock flash
dump. The dump is used as the source of the vendor FIT container that the
external SD installer builder modifies. The scripts do not flash the dump,
and the dump is not needed for an ordinary Thingino source build.

The file used during bring-up was
`firmware_T32NQ_20261027_0316.bin` (16,777,216 bytes, SHA-256
`563cf447a06d1c876746012a5a29ba17df1280c6e8a6c0e5a57656cbef104862`). Keep
the dump locally. `.gitignore` excludes that filename so it cannot be added
accidentally; do not publish the proprietary stock image or generated FITs.
The FITs are reproducible build outputs and are regenerated from the local
dump when needed.

The builder scripts clone `gtxaspec/wyze-campan4-sd-install` into temporary
directories. They do not copy that external repository into this fork. Logs,
temporary checkouts, and generated artifacts are kept under `/tmp` and the
ignored `output/` directory.

The working profile needs these ISP settings in its defconfig:

```text
BR2_ISP_CLK_MPLL=y
BR2_ISP_CLK_225MHZ=y
BR2_ISP_CLKA_VPLL=y
BR2_ISP_CLKA_400MHZ=y
BR2_ISP_CLKS_VPLL=y
BR2_ISP_CLKS_400MHZ=y
BR2_ISP_CLKV_VPLL=y
BR2_ISP_CLKV_400MHZ=y
KERNEL_VERSION_4=y
```

The Pan v4 profile in this fork already contains the following bring-up
settings. They were needed to get video and correct day/night colors. The
`thingino.json` GPIO order is also the tested persistent IR-cut direction.

1. The final value in
   `configs/cameras-exp/wyze_campan4_t32nq_sc835hai_atbm6162s/thingino.json`,
   is:

   ```json
   "ircut": "73 72"
   ```

2. In `package/ingenic-sdk/ingenic-sdk.mk`, the kernel-release query
   suppresses the nested make banner:

   ```make
   krel="$$( $(MAKE) -s --no-print-directory -C $(LINUX_DIR) kernelrelease 2>/dev/null )"; \
   ```

   This keeps the nested make directory banner out of generated package
   output.

Build through the top-level Makefile. A prior ad-hoc Buildroot rootfs
finalization lost the exported clock variables and produced a bare `tx_isp_`
line in `/etc/modules.d/20-isp`. The working image contains:

```text
tx_isp_t32 clk_name=mpll isp_clk=225000000 clka_name=vpll isp_clka=400000000 clks_name=vpll isp_clks=400000000 clkv_name=vpll isp_clkv=400000000 direct_mode=0 print_level=1
```

## Installing over stock with an SD card

The built `.bin` is a full SPI-flash image. It does not boot Thingino directly
from the SD card; it is staged there for the installer and written to internal
flash.

This camera's stock bootloader does not install the normal Thingino image
directly. The successful installation used an adapted SD-card installer that
first backed up and verified the camera's MTD partitions, then installed the
bootloader and let the device continue the firmware update on reboot. Do not
write the full image directly to `/dev/mtd0`: on stock, `mtd0` is only the
192 KiB U-Boot partition, not the whole flash.

The stock firmware reported this flash layout:

| MTD | Size | Stock name |
|---|---:|---|
| mtd0 | 192 KiB | uboot |
| mtd1 | 4,544 KiB | boot |
| mtd2 | 5,632 KiB | system |
| mtd3 | 5,632 KiB | back |
| mtd4 | 320 KiB | cfg |
| mtd5 | 64 KiB | provisioning |

### What the FIT files do

FIT is the U-Boot Flattened Image Tree container. The stock SD boot path looks
for a file named `factory_wcpanv4_uvc`; the external builder takes the vendor
FIT from the stock dump and substitutes a small temporary ramdisk. Its FIT
signature-bypass technique allows the stock bootloader to start that ramdisk
from the SD card. The diagnostic FITs only run their report and reboot. They
do not erase or write SPI flash.

The installer FIT uses the same boot path but carries the installer
`/linuxrc` instead. It is the only FIT in this workflow that writes flash.
The stock dump is a build input for both types of FIT; it is not placed on the
SD card as `autoupdate-full.bin`.

### Read-only diagnostics used to identify the layout

Before installing, we booted the temporary Pan v4 diagnostic environment from
the SD card. It ran from a read-only squashfs root in RAM (`root=/dev/ram0`,
`ro`) and mounted the SD partition at `/tmp/sd`; it did not write to SPI flash.
The MTD table came from the running kernel's `/proc/mtd`. These same checks can
be run from a root shell on the camera:

```sh
cat /proc/cmdline
cat /proc/mtd
ls -l /dev/mtd* /dev/mtdblock*
cat /proc/mounts
```

`/proc/cmdline` also showed the stock partition map:

```text
mtdparts=sfc0_nor:192K(uboot),4544K(boot),5632K(system),5632K(back),320K(cfg),64K(provisioning)
```

The device-node listing confirmed each MTD partition had both character nodes
(`/dev/mtdN`, `/dev/mtdNro`) and block nodes (`/dev/mtdblockN`). The mount
listing showed the diagnostic root was squashfs read-only and the SD card was
mounted at `/tmp/sd`. A second no-write mount diagnostic reported proc, sysfs,
tmpfs, and devtmpfs status and printed `/proc/mounts`; it confirmed the SD
card was detected and mounted. These outputs established that the diagnostic
environment could read the stock partition table without flashing anything.

The read-only report script is `scripts/wyze-panv4-diagnostics.sh`. It has
`layout` and `mounts` modes. The two diagnostic builders below place it in a
temporary ramdisk and call it from `/linuxrc` after mounting proc, sysfs,
tmpfs, devtmpfs, and the SD card. They stop after printing the report and do
not run flash erase or write commands.

#### Rebuilding the read-only SD diagnostic

The bootable diagnostic ramdisk uses the separate
[`wyze-campan4-sd-install`](https://github.com/gtxaspec/wyze-campan4-sd-install)
project. Build the two read-only diagnostic payloads with:

```sh
scripts/wyze-panv4-build-diag-layout.sh /path/to/stock-full-dump.bin
scripts/wyze-panv4-build-diag-mounts.sh /path/to/stock-full-dump.bin
```

Each command clones the upstream FIT builder, builds a separate
`factory_wcpanv4_uvc`, and saves its complete log plus output under `output/`.
Copy one FIT at a time to the FAT32 card root and capture the startup report.
The layout report shows `/proc/cmdline`, `/proc/mtd`, and flash device nodes;
the mount report checks proc, sysfs, tmpfs, devtmpfs, and `/tmp/sd`.

The tested SD card was 64 GB, FAT32, with one partition (`FAT32 XINT13`). For
the diagnostic step, copy one diagnostic FIT to the root using the exact name
`factory_wcpanv4_uvc`. For installation, copy both the installer FIT as
`factory_wcpanv4_uvc` and the Thingino full image as exactly
`autoupdate-full.bin`. The installer stopped with
`ERROR: missing autoupdate-full.bin` when that exact path/name was absent.
The stock card originally contained `factory_wcpanv4_uvc`; the installer FIT
replaces that file for the boot attempt.

### Four build scripts

Run the commands from the Thingino fork checkout. The stock dump can be stored
outside the checkout; the example below uses a local file path:

```sh
STOCK_DUMP=/path/to/firmware_T32NQ_20261027_0316.bin

scripts/wyze-panv4-build-diag-layout.sh "$STOCK_DUMP"
scripts/wyze-panv4-build-diag-mounts.sh "$STOCK_DUMP"
scripts/wyze-panv4-build-firmware.sh
```

The first two scripts each clone the external FIT builder, add the diagnostic
report script, build a separate FIT, and save the output plus full build log
under `output/panv4-diag-layout/` and `output/panv4-diag-mounts/`. Both FITs
have the same filename, `factory_wcpanv4_uvc`; use one at a time. The firmware
script clones this fork to a temporary work directory, runs `make update`,
builds the U-Boot target, then builds the complete firmware image. Its
`artifacts.txt` lists the firmware, U-Boot, and environment file paths. Full
logs remain in that temporary work directory.

Build the installer bundle from those paths:

```sh
scripts/wyze-panv4-build-sd-card.sh \
  "$STOCK_DUMP" \
  /path/to/thingino-wyze_campan4_t32nq_sc835hai_atbm6162s.bin \
  /path/to/u-boot-with-tpl-lzma.bin \
  /path/to/u-boot-env.bin
```

The final script clones the external FIT builder into `/tmp`, replaces its
`rootfs/linuxrc` with the partition-aware installer, and produces an ignored
`output/panv4-sd-card/` directory containing `factory_wcpanv4_uvc`,
`autoupdate-full.bin`, `SHA256SUMS`, and a card README. It does not clone or
commit the external project into this fork. None of the four build scripts
flashes the camera; the installer FIT writes flash only when booted on the
camera.

The committed installer `linuxrc` is a reconstruction of the temporary
installer used during the original successful installation. It checks the
exact MTD layout, backs up each MTD partition, reads each partition a second
time and verifies its hash, and saves a 16 MiB reconstructed stock backup and
hashes to the SD card before any flash write. It then erases the stock U-Boot
and boot partitions, writes the Thingino U-Boot across the 192 KiB `mtd0` and
the first 128 KiB of `mtd1` (the 320 KiB U-Boot slot), and writes the
environment at absolute flash offset `0x50000` (`0x20000` within `mtd1`). It
reads back and verifies U-Boot and environment before rebooting. The new
bootloader then applies
`autoupdate-full.bin`; leave the SD card inserted until Thingino boots.

The temporary installer used in the original bring-up was confirmed to boot
Thingino. The installer payload reconstructed in the committed script has
not yet been tested on the camera. Treat it as experimental and keep UART
recovery access available.

The working sequence was:

1. Build the firmware as described above and copy the full image to the FAT32
   card root as `autoupdate-full.bin`.
2. Boot stock with the card inserted and run the adapted installer. It saved
   each stock MTD partition to the card and verified the backups before
   writing the bootloader.
3. Wait for the installer to report that the bootloader and environment were
   verified. Leave the card inserted while the new bootloader applies
   `autoupdate-full.bin` and reboots into Thingino.
4. After Thingino boots, remove the card and verify that the Web UI and SSH
   respond on the network.

The successful installer printed `umount: can't unmount /tmp/sd: Device or
resource busy` after verification because a log file was still open on the
card. The camera nevertheless rebooted successfully without the SD card. Keep
the verified stock backups from the card for recovery. Confirm the boot and
network access before treating an installation as complete.

## First boot notes

- Web UI and SSH worked before video was fixed.
- Correct ISP module arguments restored video and stopped the repeating VIC
  interrupt errors. If the camera boots with no video, inspect
  `/etc/modules.d/20-isp` and `dmesg`.
- Correct IR-cut GPIO ordering fixed the magenta color cast and makes the
  day/night controller use the working direction persistently.
- This bring-up did not establish stock-firmware restoration instructions.
  Retain the raw stock firmware dump and the installer-created MTD backups.
