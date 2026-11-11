# Mihomo integration validation — 2026-11-08

This records local validation, not a hardware flashing approval or provenance
attestation. No hardware was flashed. The branch is
`feature/router-os-distribution-v0` for draft PR #15.

## Upstream artifacts

Official release API returned `v1.19.33`, published `2026-10-21T16:56:13Z`.
Both downloaded gzip files matched the release metadata SHA256 exactly:

| Exact asset | Compressed SHA256 |
| --- | --- |
| `mihomo-linux-amd64-v1-v1.19.33.gz` | `8ec92e7b2fdc6b853ba00156bab7e4e965c8b0d843b8c4ac8ab98795f02ad524` |
| `mihomo-linux-arm64-v1.19.33.gz` | `ba408b317080ee265c46cb923a50018c1b82cbd708551cdd46a1e3e307396187` |

Decompressed executable hashes (also checked against image contents):

| Executable | Installed SHA256 |
| --- | --- |
| x86-64 | `19cbe7ba1523a92ed2d0a30716ea093de57db05b7844db23de2b9c21fd7a1afa` |
| AArch64 | `8c73570d9a5f388bc2f58eee0b347ccfab84fb3cf1a0f8f2cf5eac7005fbcdc0` |

`file` identified the arm64 artifact as static little-endian ELF64 AArch64.
The stager checks ELF64/little-endian/machine for both targets before installing.
This is SHA256 integrity pinning, not signature/provenance authentication.

## Offline checks

Passed:

- `python3 -B distribution/tests/test-mihomo.py`: 8 tests.
- `bash distribution/tests/test-profiles.sh`: all profile checks.
- `python3 -B distribution/tests/test-agent.py`: 8 tests.
- `python3 -B distribution/tests/test-platform-adapters.py`: 7 tests.
- `bash -n distribution/scripts/build-image.sh`.
- `sh -n distribution/addons/mihomo/files/etc/init.d/mihomo`.
- `sh -n distribution/addons/mihomo/files/etc/uci-defaults/96-letkite-mihomo`.
- `git diff --check`.

The Mihomo fixtures are synthetic gzip/ELF files, not executable programs.
Network operations are mocked; build dry runs poison curl/make. There is no
production fixture URL or checksum override. CI adds only offline tests, not
Mihomo image builds/downloads. ShellCheck was unavailable locally; shell syntax
checks passed. Existing Agent/LuCI/package source and trust logic were not edited.

## Actual image builds

OpenWrt 25.12.6 official checksummed ImageBuilders were used with:

```sh
ENABLE_MIHOMO=1 ENABLE_DOCKER=0 bash distribution/scripts/build-image.sh --profile x86-full
ENABLE_MIHOMO=1 MIHOMO_STORAGE_BUDGET_MB=80 bash distribution/scripts/build-image.sh --profile ax3000t
```

AX3000T build passed. Final sysupgrade root was extracted and compared against
source: verified executable, executable init script, UCI disabled flag, original
`95-letkite-os` plus `96-letkite-mihomo`, no shipped user profile.

Final AX3000T output:
`distribution/out/ax3000t-base-mihomo/openwrt-25.12.6-mediatek-filogic-xiaomi_mi-router-ax3000t-squashfs-sysupgrade.bin`

SHA256: `df81721e6bff377b088c3b5847634cbdd84aa6983d3b3bca2b685ab1f82d124c`.

x86 build passed for all four disk variants under
`distribution/out/x86-full-base-mihomo/`:

| Filename | SHA256 |
| --- | --- |
| `openwrt-25.12.6-x86-64-generic-ext4-combined.img.gz` | `a27aa233e6b1290741f735ea3f076394469bb55b9a9ec8c96452f8a168b528d3` |
| `openwrt-25.12.6-x86-64-generic-ext4-combined-efi.img.gz` | `53f2658682be1c322ce1dba70efcdb192857e0bc3df2ecfdbb3b1e9ffae28b46` |
| `openwrt-25.12.6-x86-64-generic-squashfs-combined.img.gz` | `2ff60bf8db812eddea5dba3d266ed5cd9ff8e822d3b8b46349c59e6847df9dc9` |
| `openwrt-25.12.6-x86-64-generic-squashfs-combined-efi.img.gz` | `4cfba1fff4e736220afd94daed12c3a1fb42b0bf7e62580dd82479afb1f2d121` |

The combined squashfs disk was decompressed, its MBR root partition offset
parsed, and the actual root filesystem extracted with ImageBuilder's
`unsquashfs4 -o <offset>`. The x86 executable SHA256 matched the table above;
`file` identified static little-endian ELF64 x86-64. The service and original
firstboot defaults matched source byte for byte.

The BIOS ext4 image was booted in QEMU TCG with 512 MiB RAM, two virtual CPUs,
`-net none`, and `snapshot=on` (no persistent disk writes). The boot disk's raw
SHA256 matched the decompressed final output:
`c7847bed5f9d428f42b20925079e5a98e93b9e498ff9f415e72ff7e6724e6880`.
All seven runtime checks passed: firstboot defaults consumed; init service
disabled; no user profile; no Mihomo process; explicit start remains inactive
with UCI disabled; guest command sequence completed; binary reports
`Mihomo Meta v1.19.33 linux amd64`. Commands included
`/etc/init.d/mihomo enabled`, `pidof mihomo`,
`/opt/letkite-router/mihomo/mihomo -v`, and a disabled-service `start` followed
by another process check. No user proxy configuration was loaded and no proxy
traffic was tested. AX3000T was inspected offline, not booted or flashed.
Local smoke runner/log: `/tmp/mihomo-qemu-check.py`,
`/tmp/mihomo-inspect/qemu-mihomo.log`. The first raw-disk copy attempt raced
completed compression and was retried from the compressed disk; the successful
run used the final disk bytes verified above. ImageBuilder emitted its upstream
GRUB small BIOS boot partition warning; BIOS QEMU boot nevertheless passed.

The 80 MiB storage budget is an operator declaration after base OS and recovery
reservation. A successful image build does not qualify every NAND/UBI layout.
The arm64 installed binary alone is 57,475,198 bytes. See [operator caveats](mihomo.md).

Local build logs: `/tmp/mihomo-x86-final.log`, `/tmp/mihomo-ax-final.log`.
Build outputs and logs are local artifacts, not committed binaries. Local branch
history was preserved despite being ahead of and behind its remote; the
coordinator must sync the new commit onto the PR branch without merging the PR.
