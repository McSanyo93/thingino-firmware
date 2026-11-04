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
git clone --recurse-submodules https://github.com/themactep/thingino-firmware.git
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

The camera profile and defconfig are in the main repo. Apply these two
bring-up edits if your clone has not picked them up yet:

1. In
   `configs/cameras-exp/wyze_campan4_t32nq_sc835hai_atbm6162s/thingino.json`,
   change:

   ```json
   "ircut": "72 73"
   ```

   to:

   ```json
   "ircut": "73 72"
   ```

2. In `package/ingenic-sdk/ingenic-sdk.mk`, make the kernel-release query
   suppress the nested make banner. The line should read:

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

The tested SD card was 64 GB, FAT32, with one partition (`FAT32 XINT13`). Copy
the built image to its root as exactly `autoupdate-full.bin`; the installer
stopped with `ERROR: missing autoupdate-full.bin` when it could not find that
path/name. The user's card also contained `factory_wcpanv4_uvc`; preserve that
vendor file if following the same stock-card setup.

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
resource busy` after the bootloader verification. The camera was then rebooted
without the card and came up running Thingino; in this run that unmount message
was not a failed flash. Confirm the boot and network access before treating an
installation as complete.

The temporary installer tested during the original bring-up was built outside
this checkout from `gtxaspec/wyze-campan4-sd-install`. The fourth build script
now embeds a reconstructed partition-aware `rootfs/linuxrc` and stages the
FIT plus firmware image. This reconstruction has not yet been run on the
camera. To adapt the upstream `rootfs/linuxrc` for installation:

1. Create mount points before mounting. If devtmpfs is already mounted at
   `/dev`, keep using it instead of trying to mount it again or replacing its
   device nodes.
2. Use the observed MTD map above. Do not treat `/dev/mtd0` as a 16 MiB NOR
   device: it is only 192 KiB. Back up each MTD partition separately, verify
   each backup against a second read, and do not proceed to writes unless all
   partitions verify.
3. Write the 320 KiB Thingino U-Boot across the stock `uboot` and `boot`
   partitions. The environment starts at absolute flash offset `0x50000`,
   which is `0x20000` into `mtd1`. Erase only the required aligned flash area
   and verify U-Boot and environment by reading them back.
4. Keep the full Thingino image at the SD root as `autoupdate-full.bin` for
   the subsequent firmware update. The tested installer rebooted after
   verifying the bootloader; after that reboot the camera started Thingino.

The successful installer printed `umount: can't unmount /tmp/sd: Device or
resource busy` after verification because a log file was still open on the
card. The camera nevertheless rebooted successfully without the SD card. Keep
the verified stock backups from the card for recovery.

## First boot notes

- Web UI and SSH worked before video was fixed.
- Correct ISP module arguments restored video and stopped the repeating VIC
  interrupt errors. If the camera boots with no video, inspect
  `/etc/modules.d/20-isp` and `dmesg`.
- Correct IR-cut GPIO ordering fixed the magenta color cast and makes the
  day/night controller use the working direction persistently.
- This bring-up did not establish stock-firmware restoration instructions.
  Retain the raw stock firmware dump and the installer-created MTD backups.
