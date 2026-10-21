# Contributing

Thank you for helping. Bug reports and pull requests are welcome. For security issues, see [SECURITY.md](SECURITY.md). Partnership requests go by email (see the README).

## Developer Certificate of Origin

Every commit must be signed off. With the sign-off, you certify the [Developer Certificate of Origin](https://developercertificate.org/): you wrote the change, or otherwise have the right to submit it under this repository's MIT license.

```sh
git commit -s
```

This adds a line with your name and email to the commit message:

```
Signed-off-by: Your Name <you@example.com>
```

Pull requests with unsigned commits cannot be merged.

## Layout

| Path | What |
|---|---|
| `packages/letkite-agent/` | The package that installs the agent. `files/release` is the pinned release (generated); `files/fetch.sh` is the pre-install script. |
| `packages/luci-app-letkite/` | The LuCI app: views (`htdocs/`), the rpcd plugin, ACL and menu (`root/`), translations (`po/`). |
| `keys/agent-release-keys.txt` | Public keys of LetKite's agent releases (for `scripts/release-table.py`). |
| `scripts/` | SDK build, feed index, release table, lint, i18n. |
| `tests/` | Unit tests, the fake agent, and the QEMU smoke test. |

## Tests

What CI runs, and how to run it yourself:

```sh
# ShellCheck over every shell script, including the scripts inside the Makefiles
scripts/lint-shell.sh

# ESLint over the LuCI JavaScript
npm ci && npm run lint

# translations cover every string (after changing a string: scripts/i18n.py pot)
scripts/i18n.py check

# the pre-install script (download, SHA-256, architectures) and the release table
tests/unit/fetch.sh
tests/unit/release-table.sh
scripts/release-table.py check        # the pinned table matches its signed release

# the rpcd plugin against the fake agent, on OpenWrt's BusyBox, jshn and jsonfilter
docker run --rm -v "$PWD:/src:ro" openwrt/rootfs:x86_64-openwrt-24.10 /bin/sh /src/tests/unit/rpcd.sh

# build with the official SDK, the feed signed with a throwaway key
TEST_KEYS=/tmp/keys scripts/sdk-build.sh 24.10.8 dist/24.10
TEST_KEYS=/tmp/keys TAMPER=1 scripts/sdk-build.sh 24.10.8 dist/tampered-24.10

# install it on OpenWrt in QEMU (KVM if available)
tests/openwrt/smoke.sh 24.10.8 dist/24.10 /tmp/keys/test.pub dist/tampered-24.10
```

The SDK needs the [OpenWrt build prerequisites](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem) and about 5 GB of disk. QEMU needs `qemu-system-x86` and `qemu-utils`.

## Conventions

- Shell runs on BusyBox `ash`: POSIX sh only, no bash. Every user-supplied value is validated before use and passed as an argument, never interpolated into a command line.
- The rpcd plugin exposes only the methods in its `list`, and the ACL lists each one.
- User-facing strings go through `_()`. After changing them, run `scripts/i18n.py pot` and update `po/*/letkite.po`.
- Do not edit `packages/letkite-agent/files/release` by hand; run `scripts/release-table.py write VERSION`. It refuses a release whose signature does not verify.
- GitHub Actions are pinned to a commit SHA.
