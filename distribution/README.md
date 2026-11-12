# LetKite Router OS: image builds

**Status: engineering preview.** These are not released or signed firmware images,
and nothing here has been flashed on real hardware yet.

`scripts/build-image.sh` builds OpenWrt images for two profiles with the official
OpenWrt ImageBuilder:

| Profile | Device | OpenWrt target / profile | Packages on top of OpenWrt's defaults |
|---|---|---|---|
| `ax3000t` | Xiaomi Mi Router AX3000T, stock flash layout | `mediatek/filogic` / `xiaomi_mi-router-ax3000t` | LuCI over HTTPS, WireGuard |
| `x86-full` | x86_64 soft router or VM | `x86/64` / `generic` | the same, plus Docker (off until you turn it on) |

The images change nothing else in OpenWrt:
- no transparent proxy, firewall or LAN/WAN/WLAN changes;
- no credentials or node keys;
- no LetKite agent yet (see "LetKite" below).

## Build

On Linux x86_64 with `bash`, `curl`, `sha256sum`, `tar`, `zstd`, `make`, `awk`, `grep`, `python3`, the
[ImageBuilder prerequisites](https://openwrt.org/docs/guide-user/additional-software/imagebuilder) and about 5 GiB of disk:

```sh
distribution/scripts/build-image.sh --profile ax3000t --dry-run   # what it would build
distribution/scripts/build-image.sh --profile ax3000t
distribution/scripts/build-image.sh --profile x86-full
```

- The ImageBuilder comes from `downloads.openwrt.org` for `OPENWRT_VERSION` (25.12.6 by default). It is checked against
  the release's `sha256sums` before use.
- A cached copy is re-checked on every run. It is extracted again unless the extracted tree came from that exact archive.
- Images land in `distribution/out/<profile>/` with their own `SHA256SUMS`; earlier outputs for the profile are removed first.
- `ENABLE_DOCKER=0` leaves Docker out of `x86-full`; the AX3000T profile refuses Docker.
- `IMAGEBUILDER_CACHE` moves the download cache (default `distribution/.cache/`).

`distribution/tests/test-profiles.sh` checks the profiles and switches without building (CI runs it).
`distribution/tests/qemu-offline-smoke.py IMAGE` boots an x86 image in QEMU with no network
and checks first boot and Docker.

## Flashing the AX3000T

Follow the OpenWrt device page for the AX3000T and your exact hardware revision; check that your hardware revision
and flash chip are supported before you flash.
- The `ax3000t` profile is OpenWrt's **stock-layout** image (`xiaomi_mi-router-ax3000t`). The OpenWrt U-Boot layout
  (`-ubootmod`) is a different profile, and this build does not produce it.
- ImageBuilder makes only the `*-squashfs-sysupgrade.bin`, not the initramfs images. The first installation from
  Xiaomi's firmware therefore uses OpenWrt's own `*-initramfs-factory.ubi` for the same version, as the device page
  describes. Then flash this build's `sysupgrade.bin` from that OpenWrt (LuCI, or `sysupgrade -n`).

## Docker (x86-full)

Docker is installed but disabled at first boot (`files/etc/uci-defaults/95-letkite-os`). Before you enable it:
- give it a persistent data root on an SSD;
- keep its TCP socket off;
- limit memory and log size.

The x86 image's root partition is 512 MiB (`ROOTFS_MB` in the profile), because the default 104 MiB does not hold
Docker and LuCI.

## LetKite

The agent is not in the images yet. Flash the image, then install the agent and its LuCI page from the LetKite feed,
or with the one-line install script (see the repository [README](../README.md)).

`ENABLE_LETKITE=1` is refused. Building the signed `letkite-agent` and `luci-app-letkite` packages into an image needs:
- a way to verify the feed's signature inside ImageBuilder;
- a tested way for a pre-installed agent to be paired on first boot.

Neither is qualified yet. When they are, the image will carry the existing packages unchanged. The agent's own
`install` writes the router's local limits (`ceiling.toml`, the router template); the image does not write them.

## Tested (2026-11-12, OpenWrt 25.12.6)

- `x86-full`: built ext4 and squashfs, BIOS and EFI images. `qemu-offline-smoke.py` passes all six checks on the ext4
  BIOS image: first-boot marker, uci-defaults applied, Docker disabled at boot, the daemon starts by hand, and an
  offline image imports and runs. The manifest has LuCI with uhttpd and HTTPS, WireGuard and Docker, and no proxy software.
- `ax3000t`: built `squashfs-sysupgrade.bin` (9.6 MB). The manifest has the MT7981 Wi-Fi drivers, LuCI with HTTPS and
  WireGuard, and no Docker or proxy software. **Not flashed on hardware.**
- A second build reuses the verified ImageBuilder (17 s for `ax3000t`); a cache tree whose marker does not match the
  archive is extracted again.

## Not in this build

- Proxy software (sing-box, Mihomo): not planned for these images.
- Other devices, including the Xiaomi BE6500 Pro (RD08): there is no profile for them.
