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
- qemu-system-x86_64 TCG BIOS smoke uses no network interface and a snapshot writable virtual disk; observed Linux 6.12.112, ext4 root mount, `/sbin/init`, procd initialization, console login prompt, and WireGuard kernel driver loaded. After an early-command race was corrected, a later QEMU guest session verified that `/etc/uci-defaults/95-letkite-os` had executed, Docker autostart was disabled (`/etc/init.d/dockerd enabled` returned 1), and Docker was not active by default. A deliberate `/etc/init.d/dockerd start`, followed by 18 seconds, returned Docker Engine 29.6.1 with `overlayfs` through `docker info`; `docker network ls` listed bridge/host/none and exited successfully. This was in an isolated VM with no guest network interface. The initial probe sent commands too early (before uci-defaults) and incorrectly observed Docker API unavailable; that initial failure was a startup timing artifact. Running a real container is still a separate test.

## Limits and release gates

- Letkite Agent **not embedded**; the new explicit opt-in fails closed before ImageBuilder (see integration validation below). Current upstream README mandates a verified signed agent executable in firmware for actual preinstallation; the OpenWrt package alone is not the agent.
- AX3000T only stock OpenWrt layout `xiaomi_mi-router-ax3000t`. RD03v2 and U-Boot mod excluded. Xiaomi BE6500 Pro RD08 excluded pending QSDK BSP / ART mapping / OEM trust enforcement.
- No real AX3000T firmware flashed or tested; read-only OEM recovery research only.
- Docker daemon **has been started and queried successfully** in a network-isolated QEMU guest; actual container launch and network forwarding are not yet qualified. Docker data-root must be on SSD, and firewall/NAT interactions still need testing.
- sing-box packaged but no proxy profiles or nftables TProxy setup; test DNS/IPv6/routing/kill-switch in isolated lab before enabling.
- Need real boot on target devices, config persistence, WAN/LAN/wifi functionality, updates, factory reset, power interruption, recovery and signed distribution releases.
- Build image artifacts live under Compute-1 `/home/cp1/workspace/router-os-check/letkite-router/distribution/out/` and are deliberately git-ignored, not pushed into source history.

## Repeatable isolated Docker container smoke

A standalone stdlib test is now tracked in `distribution/tests/qemu-offline-smoke.py`. The test operates on a decompressed x86 ext4 BIOS combined image, with QEMU TCG, snapshot-only disk writes, and `-net none`. It waits until the system is initialized, verifies the brand marker and executed `uci-defaults`, confirms Docker is **disabled by default**, manually starts Docker, builds an offline tiny root filesystem from the guest BusyBox + musl/libgcc, imports it as an image, and executes a container with `--network none`.

Example:

```bash
gzip -dc distribution/out/x86-full-base/openwrt-25.12.6-x86-64-generic-ext4-combined.img.gz > /tmp/letkite-x86.img
python3 distribution/tests/qemu-offline-smoke.py /tmp/letkite-x86.img --log /tmp/letkite-x86-boot.log
```

Observed on Compute-1 (2026-11-08): exit code **0**, all six checks **PASS**:

```text
PASS firstboot marker
PASS uci defaults applied
PASS Docker disabled by default
PASS Docker daemon
PASS image imported
PASS container ran
```

Docker reported version 29.6.1 and `overlayfs`. The guest printed `LK_CONTAINER_OK` and `LK_CONTAINER_RC:0` from an actual containerized `/bin/busybox echo`. An earlier test image lacked `libgcc_s.so.1` and failed at dynamic linking; adding that library resolved the *test image* issue, not an OS/daemon bug. Serial logs on Compute-1: `/home/cp1/workspace/router-os-check/x86-qemu-ci-smoke.log`.

**Still not tested:** real WAN/LAN bridging, DNS and IPv6 policy, Docker traffic isolation vs fw4, actual hardware, SSD data-root, or power-failure recovery. The QEMU test validates offline core container execution, not deployable router networking or security posture.

## System integration gate validation — 2026-11-08

This change is a partial integration with a deliberately blocked provider, not a
successful agent-enabled firmware build. No device was touched, and no new
ImageBuilder build was attempted. Historical base/proxy/x86 build results above
were not rerun for this change.

Executed in this workspace:

| Check | Result |
|---|---|
| `bash -n distribution/scripts/build-image.sh distribution/tests/test-profiles.sh` | PASS |
| `sh -n distribution/scripts/letkite-health.sh` | PASS |
| `bash distribution/tests/test-profiles.sh` | PASS: existing variants, opt-in off equivalence, unsupported profiles, invalid toggle, blocked opt-in including non-dry/no network or make |
| `python3 distribution/tests/test-agent.py` | PASS: 8 offline tests |
| `bash tests/unit/setup.sh` | PASS: 21 |
| `bash tests/unit/fetch.sh` | PASS: 58 |
| `bash tests/unit/release-table.sh` | PASS: 35 |
| `python3 scripts/release-table.py check` with release environment overrides unset | PASS: official 1.6.1 table matches signed release |
| `git diff --check` | PASS |
| `node --test tests/unit/overview.cjs` | NOT RUN: `node: command not found` |

The new fixture generates an ephemeral Ed25519 key under a temporary directory,
signs synthetic release metadata, and validates x86_64/aarch64 artifacts without
executing them or using the network. It rejects wrong hash/architecture,
missing binary, non-0755 permissions, old claim version, invalid signature and
missing metadata. It verifies preflight leaves inputs unchanged and returns no
fixture program contents. No fixture is installed into an image. Profile tests
confirm no agent/device configuration in the default overlay and refusal before
any provider access; because no output is generated, no device credentials can
be baked by this path. These tests do **not** prove an enabled-image happy path.

Authentication evidence: existing release-table verification authenticated the
pinned 1.6.1 release using the repository agent release keys. HTTP HEAD requests
to the official 25.12 `packages.adb` and `letkite-apk.pem` endpoints both returned
200. **No apk metadata signature, package payload, or claim-capable version was
authenticated for image integration.** Endpoint availability is not a trust
claim. No feed key was committed based solely on that download.

Remaining gates: independently authenticate and pin the official apk feed key;
qualify signed metadata/package installation in ImageBuilder; compare installed
package release table to the signed executable; advance the package pin through
the separate authorized release workflow; prove the newer claim CLI contract in
an isolated VM. Then test early claim ordering, restrictive ceiling, service
restart/rollback, keep-list backup/restore, unclaim and factory reset. The health
helper has syntax validation only; router execution remains untested. ShellCheck
is unavailable locally. Existing CI retains package/lifecycle tests and now runs
the distribution offline preflight as well. No production safety or merge
readiness is asserted.
