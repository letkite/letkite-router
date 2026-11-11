# RD08 BE6500 Pro offline application staging

This is a separate OEM QSDK application installer for PR #15. It does not build or
install generic OpenWrt firmware. No router was accessed during development.
Only preexisting authorized manual/SSH access is supported. This package neither
obtains access nor changes SSH configuration. Keep normal SSH host-key checking;
verify a new host key independently. There are no network operations in either CLI.

## Evidence and limits

Read research: `RD08_VERSION_DIFF_AND_RECOVERY.md` and
`RD08_REVERSE_ENGINEERING_REPORT.md` (2026-11-07). The later extraction correction
supersedes the earlier incomplete-rootfs observation. Both researched releases
are OEM OpenWrt 18.06-SNAPSHOT, ipq53xx/generic, ARM64, kernel 5.4.213.
Firmware package hashes from those reports:

- 1.1.96: `355f28072fedafc401438c6747e53d055b3a140eb7dfc6e10a658ae7d8750a5a`
- 1.1.123: `c4d3259dae532ba1e50d55e914c8759f06e1568f42d2e708d0a69337bc5c9093`

These hashes identify research inputs, not executable trust or physical-device
qualification. Matching kernel versions do not make radio drivers interchangeable.
The existing `distribution/platform/detect.py` is a broader inventory classifier;
this installer adds an exact OEM release/version allowlist and independent board
and SoC evidence. No existing platform or plugin code is changed.

[Wetoria's README](https://github.com/Wetoria/xiaomi-be6500pro/blob/main/README.md)
describes an OEM SSH exploit and ShellCrash installation. It is not evidence of
generic OpenWrt support or a safe persistence hook. Its access, downgrade, flash,
and remote installer procedures are deliberately absent here.

The observed OEM version metadata is under
`/usr/share/xiaoqiang/xiaoqiang_version`. An accepted snapshot additionally needs
`/tmp/sysinfo/board_name` exactly `RD08` or `xiaomi,rd08`, an independent IPQ5332
CPU token, and the exact OEM release fields. Those board names are conservative
candidates from the repository's device policy, not verified physical-device
observations. A unit reporting another board name **fails closed**; do not rename
its evidence to make it pass. Research and review a new profile separately.
Snapshot files are untrusted data, never sourced or executed. This is fingerprint
matching, not remote attestation or firmware authenticity verification.

## Offline host workflow

Python 3 standard library only. Arrange a local directory containing these
read-only text files, captured manually through already authorized access:

```
etc/openwrt_release
usr/share/xiaoqiang/xiaoqiang_version
proc/sys/kernel/osrelease
proc/cpuinfo
tmp/sysinfo/board_name
```

Copy only those files as regular files (no symlinks), preserving the relative
paths. Do not copy passwords, keys, tokens, full configuration or credentials.
The tools do not collect a snapshot remotely or read unrelated snapshot files.

```
python3 distribution/installers/rd08/rd08.py inspect --snapshot /absolute/snapshot
python3 distribution/installers/rd08/rd08.py prepare \
  --snapshot /absolute/snapshot --agent /absolute/trusted/letkite-agent \
  --sha256 EXPECTED_64_HEX_SHA256 --output /absolute/new-bundle --dry-run
```

Replace the placeholders with locally reviewed inputs. Repeat without `--dry-run`
to create a new directory; existing output directories are refused. The dry run
performs all input checks and creates no directories, files, locks or backups.
Use `python3 -B` if running through an import-based harness to suppress Python
bytecode caches; direct CLI invocation does not import local modules.

The supplied binary must be a trusted local ARM64 ELF executable with a separately
obtained expected SHA256. The checker never executes it. ELF headers do not prove
libc, interpreter, syscall or runtime compatibility. Establish provenance, license,
ABI and resource compatibility separately before manual execution. Hashes are not
signatures and the self-contained manifest is not a trust anchor. Keep an
independently trusted copy/hash of the bundle and `router.sh` for transport review.

The manifest contains fixed safe basenames, SHA256, sizes, matched platform facts
and snapshot hashes. It contains no snapshot contents, credentials, enrollment
configuration or automatically generated identity. A binary itself is opaque;
operators must provide a clean release artifact without embedded credentials.
The existing pinned Agent 1.6.1 does not establish unattended claim support.
`distribution/scripts/verify-agent.py` rejects claim-incompatible versions; this
staging tool does not bypass that policy to enable enrollment. Pairing is manual.

Optional `--mihomo /absolute/local/mihomo --mihomo-sha256 EXPECTED_SHA256`
stages a separately trusted ARM64 binary. It is disabled, gets no configuration,
firewall changes or service, and is not launched. No Docker support is assumed.

## Router-side review and explicit apply

Transfer the new bundle and independently reviewed `router.sh` manually over an
authenticated channel into a private root-owned staging directory. Retain normal
SSH host verification. Run the script by explicit path. Do not run from a shared
or writable-by-other-users directory. Files must stay unchanged during inspection
and apply: this POSIX shell tool does not defend against a concurrent privileged
writer. The installer rejects links, unexpected entries, unsafe checksum paths,
duplicate entries, hash/size failures and non-ARM64 headers.

```
sh /absolute/reviewed/router.sh --check /absolute/new-bundle
sh /absolute/reviewed/router.sh --dry-run /absolute/new-bundle
sh /absolute/reviewed/router.sh --apply /absolute/new-bundle
```

`--check` and `--dry-run` are equivalent, read-only, and never execute a payload.
For offline shell fixture verification only, append `--snapshot /absolute/snapshot`;
this option is rejected with apply. Live checks always read the router's own
fingerprints. Unknown versions/kernels/boards fail closed before any storage writes.

Apply requires root and a preexisting writable `/data` mount. It creates only
`/data/letkite-rd08`, a transaction lock, staged/current files and an optional
previous backup. Payloads are checked again after copying. Space checks reserve
twice the incoming directory size plus 1 MiB. A repeated identical bundle changes
no payload; the temporary transaction lock is still created and removed.

First apply creates `current`. A later different bundle renames the old `current`
to `previous` before promoting the verified staged copy. Only one previous backup
is retained; another update fails until the operator archives the backup manually.

```
sh /absolute/reviewed/router.sh --rollback
```

Rollback validates both copies and swaps `current` and `previous`. It rolls back
application files only, not firmware, running processes or external state. Stop
any manually started process before apply/rollback; the installer does not kill
processes or migrate agent data. If a rename fails synchronously, it attempts to
restore the previous current directory. Power loss and signals can leave a lock
or staged directory; inspect and recover those files manually. No power-loss
atomicity or automatic health rollback is claimed. No recursive deletion is used.

## Manual activation only

Review `current/manifest.json`, verify runtime ABI and decide the agent's supported
manual invocation/pairing procedure from its trusted release documentation. The
installer deliberately supplies no default launch arguments, unattended claim,
autostart, generated service, or vendor init hook. No persistence hook is verified.
Mihomo remains inactive and non-executable until an operator separately reviews
and enables it. Applying a bundle does not execute either program.

No vendor init, SSH settings, NVRAM, firewall, DNS, kernel, modules, radio firmware,
OEM updater, bootloader, ART or partition is changed. Backups cover application
files only. OEM reset/OTA and `/data` recovery may remove staged applications;
this tool does not promise retention across those operations. No downgrade,
CGI exploit, telnet/UART enablement, flash operation or remote shell installer is
implemented. OEM recovery behavior and ART preservation remain unverified.

## Validation

```
python3 -B distribution/tests/test-rd08-installer.py
sh -n distribution/installers/rd08/router.sh
```

Tests use synthetic fixtures and minimal ELF headers, never a real router or real
agent execution. Apply/rollback tests rewrite a private copy of the shell script
to a temporary fixture root and storage, removing only root and mount prerequisites.
Production has no writable fixture-root mode. Hardware, live BusyBox behavior,
agent ABI, available resources and pairing need separate authorized validation.
