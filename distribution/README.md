# Letkite Router OS — distribution prototype

**Status: engineering preview, NOT an installable firmware release.** This directory is separate from the existing `packages/letkite-agent` and `packages/luci-app-letkite`, which are developed independently.

## Design

- OpenWrt 25.12.6 based images for Xiaomi AX3000T **RD03/RD23 (stock layout only)** and x86_64.
- Feature profiles: Lite (LuCI, WireGuard; optional sing-box), x86 Full (same plus optional Docker runtime).
- No default transparent proxy / TProxy / firewall rewrites. Users configure their own compliant VPN or proxy service explicitly after installation.
- No credentials, node keys, enrollment identities or OEM proprietary binaries in images.
- This prototype **does not embed Letkite Agent**. After verifying hardware and flashing an officially supported OpenWrt device, install the agent from the signed package feed using the repository's top-level README. This separation prevents conflicts with the ongoing agent development; future agent preinstallation must provide a verified architecture-matched executable, use `claim=1`, and pass all existing setup tests.
- All image building is **offline with respect to devices**. It never runs sysupgrade, mtd, ubiformat, or modifies a router.

## Build

Requirements: Linux x86_64, `curl`, `sha256sum`, `tar`, `zstd`, `make`, `python3`; disk space at least 5 GiB.

```sh
distribution/scripts/build-image.sh --profile ax3000t --dry-run
distribution/scripts/build-image.sh --profile x86-full --dry-run
distribution/scripts/build-image.sh --profile ax3000t
distribution/scripts/build-image.sh --profile x86-full
```

The script downloads the official OpenWrt ImageBuilder and checks its SHA-256 using the **same official release target's** `sha256sums` before extracting. Outputs are under `distribution/out/<profile>/`; no image is flashed.

Variables: `OPENWRT_VERSION` (defaults to pinned 25.12.6), `ENABLE_PROXY=1` to include the sing-box binary only, `ENABLE_DOCKER=0` to omit Docker from x86; `IMAGEBUILDER_CACHE` for downloads. `sing-box` being included does NOT activate traffic interception. Confirm storage requirements and plugin availability per target.

### Device safety

AX3000T RD03/RD23 only. **RD03v2 is not compatible.** The profile is for OpenWrt's **stock layout** `xiaomi_mi-router-ax3000t`; never flash on U-Boot mod partitions or unverified NAND variants. First installation is NOT equivalent to `sysupgrade`: follow the exact OpenWrt device wiki for the hardware revision and bootloader. Images built here are not qualified for a production flash.

## BE6500 Pro RD08

**Research-only; deliberately no build profile.** Xiaomi stock uses Qualcomm IPQ5332, kernel 5.4.213 and proprietary QCA WLAN/NSS/PPE, with device-specific ART calibration. OpenWrt ImageBuilder images are not a safe replacement. See `docs/rd08-vendor-boundary.md`.

## Docker

Docker is disabled for AX3000T: limited RAM/NAND and no external disk. The x86-full profile carries `dockerd`, `docker` and related container networking packages; for production use place Docker data-root on persistent SSD; the x86 image build reserves a 512 MiB root partition because the default 104 MiB ext4 partition was too small, disable remote TCP socket, limit memory and log size, and verify image kernel features on QEMU hardware before enabling services.

## VPN / proxy

WireGuard and LuCI protocol integration are standard. Optional sing-box is an **unconfigured component**. A transparent gateway requires a separate, audited configuration for nftables TPROXY, DNS behavior, policy routing, IPv6, kill-switch and recovery; not part of this first safety-focused build.

## Validation

```sh
distribution/tests/test-profiles.sh
```

No production signing key is included. Before a production release add image signature + manifest, hardware compatibility gating, recovery/rollback tests, and reproducible source/feeds locks.
