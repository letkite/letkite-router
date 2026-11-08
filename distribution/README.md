# Letkite Router OS — distribution prototype

**Status: engineering preview, NOT an installable firmware release.** This directory is separate from the existing `packages/letkite-agent` and `packages/luci-app-letkite`, which are developed independently.

## Design

- OpenWrt 25.12.6 based images for Xiaomi AX3000T **RD03/RD23 (stock layout only)** and x86_64.
- Feature profiles: Lite (LuCI, WireGuard; optional sing-box), x86 Full (same plus optional Docker runtime).
- No default transparent proxy / TProxy / firewall rewrites. Users configure their own compliant VPN or proxy service explicitly after installation.
- No credentials, node keys, enrollment identities or OEM proprietary binaries in images.
- Agent preinstallation is explicitly gated by `ENABLE_LETKITE=1`, disabled by default, and currently **blocked**. The existing packages remain untouched. See the integration gate below.
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

## LetKite integration gate

```sh
# Existing base/proxy/x86 builds are unchanged; no LetKite package or overlay.
ENABLE_LETKITE=0 distribution/scripts/build-image.sh --profile ax3000t --dry-run
# Intentionally exits nonzero, including in dry-run; no downloads or image writes.
ENABLE_LETKITE=1 distribution/scripts/build-image.sh --profile x86-full --dry-run
python3 distribution/tests/test-agent.py
```

The official base remains OpenWrt 25.12.6 (apk). The repository currently pins
agent **1.6.1**: legacy manual enrollment, not the automatic Card A claim contract
(newer than 1.9.1). We do not advance that pin, patch the packages, or infer claim
compatibility from the presence of the `install` command. Neither manual nor
unattended agent embedding is enabled by this implementation.

On 2026-11-08 the official `packages.adb` and apk public key endpoints returned
HTTP 200. Reachability is not package authentication. No independently pinned
feed key and qualified ImageBuilder apk installation path have been established
here. The gate always refuses opt-in, even if callers supply environment
variables naming a feed or a key. There is no unsigned/local-package escape hatch.

`verify-agent.py BUNDLE x86_64|aarch64` is an **offline preflight**, not an image
builder or an installer. A bundle contains `release.json`, `release.json.sig`,
`SHA256SUMS`, and the architecture-specific program, mode exactly 0755. It uses
the existing release-table verifier with repository release keys and the exact
repository table; environment overrides of release trust are ignored. It checks
signature, product, version, architecture-specific size and SHA-256, and refuses
versions <=1.9.1. It never executes the supplied program, copies arbitrary bundle
contents, or writes an overlay. Its JSON explicitly says package authentication
and image authorization are false. Example after a separately reviewed compatible
package pin exists:

```sh
python3 distribution/scripts/verify-agent.py /path/to/official-release-bundle aarch64
```

A successful artifact preflight alone cannot establish the CLI claim contract:
require a real signed-version integration test as well. The missing provider must
verify signed apk metadata and package hashes for **both** existing packages,
ensure their embedded release table agrees with the checked program, retain apk
signature verification in ImageBuilder, and fail on absent feed/metadata/packages.
Only then may it produce a clean generated FILES overlay containing
`/opt/letkite-agent/letkite-agent` (0755). Do not copy caller-provided configuration
or directories into FILES. Require >=256 MiB RAM and free writable storage for two
program copies (about 16 MiB for the current release; measure future releases).

### Runtime contract and release gates

For a future qualified provider, an image-only UCI default must sort **before**
`90-letkite-claim` (for example `80-letkite-os-claim`) and set `letkite.main.claim=1`
only for the proven compatible version. `95-letkite-os` is too late. The existing
package firstboot/setup helper owns initialization: preserve existing setup and
identity, retry unsuccessful firstboot on a later boot, and let the agent create
its procd service. Do not add a second service, watchdog, updater or claim loop.
Health supervision, restart policy and signed-update rollback belong to the
existing agent; verify their actual behavior in a lab before qualifying images.
For 1.6.1, use manual pairing after secure installation with `claim=0`.

The distribution must not widen the local ceiling. Before enabling remote use,
root must verify the existing agent's ceiling: shell off, files empty, GUI off,
handover/direct/env/mesh disabled, and tunnel targets limited to explicitly
approved local destinations (empty until approved). Do not write a guessed TOML
schema or replace a retained ceiling. No WAN ports, guest firewall overrides,
transparent proxy rules, LAN/WLAN changes or automatic Docker startup are added.

Run `sh distribution/scripts/letkite-health.sh` locally on the router after manual
installation for version, agent-owned service running state and ceiling presence.
This helper stays outside the default firmware overlay. It does not request claim
codes, expose identities, or prove connectivity/policy correctness.

Verify the agent-created `/lib/upgrade/keep.d/letkite-agent` retains **both**
`/etc/letkite/` and `/opt/letkite-agent/` with `sysupgrade -l` before upgrading;
if either is absent, stop and resolve it before any upgrade. Validate backup and
restore in an isolated VM, including permissions and power-loss behavior. These
paths contain device secrets at runtime: never commit them or distribute backups.
Do not layer an independent keep-list over the agent's uninstall lifecycle.

Unclaim is an owner action in LuCI/the dashboard; never silently clear identities
on boot or sysupgrade. Package removal invokes the existing agent uninstall and
removes its service/keep-list and `/opt/letkite-agent`; `/etc/letkite` is retained.
To permanently forget a device, remove it from the dashboard and explicitly delete
`/etc/letkite` after stopping/uninstalling the agent. A reset/reflash may restore
a firmware-embedded program; it must still generate a fresh identity locally.

Until the provider and claim gates are qualified, build with the default toggle
and install manually after flashing using the root README's official apk feed
procedure. Authenticate the feed key through a trusted independent channel before
trusting downloaded metadata; stop on signature errors. Do not use `curl|sh`, an
arbitrary executable, or disable apk signature checking as a workaround.

Optional Clash Meta / Mihomo binary integration: see [operator and trust policy](docs/mihomo.md). Default `ENABLE_MIHOMO=0`; no Mihomo/OpenClash APK is assumed available.
