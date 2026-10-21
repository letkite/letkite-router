# letkite-router

OpenWrt packages and the LuCI app for the [LetKite](https://letkite.com) agent.

[中文说明](README.zh-CN.md)

LetKite lets AI assistants on your account reach your machines, and, through a router, the devices behind it (a NAS, a printer, a camera's admin page, a PC to wake), within limits you set on each machine. On a router, the agent can also wake computers on the LAN and manage the router itself.

This repository contains:

- **`letkite-agent`**: an OpenWrt package that installs the LetKite agent.
- **`luci-app-letkite`**: Services → LetKite in LuCI. It shows the agent's status, pairs the router with your account (a code and a QR code), pauses and resumes the agent, sets its permissions, and shows its log.

**What this is not.** The agent itself is **not** here. It is a closed-source program, built and signed by LetKite, and published on `get.letkite.com`. This repository is the MIT-licensed packaging and LuCI app around it. The package does not contain the program: it downloads one exact release, checks its SHA-256, and installs it ([How the program is verified](#how-the-program-is-verified)).

## For router and device makers

We work with router, NAS and device makers to preinstall or integrate the LetKite agent:

- firmware images with the agent built in;
- OEM feeds;
- LuCI branding;
- joint testing on your hardware;
- new architectures, such as mipsel.

Write to **contact@letkite.com** with the subject starting with **`[Router partnership]`**. Please include:

- your company;
- the devices and SoCs;
- the OpenWrt version or vendor SDK;
- expected volumes;
- your timeline.

Please do not post this in a public issue.

## Supported

| | |
|---|---|
| OpenWrt | 25.12 (apk) and 24.10 (opkg). Vendor firmware based on other OpenWrt versions is not supported yet. |
| Architectures | x86_64; aarch64 (MediaTek MT798x, Rockchip, Raspberry Pi, armsr…); ARMv7 **with a VFPv3 FPU** (IPQ40xx, mvebu, armsr…) |
| Not supported | MIPS (mipsel, e.g. MT7621; mips), ARMv7 without VFPv3 (some BCM53xx), ARMv5/v6 |
| Hardware | 256 MB of RAM or more. Free flash for two copies of the program (about 16 MB), because an update writes the new copy before removing the old one. |

On an unsupported router, the install stops with a message that names the reason, and nothing is installed.

## Install from the LetKite feed

> **Available once the feed is published.** The feed and its keys are not on `get.letkite.com` yet. Until they are, use [Install over SSH](#install-over-ssh).

**OpenWrt 25.12 (apk):**

```sh
wget -O /etc/apk/keys/letkite-apk.pem https://get.letkite.com/openwrt/keys/letkite-apk.pem
echo 'https://get.letkite.com/openwrt/25.12/packages.adb' >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add luci-app-letkite
```

**OpenWrt 24.10 (opkg):**

```sh
wget -O /tmp/letkite-usign.pub https://get.letkite.com/openwrt/keys/letkite-usign.pub
opkg-key add /tmp/letkite-usign.pub
echo 'src/gz letkite https://get.letkite.com/openwrt/24.10' >> /etc/opkg/customfeeds.conf
opkg update
opkg install luci-app-letkite
```

`luci-app-letkite` pulls in `letkite-agent`. Install only `letkite-agent` if you don't use LuCI. Translations: `luci-i18n-letkite-zh-cn`, `-ja`, `-ko`, `-fr`, `-de`.

The packages are architecture-independent (`all`), so there is one feed per OpenWrt version.

## Install over SSH

Without the feed, the install script does the same job: it downloads the agent, checks it against the release's `SHA256SUMS`, and installs it in `/opt/letkite-agent`. Log in as root and run:

```sh
wget -qO- https://get.letkite.com/install.sh | sh
```

To pair the router as part of the install, use the command shown in the [dashboard](https://dashboard.letkite.com) under **Add device → Router (OpenWrt)**. It is the same line followed by `-s -- enroll …`.

## Pairing in LuCI

1. Open **Services → LetKite → Overview** and click **Pair**. You can give the router a name.
2. LuCI shows a code, a link and a QR code. Open the link (or scan the code with your phone), sign in to LetKite, and approve the code.
3. Once you approve it, the router appears in your dashboard and the agent's service starts.

**Pause** disconnects the agent for 30 minutes, an hour, a day, a custom time, or until you resume it. **Permissions** shows the router's local ceiling (see [Permissions](#permissions)). **Log** shows the agent's lines from `logread`.

## Permissions

The router's local ceiling, `/etc/letkite/ceiling.toml`, is the most AI assistants may ever do on this router, whatever your LetKite account allows: the dashboard can narrow it but never exceed it. Only root can change it. **Services → LetKite → Permissions** shows it.

**Switches.** Seven of its keys are true or false, and LuCI turns them on and off:

| Switch | On means |
|---|---|
| `handover` | someone at the device may hand it over to AI assistants and leave (meant for desktops) |
| `direct` | direct peer-to-peer transfers with the account's other devices |
| `updates` | the agent installs newer releases signed by LetKite |
| `env` | the environment variables set in the dashboard are written on the router, for the commands run there |
| `accelerate` | traffic to LetKite's own servers goes through its access points |
| `telemetry` | the agent sends its crash reports (version, system, where it failed; never commands, paths or output) |
| `mesh` | the router joins the account's mesh network, so its other devices can reach it as the account's rules allow |

Turning on `handover`, `direct`, `env` or `mesh` asks for confirmation first, because each widens what AI assistants on the account can do or reach on this router. The other three are about how the agent itself runs.

LuCI saves a switch with `letkite-agent ceiling set <switch> <true|false>`, which changes only that line of the file. The agent reads its ceiling only when it starts, so LuCI then restarts it (`/etc/init.d/letkite-agent restart`); the router is offline for LetKite for a few seconds.

**Other limits.** The rest of the ceiling is not true or false, so LuCI shows it read-only:

| Key | What |
|---|---|
| `shell` | `off` or `full`: whether AI assistants may run commands, shell sessions and terminals here. (`sandboxed` needs Landlock, which OpenWrt's kernel does not have.) |
| `files` | the most of the file system they may be granted; `[]` is nothing, `["*"]` no limit |
| `deny` | paths always hidden |
| `gui`, `gui_apps` | screen access; `off` and `[]` on a router |
| `tunnel_targets` | where tunnels may connect, such as `"192.168.1.0/24"` or `"192.168.1.10:80"` |
| `keep_awake`, `local_control` | power, and who at the device may pause the connection |

To change them, edit the file over SSH, check it, and restart the agent:

```sh
vi /etc/letkite/ceiling.toml
letkite-agent ceiling --path /etc/letkite/ceiling.toml   # prints what the agent reads, or the error
/etc/init.d/letkite-agent restart
```

Every key must be present and unknown keys are refused. The agent does not start with a ceiling it cannot read; LuCI then shows why.

## Uninstall

```sh
apk del -r letkite-agent                                          # 25.12
opkg remove --force-removal-of-dependent-packages letkite-agent   # 24.10
```

This removes `letkite-agent` together with what depends on it (`luci-app-letkite` and its translations).

Removing `letkite-agent` runs the agent's own `letkite-agent uninstall`, which stops and removes its procd service and sysupgrade keep list, and then deletes `/opt/letkite-agent`. **`/etc/letkite` stays.** It holds the node key, the enrollment and the ceiling, so installing again brings back the same node. To forget the node completely, also delete that directory and remove the router in the dashboard:

```sh
rm -rf /etc/letkite
```

## How the program is verified

The chain of trust is **feed signature → package → pinned SHA-256**:

1. Your package manager installs `letkite-agent` only from a feed index signed with LetKite's feed key: usign on 24.10, an apk v3 key on 25.12. The index lists each package's hash.
2. The package's pre-install script carries a table generated from the agent release: the version and the SHA-256 of the program for each architecture ([`packages/letkite-agent/files/release`](packages/letkite-agent/files/release)).
3. The script downloads `https://get.letkite.com/agent/v<version>/letkite-agent-linux-<arch>`, checks it with `sha256sum`, and installs it only on an exact match. On a mismatch, an unsupported CPU, too little flash or a failed download, the script fails, the install command fails, and no program and no service are left on the router. opkg (24.10) then stops, so the package is not installed at all. apk-tools (25.12) goes on after a failed pre-install script: it keeps a record of the package, which holds only the release table and is flagged with a script error. `apk del -r letkite-agent` removes it.

The table is regenerated only from a release whose `release.json` carries a valid Ed25519 signature from one of LetKite's agent release keys ([`keys/agent-release-keys.txt`](keys/agent-release-keys.txt), the same keys the agent itself trusts). `SHA256SUMS` must also agree with `release.json`. [`scripts/release-table.py`](scripts/release-table.py) does this; the scheduled `bump` workflow runs it and opens a pull request, and CI checks the pinned table against the signed release on every change.

Afterwards, the agent installs its own procd service (`letkite-agent install`). It then updates itself: it installs only releases signed with the same release keys, verifies their size and SHA-256, and rolls back an update that does not come up.

**Why `apk audit` stays clean.** The package does not own `/opt/letkite-agent/letkite-agent`; the program file is not in the package. The agent replaces that file when it updates itself, and a file the package owned would then show up as modified. The package owns only the release table, `/usr/share/letkite-agent/release`. The init script and the sysupgrade keep list belong to the agent, which writes them on install and removes them on uninstall, so the package and the agent never disagree about the service.

## Security

Please report vulnerabilities privately to **contact@letkite.com** with the subject starting with **`[Security]`**. Do not open a public issue. See [SECURITY.md](SECURITY.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Every commit needs a `Signed-off-by` line (DCO).

## License

MIT, see [LICENSE](LICENSE). This covers this repository only. The LetKite agent is distributed by LetKite under its own terms. The vendored QR code library is MIT licensed, see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
