# Optional Clash Meta / Mihomo

Mihomo is independent of sing-box (`ENABLE_PROXY`) and WireGuard. It is off by
default. Neither Mihomo nor OpenClash is available in the checked official
OpenWrt 25.12.6 APK feeds. This integration downloads a binary, never an APK.
It does not change Letkite Agent, LuCI, package trust, routing or firewall policy.

The reviewed provider is [MetaCubeX/mihomo v1.19.33](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.33),
published 2026-10-21. Exact asset names, compressed sizes and SHA256 pins are in
[`../addons/mihomo/manifest.json`](../addons/mihomo/manifest.json), verified against
[official release API metadata](https://api.github.com/repos/MetaCubeX/mihomo/releases/tags/v1.19.33)
on 2026-11-08. Downloads must match the compressed SHA256 before decompression;
the result must be little-endian ELF64 with machine 62 (x86-64) or 183 (AArch64).
SHA256 pinning provides integrity relative to a reviewed upstream artifact;
**it is not full provenance or signature authentication**. Production releases
need a stronger reviewed trust policy (signed attestations/source verification).
No `latest`, alternate download URL, runtime checksum override or untrusted APK
fallback exists. Missing assets, download failures and mismatches fail closed.

The explicit amd64-v1 variant avoids requiring v2/v3 CPU extensions. The arm64
variant targets baseline AArch64 (AX3000T Cortex-A53). The provider selection and
hardware adapter table are separate from OpenWrt profiles and package feeds:
`stage-mihomo.py` owns release URL/verification, `manifest.json` owns target
mapping, and `build-image.sh` owns ImageBuilder staging. Future forks require
reviewed builder/profile adapters and independent resource qualification; this
does not authorize generic fork images or flashing.

```sh
# Dry run performs no downloads or writes.
ENABLE_MIHOMO=1 bash distribution/scripts/build-image.sh --profile x86-full --dry-run
# Real image; omit ENABLE_DOCKER=0 if Docker is also required.
ENABLE_MIHOMO=1 ENABLE_DOCKER=0 bash distribution/scripts/build-image.sh --profile x86-full
# Both binaries present, both services disabled until configured:
ENABLE_MIHOMO=1 ENABLE_PROXY=1 bash distribution/scripts/build-image.sh --profile x86-full
```

Outputs are `distribution/out/<profile>-base-mihomo` or
`<profile>-proxy-mihomo`; existing base/proxy output paths are preserved. Downloads
and overlay directories are temporary and removed on success/failure. Only the
verified executable is placed at `/opt/letkite-router/mihomo/mihomo`. The base
`distribution/files` directory is never modified. The overlay retains
`95-letkite-os` (sing-box/dockerd safety) and adds `96-letkite-mihomo` which disables
and stops Mihomo on first boot. No user profiles, subscriptions, API secrets,
TUN/TProxy/DNS/firewall rules or listener configuration are shipped.

## Storage and runtime limits

Measured release sizes:

| Target | Gzip bytes | Installed executable bytes |
| --- | ---: | ---: |
| x86-full (amd64-v1) | 22,893,964 | 62,079,102 |
| AX3000T (arm64) | 20,824,326 | 57,475,198 |

Plan at least 256 MiB RAM for small configurations, preferably 512 MiB or more;
this is an operator planning floor, not a measured guarantee. Rule sets, geo
databases, connections and concurrent sing-box/Docker increase usage. Reserve
at least 80 MiB persistent space **after** the base OS and recovery reserve,
plus space for your own databases/logs. x86 uses the existing 512 MiB root image.
Compressed download size does not predict squashfs size or NAND headroom.

AX3000T NAND/UBI layouts vary; this binary is not suitable for all layouts.
The build is blocked unless the operator supplies `MIHOMO_STORAGE_BUDGET_MB=80`
or greater, declaring available space after those reservations. The staging
check also enforces installed size plus 16 MiB reserve against that budget;
ImageBuilder still must pass its image/partition checks. This is not automatic
free-flash detection or proof that an existing device can upgrade safely. Inspect
UBI capacity, image size and upgrade/recovery requirements yourself. Do not flash
an oversized image. Runtime data defaults to volatile `/tmp/mihomo` (RAM); use
carefully reviewed service changes for large persistent databases to avoid NAND
wear and RAM exhaustion. No hardware flashing is performed by the builder.

## Operator installation and enablement

For an image, use the builder above. For manual installation, run the same pinned
stager on a trusted build host with Python 3.11+ and curl:

```sh
overlay=$(mktemp -d)
python3 distribution/scripts/stage-mihomo.py --target x86-full --overlay "$overlay"
# Review and copy only opt/letkite-router/mihomo/mihomo, etc/init.d/mihomo,
# and etc/config/mihomo from this overlay to matching router paths as root.
# On AX3000T select --target ax3000t --storage-budget-mb 80 after capacity review.
# Disable the installed service, create /etc/mihomo mode 700, and keep UCI mode 600.
rm -rf "$overlay"
```

Install the executable and init script with mode 755. Use `/etc/init.d/mihomo
disable` and `stop` after manual installation. Create a root-owned
`/etc/mihomo/config.yaml` with mode 600 inside root-owned `/etc/mihomo` mode 700.
The service accepts only this fixed regular config file; it refuses a symlink or
incorrect file owner/mode. Keep all parent directories root-owned. UCI stores only
an enable flag, not subscriptions or secrets. Example enable sequence after
reviewing a private configuration:

```sh
/opt/letkite-router/mihomo/mihomo -t -d /tmp/mihomo -f /etc/mihomo/config.yaml
uci set mihomo.main.enabled='1'
uci commit mihomo
/etc/init.d/mihomo enable
/etc/init.d/mihomo start
```

Validate profiles in an isolated environment first: Mihomo may download geo data
or provider resources depending on the supplied configuration, including during
validation. Supply local resources where offline operation is required. No network
profile validation is done by the builder. Start with manual localhost proxy
listeners, `allow-lan: false`, no external controller, DNS or TUN. Any LAN/WAN/API
exposure, DNS hijacking or transparent routing requires explicit operator design.
Review ports, routes and policy rules before running sing-box and Mihomo together.
The service runs as root for potential networking features; it is not a sandbox.
It caps open files and disables core dumps; it does not enforce a RAM hard limit.

Stop with `/etc/init.d/mihomo stop`, set `mihomo.main.enabled=0`, commit UCI and
`/etc/init.d/mihomo disable`. Never commit private profiles or subscriptions.

## Offline tests

`python3 -B distribution/tests/test-mihomo.py` uses synthetic gzip/ELF fixtures
and a mocked downloader, without a production source/checksum override. It covers
wrong SHA, missing file, wrong machine/class, decompression size limits, asset
path traversal, storage/overlay rejection, executable modes, preserved defaults,
and dry runs with poisoned curl/make. CI runs only these offline Mihomo tests;
real release downloads and image builds remain explicit operator actions.
