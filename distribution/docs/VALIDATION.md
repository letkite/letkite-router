# Letkite Router OS distribution — engineering validation log

Validated 2026-11-08 on independent Compute-1 workspace. **Not production release or flashing authorization.**

## Builds

| Profile | ImageBuilder | Packages | Result |
|---|---|---:|---|
| ax3000t base | OpenWrt 25.12.6 mediatek/filogic | 166 | PASS (BIOS not applicable), sysupgrade tar |
| ax3000t proxy | OpenWrt 25.12.6 mediatek/filogic | 169 | PASS, sing-box 1.13.21 in SquashFS |
| x86-full base | OpenWrt 25.12.6 x86/64 | 239 | PASS, combined BIOS & UEFI ext4 and SquashFS |

The official downloaded ImageBuilder tarballs were verified against upstream target sha256sums before extraction.
Local image SHA256SUMS files all verified successfully for completed variants.

### AX3000T

- Base image 9,595,168 bytes (9.6 MB decimal), build exit=0.
- Proxy image 21,596,448 bytes (21.6 MB decimal), build exit=0.
- Proxy image SHA256: `be54fdb7c775fe833dea8d43822329c90f78d2cee4dae145bc7d1481e577effc`.
- Verified `/usr/bin/sing-box`, `/etc/init.d/sing-box` and WireGuard in extracted SquashFS.
- `/etc/uci-defaults/95-letkite-os` now explicitly disables unconfigured sing-box and dockerd on first boot; verified present in built proxy image. Runtime execution of this startup script is **not yet independently tested on AX3000T hardware**.

### x86 Full

- Initial build failed because OpenWrt's default 104 MiB ext4 root partition cannot hold Docker image contents.
- Rebuilt with `ROOTFS_PARTSIZE=512` (512 MiB), success (exit=0).
- All four combined BIOS/UEFI, ext4/SquashFS `.img.gz` output SHA256SUMS verified.
- Explicitly located `/usr/bin/dockerd`, `/usr/bin/docker`, `/usr/bin/wg`, `/etc/init.d/dockerd`, LuCI Dockerman menu/JS files, and safe-firstboot script in build root.
- qemu-system-x86_64 TCG BIOS smoke uses no network interface and a snapshot writable virtual disk; observed Linux 6.12.112, ext4 root mount, `/sbin/init`, procd initialization, console login prompt, and WireGuard kernel driver loaded. Not a container functionality test.

## Limits and release gates

- Letkite Agent **not embedded** yet, to avoid interfering with concurrently developed packages. Current upstream README mandates a verified signed agent executable in firmware for actual preinstallation; the OpenWrt package alone is not the agent.
- AX3000T only stock OpenWrt layout `xiaomi_mi-router-ax3000t`. RD03v2 and U-Boot mod excluded. Xiaomi BE6500 Pro RD08 excluded pending QSDK BSP / ART mapping / OEM trust enforcement.
- No real AX3000T firmware flashed or tested; read-only OEM recovery research only.
- Docker daemon and containers not yet launched/tested in a guest network; Docker data-root must be on SSD and firewall/NAT interactions tested.
- sing-box packaged but no proxy profiles or nftables TProxy setup; test DNS/IPv6/routing/kill-switch in isolated lab before enabling.
- Need real boot on target devices, config persistence, WAN/LAN/wifi functionality, updates, factory reset, power interruption, recovery and signed distribution releases.
- Build image artifacts live under Compute-1 `/home/cp1/workspace/router-os-check/letkite-router/distribution/out/` and are deliberately git-ignored, not pushed into source history.
