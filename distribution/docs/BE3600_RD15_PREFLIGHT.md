# Xiaomi BE3600 2.5G (RD15) — Win11 pre-flash readiness, 2026-11-17

**Status: RESEARCH / READ-ONLY ONLY. No production Letkite RD15 image exists. NO FLASH AUTHORIZATION.**

## Source baseline
- Current Letkite Router OS PR #15 remote head at start of this prep: `dbb333748d24c9be0d5e5e84d253ce76fb619229`; original dev local branch diverged, preserved intact. A new Compute-1 isolated worktree `/home/cp1/workspace/router-os-check/letkite-router-be3600` uses the refreshed PR base.
- Experimental RD15 port source: https://github.com/victorpivotto-cloud/openwrt-xiaomi-be3600-rd15 at `d9c8a55a1eedf0956f85f0ef2a591a30d0415464` (fetched to `/home/cp1/workspace/router-os-check/be3600-rd15-upstream`).
- It extends https://github.com/fivefold3/openwrt-gl-be3600 at pinned `BASE_COMMIT=e46ea77ba4f431c72301c3d07220e454450b3070`; target `qualcommbe/ipq53xx`, kernel 6.18 snapshot. **Not an official OpenWrt release for RD15.**
- Stock image reference retrieved from Xiaomi CDN, `miwifi_rd15_firmware_0321a_1.0.87.bin`, 28 MB, sha256 `cb2d7e40a74c33439fe61e78f1c2c08bf4effdb6617214118f3da783fd7a5c0a` matched the port author's reference exactly. Private local path: `/home/cp1/workspace/router-os-check/be3600-stock-reference/`. Do not commit proprietary blobs.
- xmir-patcher issue #177 discusses 1.0.87 SSH, but root access must be independently authorized and checked. Never infer flash compatibility merely from SSH access.

## Hardware/flash uncertainty
- Target candidate is Xiaomi BE3600 **2.5G** **RD15** (international naming RN06 can differ); other BE3600 variants such as RD16 are not interchangeable.
- Tested upstream RD15: IPQ5332, QCN6432, 256 MiB physical RAM (far less free after reserved firmware, ~35 MiB), 128 MiB SPI-NAND, 2 KiB NAND page, 128 KiB block; **NAND model, PHY and geometry must be read on this unit**.
- Two 42 MiB firmware slots `rootfs` and `rootfs_1`. ART/calibration, bdata, APPSBL, MIBIB must never be overwritten with another unit's data. Preserve untouched stock slot and full private backups.
- The experimental installed upstream port has three 1GbE LAN working but **2.5G PHY/port remains unqualified**; the separate RAM-only PHY experiment does not certify installed firmware. Letkite/Mihomo may be too large for available 42 MB slot and very low free RAM. Do not enable Docker.
- Upstream factory.ubi is explicitly **unqualified** as a stock-to-OpenWrt path. Upstream initial install needs OEM root, verified **1.8 V** UART console, OpenWrt initramfs RAM boot, image/partition checks and readback before slot-0 modification. **No one-click stock install** exists here.

## Win11 host side
- First use a 1GbE LAN to an isolated PC. Do not connect test router to production WAN. Confirm model and exact stock firmware in Xiaomi web UI, not by guess.
- Windows built-in OpenSSH (`ssh.exe`, `scp.exe`) and local PowerShell are sufficient for host preflight; build should run on separate Linux/WSL2 or Compute-1. Do not assume Xiaomi's Windows recovery tool supports Windows 11 — Xiaomi's download page lists older Windows restrictions; investigate and test a compatible recovery environment BEFORE flash.
- A private Win11 kit is delivered separately with PowerShell read-only TCP/adapter/tool inventory and an optional router-side read-only `/proc/mtd` / device-tree script, available to the user in the conversation. It does **not** perform SSH exploitation or flash writes.
- 1.8 V (not 3.3/5 V) UART adapter mandatory for the known install path. Verify pinout and voltages with a meter; leave VCC disconnected. Don't assume UART enabled in OEM environment.

## Gates to move to actual install
1. Confirm bottom sticker board model, firmware region/version, router GUI access and Win11 Ethernet link.
2. Read-only fingerprint `/proc/device-tree/model`, compatible, `/proc/mtd`, UBI volume map, MTD page/block geometry and exact NAND chip. If no authorized shell yet, establish recovery and consent before any unlocking workflow.
3. Full device-unique private backup and checksum verification (both firmware slots, boot environment, ART/bdata, FIT, bootloaders and partitions) — stored privately, not GitHub.
4. Test 1.8 V serial and verify a non-destructive RAM initramfs boot before writing flash.
5. Build a *device/firmware/PHY matched* Letkite image on upstream RD15 source (not AX3000T image), estimate image size, RAM budget, signed agent version/claim compatibility, and validate restore path. The current Letkite agent pin 1.6.1 does not satisfy unattended claim contract.
6. Only after all above gates, request separate user authorization for partition-specific changes. No automated writes yet.

## References
- https://github.com/victorpivotto-cloud/openwrt-xiaomi-be3600-rd15/blob/main/docs/hardware.md
- https://github.com/victorpivotto-cloud/openwrt-xiaomi-be3600-rd15/blob/main/docs/installing.md
- https://github.com/victorpivotto-cloud/openwrt-xiaomi-be3600-rd15/blob/main/docs/limitations.md
- https://github.com/victorpivotto-cloud/openwrt-xiaomi-be3600-rd15/blob/main/docs/recovery-and-rollback.md
- https://github.com/openwrt-xiaomi/xmir-patcher/issues/177
- https://www.miwifi.com/miwifi_download.html
