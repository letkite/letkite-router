# OpenWrt-family platform adapters

This is an independent, read-only inventory layer. It does not change the existing
build profiles or agent packages. Run on an analysis workstation with Python 3:

```sh
python3 -B distribution/platform/detect.py --root /path/to/inventory
python3 -B distribution/tests/test-platform-adapters.py
```

Default root is `/`. `--allow-uname` optionally supplements live-root kernel and
machine information through `os.uname`; fixture roots never use host information.
No ubus, shell, package manager, network, agent service or external command is
needed. Python 3 is an analysis-tool requirement, not a proposed router package
dependency. On routers without Python, collect an inventory for offline analysis.
The CLI emits JSON with facts, classification, reasons, warnings and next steps.
Missing facts are null/unknown; malformed input produces warnings and downgrades
classification. Exit success means inventory completed, never install permission.

## Files and extension contract

- `platform/adapters.json`: OS-family definitions, package trust requirements,
  builder availability, minimum resources, integration tier and flash boundary.
  `manifest.schema.json` documents its version 1 JSON Schema contract. Runtime
  needs only Python's standard library; tests check required manifest fields.
- `platform/devices.json`: separate board candidates and target/profile hints.
  These hints do not verify hardware revisions, flash layouts or authenticity.
- `platform/policy.json`: fail-closed default and four integration tiers. Detector
  consumes its default classification and disabled firmware capabilities.
- `platform/fixtures.json`: synthetic file maps for tests/examples. MTD sizes and
  kernel placeholders are illustrative, not device specifications or flash maps.
- `platform/detect.py`: bounded file parsing and adapter selection. No fixture
  release file is sourced; no fixture executable is invoked.

The registry is trusted repository policy, not a device-supplied manifest. Keep
all firmware capability flags disabled until a separate reviewed qualification
mechanism exists. Adding a name to a registry never qualifies firmware. A future
qualification record must bind exact board/revision, release, target, partition
map, signed builder/BSP provenance and tested recovery. This implementation ships
no such records and grants no firmware build or flash authorization.

## Classification and evidence

| Tier | Meaning and current behavior |
| --- | --- |
| Full firmware ImageBuilder/SDK | Intended for qualified upstream targets; official OpenWrt family reports builder candidacy. Disabled for all detected devices pending exact qualification. |
| Vendor BSP source build | Requires OEM BSP, licensed components, kernel/radio pairing and recovery qualification. RD08 combined evidence reports a BSP candidate; capability remains disabled. |
| Agent-only package/overlay | OpenWrt 24.10/opkg or 25.12/apk metadata with supported CPU evidence and no parse conflicts is an agent candidate. This does not install or approve a binary. |
| Research-only/manual review | Default for missing/conflicting evidence, unknown firmware, unverified forks and legacy vendor systems. |

APK/OPKG detection uses nonempty native database or feed configuration files,
never a release-number guess. Both present is a conflict. OpenWrt agent candidacy
requires agreement between `DISTRIB_ID` and `os-release` ID, a known release/backend
pair and supported package architecture. Version metadata disagreement downgrades
to research. Unknown ImmortalWrt opkg and apk variants remain research-only,
regardless of their name. Declared identities and feeds are untrusted observations;
no local file can establish vendor authenticity.

Inputs include `/etc/openwrt_release`, `/etc/os-release`, `/proc/cpuinfo`,
`/proc/mtd`, `/proc/mounts`, `/etc/board.json`, `/proc/sys/kernel/osrelease`,
`/lib/apk/db/installed`, `/etc/apk/repositories`,
`/etc/apk/repositories.d/distfeeds.list`, `/usr/lib/opkg/status` and
`/etc/opkg/distfeeds.conf`. Board compatible is the board.json model ID, not
inferred from a marketing name. Package architecture and target are reported
verbatim. Actual libc, float ABI and binary compatibility remain explicitly
unverified; CPU VFPv3/VFPv4 evidence is required for ARM package candidacy.
Minimum RAM/storage values are screening requirements, not measured capacity or
a guarantee that any particular agent release fits. Installation must reuse the
agent package's signed-feed, pinned-binary, CPU and free-storage checks.

Every MTD layout is observed-unverified, even if partition names look familiar.
The x86 fixture has a filesystem observation without an MTD table; physical/VM
partitioning and disk identity still need review. AX3000T compatible strings do
not distinguish RD03/RD23 stock layout from unsafe revisions or bootloader mods.

RD08 selection requires a board candidate plus IPQ5332 CPU evidence, an 18.06
release and kernel 5.4.213 together. These observations reflect the existing
[OEM boundary analysis](rd08-vendor-boundary.md), not all OEM releases. Partial
evidence stays research-only without claiming an exact OEM match. OEM build
version, board revision, ART offsets and partition geometry remain unverified.
Official OpenWrt ImageBuilder images are unsuitable for this proprietary QSDK
system. Preserve ART, WIFIFW, calibration, identity and boot data. There are no
partition-writing commands or operations in the detector.

Files larger than 256 KiB, nonregular files, NUL/invalid UTF-8 content and symlink
components (including fixture-root ancestors) are refused. JSON shape errors are
handled. Use a stable, trusted inventory directory: this lightweight parser is
not a sandbox against concurrent filesystem replacement. Ordinary missing files
are tolerated; insufficient evidence cannot enable firmware capabilities.
