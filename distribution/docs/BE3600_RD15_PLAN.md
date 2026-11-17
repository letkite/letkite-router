# RD15 development preflight — no flashing

This is source preparation for Xiaomi BE3600 2.5G **RD15 only**, not an
installable Letkite release. RD16 and RD08 are incompatible. No device has
been contacted. Serial hardware is absent: installation is blocked.

The source of the hardware observations is the local experimental reference
at `d9c8a55a1eedf0956f85f0ef2a591a30d0415464`, especially README and
`docs/{hardware,installing,recovery-and-rollback,limitations,building,status-and-testing}.md`.
Its base is fivefold3/openwrt-gl-be3600 at
`e46ea77ba4f431c72301c3d07220e454450b3070`, kernel 6.18,
`qualcommbe/ipq53xx`. All five feed revisions and source-file hashes are
recorded in `../platform/rd15/source-lock.json`. These are pinned source
observations, not independently reproduced hardware results. No online
qualification or new release lookup was performed.

## Preparation and offline evidence

Run from the repository root:

```sh
python3 distribution/scripts/prepare-rd15.py /path/to/be3600-rd15-upstream
python3 distribution/platform/rd15/preflight.py distribution/platform/snapshots/rd15-reference.json
python3 distribution/tests/test-rd15.py
```

The first command audits source without modifying it, fetching, applying
patches or building. The second intentionally refuses incomplete synthetic
evidence. The snapshot is a sanitized reference template, not a router dump.
Supply only allowlisted model, geometry, MDIO, slot, size and recovery facts
for future offline review; never supply complete logs, board data, partition
contents, identities or configuration. Evidence is operator supplied, not
cryptographically attested; a pass never authorizes images or flashing.
The adapter is a separate explicit evaluator, not a generic OS auto-detection
upgrade. Official OpenWrt ImageBuilder cannot build this experimental target;
`build-image.sh` rejects its profile even in dry-run.

The private stock 1.0.87 input is pinned by SHA-256
`cb2d7e40a74c33439fe61e78f1c2c08bf4effdb6617214118f3da783fd7a5c0a`.
It stays outside this repository. Future local vendor staging must first
verify this whole-image digest and then the upstream extracted-file hashes.
Do not use upstream's `--allow-unverified` escape hatch. No firmware, extracted
vendor files, keys, authorized_keys, images or per-device calibration are
staged by this integration. Do not publish proprietary build outputs.

Full source-tree preparation and compilation are deferred: upstream's
prepare-tree script fetches a base and copies an overlay containing boot-slot
write services; the build produces flashable artifacts. This change only
audits and locks those inputs. A later separately reviewed isolated build
must inspect patches, expand config, verify feeds and vendor hashes, record
artifact sizes/hashes, and keep outputs private. Never run upstream install,
slot-selection or recovery scripts as part of host preparation.

## Capacity decision

256 MiB physical RAM is not service headroom: Q6 reservations leave about
145 MiB to Linux. Upstream reports roughly 28–37 MiB MemAvailable with both
radios, low-memory ath12k patches, and unresolved endurance/client behavior.
A 7–9 MiB Letkite executable is a disk estimate, not a measured RSS estimate.
Wi-Fi plus Letkite is plausible only as an experiment; it is **not qualified**.
Measure peak RSS/PSS, MemAvailable, OOM/restarts and recovery during concurrent
radio traffic, agent reconnect/update and long-duration multi-client load.
Do not assume that disabling radios releases all reserved regions.

Each NAND slot is 42 MiB, not 42 MiB of writable filesystem. The kernel volume
is 10,539,008 bytes; this port caps SquashFS at 16 MiB and uses remaining UBI
capacity for overlay after bad-block/UBI overhead. Upstream measured only
about 8.2 MiB free overlay. Two 7–9 MiB program copies need 14–18 MiB before
configuration and safety margin; the existing 16 MiB policy floor is not enough
for a future 9 MiB release. Current layout therefore does not demonstrate
safe agent updates. Reject oversize kernel/rootfs/slot payloads; later image
qualification must measure actual UBI allocation, bad-block reserve, free
overlay and two exact signed program sizes plus update overhead.

Mihomo (~57 MiB executable) exceeds the slot budget by itself and is prohibited.
Docker on the router is prohibited. Host-side build containers are a different
resource but are not executed here. No proxy or service is automatically enabled.

## Agent release gate

No Letkite agent or LuCI source changes. The pinned 1.6.1 agent is not qualified
for automatic claim. `--enable-agent` always refuses; snapshot booleans cannot
qualify it. Follow the existing distribution README gate: independently trusted
signed release and apk metadata for both packages, exact binary digest/size,
aarch64 ABI, signed version newer than 1.9.1 plus real claim-contract tests,
and measured two-copy storage/RAM are all required. An offline binary signature
check alone does not qualify a provider. Preserve the agent-owned firstboot,
service, ceiling, identity, update and uninstall lifecycle. Do not add a second
service or embed pairing data. No provider exists in this integration.

## Recovery and validation blockers

Verify a 1.8 V UART, ground and logic voltage, VCC disconnected, a working
bootloader interrupt, private same-device hashed backups of all partitions
and UBI volumes, and intact stock slot 1 before any later installation.
ART, bdata, MIBIB and APPSBL must never be replaced or uploaded. Stock UART
and boot interrupt may be disabled; no unlocking instructions are supplied.
Direct bootm caused HLOS panic upstream; bootmiwifi and slot flags require
board-specific review. Boot-success marking changes NAND environment; repeated
cold boots and power-loss recovery are unqualified. No slot flag changes,
nvram, mtd/mtdev, sysupgrade, UART activity or RAM boot is authorized here.
A verified RAM boot and recovery exercise remain prerequisites to flashing.

First later hardware validation should use an isolated **1 GbE LAN** cable:
confirm management, both traffic directions, DHCP/FDB forwarding, link recovery,
error counters and sustained traffic before Wi-Fi and concurrent agent tests.
The YT9215S switch is at MDIO 0x1d; expected YT8821 is 0x07, ID 0x4f51ea19,
with no PHY at 0x0c. Different NAND or MDIO means stop, not broaden the guard.
The installed reference omits the 2.5G PPE port; RAM-only results with a failing
USB peer do not qualify it. Stable peer hardware, MAC assignment, reset behavior,
thermal/error monitoring and bidirectional endurance are required separately.

## Windows 11 PC-1 notes

Two wired Xiaomi routers share 192.168.31.1. RD15 is **Ethernet 2**, local source
192.168.31.121; the RD08 Internet router is **Ethernet**, source 192.168.31.120.
Never select a target by IP alone, and never target the Internet router.
This task runs no network probes or route changes. For a later authorized lab,
physically isolate RD15 and verify interface, source address and cable before
any access. Read-only host inspection can use PowerShell `Get-NetAdapter`,
`Get-NetIPAddress -AddressFamily IPv4`, `Get-NetRoute -AddressFamily IPv4`
and `Get-FileHash -Algorithm SHA256` for local files. Do not publish MACs or
raw host logs. Use Linux/WSL2 on its Linux filesystem for a future source build;
Windows OpenSSH, serial terminals, TFTP and network tools are not needed now.
No passwords, private/public login keys or device partition uploads are needed.
