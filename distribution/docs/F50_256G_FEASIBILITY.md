# F50 256GB / MU300 — Letkite Embedded OpenWrt Feasibility Assessment

**Date:** 2026-11-11 (Singapore time)  
**Scope:** Read-only public-source research, checksum validation, static ELF analysis and ARM64 disassembly. No physical device accessed, no image flashed, no binaries executed on the target.  
**Recommendation:** **Engineering feasibility: HIGH** for a device-specific Letkite OpenWrt build. **Stable commercial production readiness: NOT YET ESTABLISHED**. Start a controlled developer edition on the vendor 5.4 BSP, then test an upstream 6.18 LTS branch independently. Do NOT use Letkite's current AX3000T or Xiaomi RD08 firmware on this Unisoc platform.

## 1. Source identification and precise limits

- Case study: https://github.com/atongrun/f50-256g-openwrt-guide ; reviewed checkout `1f490e72d5388fbb66a19b48e5dbf11501a76b9d`.
- Main implementation: https://github.com/dikeckaan/mu300-linux ; reviewed checkout `833616a6c03a7c0245300c5946d98ec98b09bb94`.
- Companion tooling: https://github.com/dikeckaan/zte-f50-toolkit . Review tooling and device-specific firmware before use; never trust another unit's NV, IMEI, calibration, security metadata or GPT.
- The guide has **one** physical 256GB F50 case. It identifies board `ums9620_2h10_feimao`, Unisoc T760/UMS9620, Android 13, originally B06 then B09, with logical SIM slot 1, channel nr4, interface sipa_eth8. These are **observations on one unit**, not platform defaults.
- F50 **is not** Xiaomi BE6500 Pro RD08. It uses Android/Unisoc A/B boot, GPT and a Linux rootfs partition; RD08 uses Qualcomm OEM QSDK/NAND and ART. Treat as a new hardware adapter.
- Upstream PR #72 (internal-SIM data routing) and #98 (kernel 5.4 fw4 flowtable reload) were **merged**, confirmed 2026-11-11. Review current source rather than transplanting the guide's local patches blindly.

## 2. Acquired, independently verified resources

Latest published non-prerelease in queried GitHub Releases: `v2026.11.02.1`, published 2026-11-02. Assets on Compute-1 in:
`/home/cp1/workspace/f50-letkite-feasibility/assets/`

| Artifact | Bytes | SHA-256, matched GitHub release asset metadata |
|---|---:|---|
| `mu300-openwrt-luci-rootfs.tar.gz` | 24,154,179 | `c88e6e72dee1dbd8fa0ad565dc8885b1b408d9abc8221bae10aaead92123d782` |
| `mu300-kernel.tar.gz` (vendor 5.4) | 27,997,200 | `9336003a5ae3d65a9939d3e5fc2d0036cc2bde2f81b03a6cd94fd76296866124` |
| `mu300-kernel-6.18.tar.gz` | 53,175,572 | `64893b185c5717b3c40699ab4863fb1f291a0e03eb869d50fdcf05a78014e130` |

Exact URL scheme: `https://github.com/dikeckaan/mu300-linux/releases/download/v2026.11.02.1/ARTIFACT`.
Downloaded assets were verified with local `sha256sum -c`. GitHub asset digest and transport checks **are not** sufficient provenance attestation for a commercial release; require publisher signature, reproducible source attestations and license audit.

## 3. Actual rootfs, kernel and disassembly checks

Extracted release metadata from the shipped rootfs:
```
DISTRIB_RELEASE='25.12.6'
DISTRIB_TARGET='armsr/armv8'
DISTRIB_ARCH='aarch64_generic'
etc/mu300/image-version: v2026.11.02.1
```

- Stock-kernel bundle's `Image` includes `Linux version 5.4.254-gb50db5b6224c` and `modules/` contains board-specific Unisoc `sipa-core.ko`, `sprd_modem_loader.ko` and radio/device modules.
- Mainline 6.18 bundle includes a kernel identified as `Linux version 6.18.60`, and a separate custom module set. Keep kernel, module tree, DTB, Wi-Fi firmware and vendor Android subset **version-matched**. Do not install generic OpenWrt 6.12 kmod packages on 5.4 or 6.18 images.
- Static ELF inspection of 5.4 `sipa-core.ko`: ELF64 AArch64 ET_REL, `vermagic=5.4.254-gb50db5b6224c SMP preempt mod_unload modversions aarch64`. `sprd_modem_loader.ko`: same vermagic, `depends=sprd_power_manager,sipc-core`. Both advertise GPLv2 in modinfo; additional vendor firmware licensing must be separately checked.
- Capstone AArch64 disassembly of `sipa_prepare_suspend` at section-relative address `0x36b0` starts `str x30, [x18], #8; stp x29, x30, [sp, #-0x40]!; ...; ldr x23, [x0, #0x98]; ldrb w8, [x23, #0x140]; cbnz w8, ...`. `modem_probe` at `0x234` starts with register save, pointer/size setup, and conditional branches for allocation failure. **In relocatable .ko, branch instructions may not resolve to their linked functions yet**; these excerpts prove architecture and the presence of resource/driver state paths, not field stability or proprietary protocol correctness.
- Also inspected bundled `mu300-carry`: ELF64 static AArch64 ET_EXEC with symbols, function `main` at `0x400570`. The public source `tools/carry/mu300-carry.c` documents preserving mode, xattrs, hardlinks, sparse files and user customizations during upgrade. This is a promising integration hook but requires custom-file regression tests.
- The rootfs contains a substantial MU300-specific layer, `/opt/mu300/` and custom `/lib/netifd/proto/mu300cell.sh` and `fw4` patches; these are essential cellular and network functions, not interchangeable with official generic OpenWrt ImageBuilder output.

### Static analysis is not hardware certification

No 5G call, AT conversation, carrier NAT, Wi-Fi throughput, cold-boot, modem power state or kernel security behavior can be verified by static disassembly alone.

## 4. Feasible Letkite integration architecture

**Recommended v0.1 developer build:** fork/pin the verified `mu300-linux` release and add a separate Letkite build overlay in its **source rootfs assembly** process. Build `openwrt-luci` flavor, vendor-matched 5.4.254 kernel for the first reference device, no bootloader/GPT modifications in the image-building step.

System structure:
- `MU300 BSP / Android vendor subset / modem + Wi-Fi drivers` remains an upstream-pinned boundary.
- `OpenWrt 25.12.6 armsr/armv8 rootfs` + `MU300 netifd/factory hardware services`.
- `Letkite signed ARM64 agent + procd init + read-only health diagnostics + LuCI entry`, installed at build time from a signed authenticated artifact, rather than `curl|sh` after first boot.
- `Letkite enrollment` only after the owner authenticates and verifies claim. Current `letkite-router` pinned agent `1.6.1` is **NOT qualified** for unattended owner claim: `verify-agent.py` explicitly rejects versions <=1.9.1. Do not bypass signature/claim gate or embed enrollment keys.
- Optional WireGuard and Mihomo (independently signed/hash-pinned), disabled until configured. Avoid routing Letkite's outbound control channel through a proxy that the Letkite agent itself manages, to prevent self-lockout.
- Docker optional, **OFF by default**. Upstream explains embedded Docker adds ~190 MB, twice during an update/rollback; the actual Linux partition in the guide is only ~4 GiB and runtime RAM ~1.4 GB. Store containers outside OS path and cap memory/logs.

### Update model

- The upstream `mu300-update` supports system backup/rollback and has SHA256SUMS.sig (Ed25519/usign) verification logic when a trusted installed release public key exists.
- **Do not automatically trust Letkite-customized builds as upstream signed releases**; forked image must have a separate Letkite release key, manifest, version/rollback semantics, and explicit source provenance.
- `mu300-update` contains paths where a missing release key permits legacy HTTPS+hash trust, and explicit `MU300_ALLOW_UNSIGNED` overrides. Stable Letkite builds must mandate a pinned local root-owned key and **fail closed on unsigned updates**, without weakening upstream safeguards.
- `mu300-carry` and `mu300-user-packages` preserve user changes and reinstall local packages. Image-owned Letkite binaries should be included in **every** Letkite release, not merely a user-added executable, to avoid removal during rootfs updates. Test preservation of owner credentials/host keys through upgrade and rollback, stored outside public source and excluded from logs.
- Preserve Android fallback/trial boot and allow rollback to a previous known-good kernel + rootfs combination. Never disable fallback as a cosmetic way to make Linux the default.

## 5. F50 256 GB hardware hazards

The guide's 256 GB sample had **no unused GPT tail space** and **no SD card**. The owner intentionally shrank Android userdata to make ~4 GiB for Linux; GPT modification plus an unreconciled F2FS block count can destroy both systems. A stable installer must independently verify model, firmware, storage media, boot slot, main/backup GPT CRC, overlap and filesystem shrink completion, and obtain **explicit device-specific authorization** before any such operation.

Hard constraints:
1. No copying another device's GPT, NV, IMEI, calibration, persist, metadata or encrypted keys.
2. No blind `dd`, `mtd`, stock Android boot override or F2FS shrink from user-facing default installer.
3. Stable builds should prefer an F50 device with validated empty installation space, or removable SD where supported, rather than making GPT surgery the default product workflow.
4. Device-class RAM, USB power dependency, 5G thermal load and carrier-specific SIM/AT behavior need soak testing.
5. Don't assume physical SIM labels equal the logical slot. Guide's internal SIM1 mapping is a single-unit observation. Upstream PR #72 was merged, but external/internal transitions need regression tests.
6. 5.4 kernel has known firewall flowtable incompatibilities; upstream PR #98 merged, verify it is included in the pinned image. Mihomo's `auto-redirect` cannot be assumed to work on 5.4; first verify non-transparent operation and routing cleanup.

## 6. Proposed qualification matrix and release gates

| Gate | Required evidence | Status as of this assessment |
|---|---|---|
| Reproducible signed source + toolchain | Locked upstream commit, release signatures, license audit, SBOM | **NOT DONE** |
| System-level ARM64 Letkite artifact | Signed qualified claim-capable agent, package provenance, procd startup | **BLOCKED (1.6.1)** |
| F50 boot / Android fallback | Physical device, 1–5 failed trial attempts, A/B round-trip | **NOT TESTED BY LETKITE** |
| Cellular and client traffic | Both SIM modes, modem RX/TX, Wi-Fi/USB DNS, TLS and HTTP with client bound | **UPSTREAM SINGLE-DEVICE ONLY** |
| Firewall + proxy + Docker | nftables/fw4, DNS, IPv6, TUN, NAT, isolation and rollback | **NOT TESTED BY LETKITE** |
| 24–72h soak | Multiple cold boots, modem reconnection, RAM pressure, 5G heat, watchdog | **NOT DONE** |
| Upgrade and recovery | Signed image updates, backup data integrity, power-cut simulation, rollback | **NOT DONE** |
| Device variants | At least multiple 256GB units and supported Android versions | **NOT DONE** |

**Release decision:** Allow an **internal developer edition / controlled alpha** after signed agent and off-device image tests; **do not label it a stable retail ROM** until the above physical and security gates pass.

## 7. Work breakdown and low-risk next step

1. Add a new `f50-mu300` BSP adapter to Letkite's existing `distribution/platform/` policy, with `vendor_device`, `storage_layout=GPT`, `android_fallback=true`, `build_backend=mu300-rootfs-assembler` and flash safety `research-only` until device-qualified. No Xiaomi code reuse beyond generic capability checks.
2. Build a pinned **offline overlay test** for `openwrt-luci` that includes a placeholder/version marker and tests procd/script ordering; only substitute a real Agent when authenticated release/claim contract is proven. Never embed private credentials.
3. Rebuild the MU300 rootfs with its required matching kernel modules, regulatory database, vendor Android subset, source hashes and new Letkite overlay. Compare packed image manifest to the baseline.
4. In QEMU/test chroot, verify ARM64 binary invocation/ABI and startup guard, package integration and updater compatibility. Virtual QEMU cannot certify 5G modem, Wi-Fi, Android A/B boot or field recovery.
5. On an owner-authorized test device, capture **read-only** ADB and GPT inventory, verify backups and recovery strategy, then separately request explicit write authorization for any installation.
6. Keep two independent release tracks: vendor 5.4 BSP first for known modem compatibility, 6.18 LTS as a longer-term security candidate after equivalent tests.

## 8. Traceability and local artifacts

Workspace: `/home/cp1/workspace/f50-letkite-feasibility/`. Local checked-out source and verified release assets kept outside Git. Static extraction under `inspect/`, including 5.4 and 6.18 images and the two vendor modules. Public GitHub source and this report contain no device-specific secrets. No actual F50 or other router was accessed or modified.

Relevant upstream sources:
- https://github.com/atongrun/f50-256g-openwrt-guide/blob/main/docs/02-installation-runbook.md
- https://github.com/atongrun/f50-256g-openwrt-guide/blob/main/docs/05-recovery.md
- https://github.com/atongrun/f50-256g-openwrt-guide/blob/main/docs/06-clash.md
- https://github.com/dikeckaan/mu300-linux/blob/main/openwrt/build-rootfs.sh
- https://github.com/dikeckaan/mu300-linux/blob/main/rootfs/overlay/opt/mu300/bin/mu300-update
- https://github.com/dikeckaan/mu300-linux/blob/main/tools/carry/mu300-carry.c
- https://github.com/dikeckaan/mu300-linux/releases/tag/v2026.11.02.1
- https://github.com/dikeckaan/mu300-linux/pull/72
- https://github.com/dikeckaan/mu300-linux/pull/98
