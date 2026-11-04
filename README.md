Thingino
--------

## Wyze Cam Pan v4 bring-up (experimental)

This fork includes a camera-specific profile for the Wyze Cam Pan v4 with an
Ingenic T32NQ, SC835HAI sensor, and ATBM6162S Wi-Fi. The profile and the
stock-to-Thingino bring-up were tested on one camera. Hardware revisions and
stock firmware versions may differ.

### Build from a fresh clone

```sh
git clone --recurse-submodules git@github.com:McSanyo93/thingino-firmware.git
cd thingino-firmware
make update
CAMERA=wyze_campan4_t32nq_sc835hai_atbm6162s GROUP=exp make
```

This builds the full 16 MiB SPI flash image. `make update` initializes the
Buildroot source, applies patches, and prepares the toolchain.

The output is a flash image staged on the SD card for the adapted installer;
it does not run Thingino from the SD card. The tested stock card was 64 GB,
FAT32, and used the exact filename `autoupdate-full.bin`. The installer first
backed up and verified the stock flash, then installed the Thingino
bootloader. **The adapted SD installer is not included in this repo**, so the
firmware image alone is not sufficient to reproduce installation over stock.

### Adapt the stock SD installer

The diagnostic boot and installer were made from
[`gtxaspec/wyze-campan4-sd-install`](https://github.com/gtxaspec/wyze-campan4-sd-install).
Clone that project separately, copy this repo's read-only diagnostic script
into its `rootfs/`, and call it from `rootfs/linuxrc` after the pseudo-filesystems
and SD card are mounted. For a diagnostic-only image, call the script and
pause before any install logic:

```sh
/wyze-panv4-diagnostics.sh
sleep 30
reboot -f
```

The temporary boot uses the stock U-Boot FIT signature bypass implemented by
that external builder. To build the diagnostic FIT with the stock full dump
and the U-Boot plus environment files from the Thingino build:

```sh
git clone https://github.com/gtxaspec/wyze-campan4-sd-install.git
cd wyze-campan4-sd-install
cp /path/to/thingino-firmware/scripts/wyze-panv4-diagnostics.sh rootfs/
STOCK_DUMP=/path/to/stock-full-dump.bin
UBOOT_IMAGE=/path/to/output/images/u-boot-with-spl-lzma.bin
UBOOT_ENV=/path/to/output/images/u-boot-env.bin
./build.sh "$STOCK_DUMP" "$UBOOT_IMAGE" "$UBOOT_ENV"
```

Replace the example paths with the stock dump and image paths from your build;
the U-Boot image filename can vary by configuration.

That creates `factory_wcpanv4_uvc`, which boots the temporary ramdisk. For an
installer, replace the diagnostic-only `linuxrc` with a partition-aware
installer: create mount points first, tolerate devtmpfs already mounted, back
up and verify every MTD partition before writing, and target the 192 KiB
`mtd0` plus the first 128 KiB of `mtd1` for the 320 KiB U-Boot image. The
environment is at flash offset `0x50000` (offset `0x20000` within `mtd1`).
Never treat `/dev/mtd0` as a raw 16 MiB flash device. The exact partition map,
diagnostic steps, and observed installer behavior are in
[`docs/cameras/wyze-cam-pan-v4.md`](docs/cameras/wyze-cam-pan-v4.md).

The camera's read-only startup diagnostics are documented in
[`docs/cameras/wyze-cam-pan-v4.md`](docs/cameras/wyze-cam-pan-v4.md). The
script [`scripts/wyze-panv4-diagnostics.sh`](scripts/wyze-panv4-diagnostics.sh)
prints the kernel command line, MTD partitions, MTD device nodes, and mounts.
The tested ISP clocks and IR-cut GPIO order are recorded in the Pan v4
defconfig and `thingino.json`.

---

Thingino (_/θinˈdʒiːno/_, _thin-jee-no_) is an open-source firmware for Ingenic SoC IP cameras.

![Thingino Web UI][10]

### Supported Hardware

Please find [the full list of supported cameras](docs/hardware/supported-hardware.md)
in a separate document. Visit [our website][0] for an illustrated version of
the list.

---

### Thingino Repository Branches Explaned

We've split the Thingino repository into two branches: stable and master, to better manage development and provide reliable releases for users.

**Ciao Branch**

Provides a reliable, tested version of Thingino for general use. It includes carefully selected, stable changes. It uses the original ONVIF server and Prudynt with libconfig.
The ciao branch will receive critical fixes. New features will only be added once they are thoroughly tested and mature in the master branch.

For users who want a dependable version of Thingino without needing to build or contribute to development.

**Master Branch**

The development hub for new features and experimental changes. Includes advanced features, and uses the new [raptor][13] streamer. These are still in development and may not be stable.

Only for developers and contributors who can build the project themselves and actively participate in improving the code.

> [!WARNING]
> The master branch uses a highly experimental maineline U-Boot.
> - Having access to the UART port on the camera and unbricking skills is **highly recommended** when building images from the master branch.

This structure allows us to maintain a reliable version (stable) for most users while continuing to innovate and test new features (master). Critical fixes and matured features from master will be gradually integrated into stable for broader use.

> [!NOTE]
> If you’re not contributing to development, we recommend sticking with the stable branch.

Thank you for using Thingino! For questions or contributions, please join our Discord community or check the GitHub issues page.

### Building

```
git clone --recurse-submodules https://github.com/themactep/thingino-firmware
cd thingino-firmware
make update
make
```

Read [Building from sources][7] article for more info.

### Building in a Container

```
git clone --recurse-submodules https://github.com/themactep/thingino-firmware
cd thingino-firmware
./build-container.sh
```

The build uses a prebuilt image from
[ghcr.io/themactep/thingino-builder-image](https://github.com/themactep/thingino-builder-image),
pulled automatically on first run. Requires Podman or Docker.

Read [Building in a container](docs/build/container.md) for more info.

### Documentation

- [Firmware Image Structure](docs/firmware/firmware-image-structure.md) - Partition layout and image assembly
- [Firmware Dumping](docs/firmware/firmware.md) - How to backup existing firmware
- [Camera Recovery](docs/firmware/camera-recovery.md) - Recovering from failed updates
- [Local Build Settings](docs/build/local-build-settings.md) - Layered user-specific settings from `THINGINO_USER_DIR/common`, per camera, and per device IP

### Resources

- [Project Website][0]
- [Project Wiki][1]
- Buildroot Manual [HTML][5] [PDF][6]
- [Discord channel][3]
- [Telegram group][4]

### GitHub CI Status

[![toolchain-x86_64][11]][8]
[![firmware-stable][12]][9]

[0]: https://thingino.com/
[1]: https://github.com/themactep/thingino-firmware/wiki
[3]: https://discord.gg/xDmqS944zr
[4]: https://t.me/thingino
[5]: https://buildroot.org/downloads/manual/manual.html
[6]: https://nightly.buildroot.org/manual.pdf
[7]: https://github.com/themactep/thingino-firmware/wiki/Building-from-sources
[8]: https://github.com/themactep/thingino-firmware/actions/workflows/toolchain.yaml
[9]: https://github.com/themactep/thingino-firmware/actions/workflows/firmware.yaml
[10]: https://github.com/user-attachments/assets/5e74827c-47f9-4ea0-b523-d12a199a9974
[11]: https://github.com/themactep/thingino-firmware/actions/workflows/toolchain-x86_64.yaml/badge.svg
[12]: https://github.com/themactep/thingino-firmware/actions/workflows/firmware-stable.yml/badge.svg
[13]: http://github.com/gtxaspec/raptor
