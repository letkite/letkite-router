# letkite-router

[LetKite](https://letkite.com) agent 的 OpenWrt 软件包和 LuCI 应用。

[English](README.md)

LetKite 让你账户里的 AI 助手访问你的机器。通过路由器，它们还能访问路由器后面的设备，比如 NAS、打印机、摄像头的管理页，或者需要唤醒的电脑。能做什么，由你在每台机器上设定的上限决定。在路由器上，agent 还能唤醒局域网里的电脑、管理路由器本身。

本仓库包含：

- **`letkite-agent`**：安装 LetKite agent 的 OpenWrt 软件包。
- **`luci-app-letkite`**：LuCI 里的「服务 → LetKite」。它显示 agent 的状态，把路由器配对到你的账户（显示配对码和二维码），暂停和恢复 agent，设置权限，查看日志。

**这里没有什么。** agent 程序本身**不在**这里。它是闭源程序，由 LetKite 编译、签名，发布在 `get.letkite.com`。本仓库是它外面的 MIT 许可的打包和 LuCI 应用。软件包里不含程序：安装时下载一个确定的版本，核对 SHA-256 以后才装上（见[程序如何验证](#程序如何验证)）。

## 厂商合作

我们和路由器、NAS 及其他设备厂商合作，预装或集成 LetKite agent：

- 内置 agent 的固件镜像；
- OEM 软件源；
- LuCI 品牌定制；
- 在你们的硬件上联合测试；
- 新架构，例如 mipsel。

请发邮件到 **contact@letkite.com**，标题以 **`[Router partnership]`** 开头，并写明：

- 公司；
- 设备和 SoC；
- OpenWrt 版本或厂商 SDK；
- 预计出货量；
- 时间安排。

请不要发在公开的 issue 里。

## 支持范围

| | |
|---|---|
| OpenWrt | 25.12（apk）和 24.10（opkg）。基于其他 OpenWrt 版本的厂商固件暂不支持。 |
| 架构 | x86_64；aarch64（联发科 MT798x、瑞芯微、树莓派、armsr 等）；**带 VFPv3 浮点单元**的 ARMv7（IPQ40xx、mvebu、armsr 等） |
| 不支持 | MIPS（mipsel，如 MT7621；mips）、没有 VFPv3 的 ARMv7（部分 BCM53xx）、ARMv5/v6 |
| 硬件 | 内存 256 MB 起。闪存要放得下两份程序（约 16 MB），因为升级时先写新程序，再删旧的。 |

在不支持的路由器上，安装会停下来并说明原因，什么都不会装上。

## 从 LetKite 软件源安装

> **软件源发布后可用。** 软件源和它的公钥还没有放到 `get.letkite.com` 上。在那之前，请用[通过 SSH 安装](#通过-ssh-安装)。

**OpenWrt 25.12（apk）：**

```sh
wget -O /etc/apk/keys/letkite-apk.pem https://get.letkite.com/openwrt/keys/letkite-apk.pem
echo 'https://get.letkite.com/openwrt/25.12/packages.adb' >> /etc/apk/repositories.d/customfeeds.list
apk update
apk add luci-app-letkite
```

**OpenWrt 24.10（opkg）：**

```sh
wget -O /tmp/letkite-usign.pub https://get.letkite.com/openwrt/keys/letkite-usign.pub
opkg-key add /tmp/letkite-usign.pub
echo 'src/gz letkite https://get.letkite.com/openwrt/24.10' >> /etc/opkg/customfeeds.conf
opkg update
opkg install luci-app-letkite
```

`luci-app-letkite` 会一并装上 `letkite-agent`。不用 LuCI 的话，只装 `letkite-agent` 就行。翻译包：`luci-i18n-letkite-zh-cn`、`-ja`、`-ko`、`-fr`、`-de`。

这些软件包与架构无关（`all`），所以每个 OpenWrt 版本只有一个软件源。

## 通过 SSH 安装

没有软件源时，安装脚本做同样的事：下载 agent，按发布的 `SHA256SUMS` 核对，装到 `/opt/letkite-agent`。以 root 登录后运行：

```sh
wget -qO- https://get.letkite.com/install.sh | sh
```

想在安装时一并配对，请用[控制台](https://dashboard.letkite.com)里 **添加设备 → 路由器（OpenWrt）** 给出的命令。它是同一行命令，后面接 `-s -- enroll …`。

## 在 LuCI 里配对

1. 打开 **服务 → LetKite → 概览**，点 **配对**。可以给路由器起个名字。
2. LuCI 显示一个配对码、一个链接和一个二维码。打开链接（或用手机扫码），登录 LetKite，批准这个配对码。
3. 批准以后，路由器出现在你的控制台里，agent 的服务随之启动。

**暂停**会断开 agent：30 分钟、1 小时、1 天、自定时长，或者直到手动恢复。**权限**页显示路由器本地的上限：无论账户允许什么，AI 助手在这台路由器上最多只能做这些。打开执行命令、shell、终端或文件访问时，会先请你确认。**日志**页显示 `logread` 里 agent 的日志。

> **agent 1.5.0。** LuCI 里的配对、完整状态和权限开关要用到 1.5.0 还没有的 agent 命令：`status --json`、`enroll --no-browser --json` 和 `ceiling show|set`。之后的 agent 版本会加上。在那之前，LuCI 显示基本状态（版本、是否已配对、服务是否在运行）和日志；配对请通过 SSH 运行控制台给出的命令。agent 会自动升级，升级后 LuCI 就有这些功能，不用重新安装。

## 卸载

```sh
apk del luci-app-letkite letkite-agent              # 25.12
opkg remove luci-app-letkite letkite-agent          # 24.10
```

卸载 `letkite-agent` 时，先运行 agent 自己的 `letkite-agent uninstall`，停止并删除它的 procd 服务和 sysupgrade 保留清单，然后删除 `/opt/letkite-agent`。**`/etc/letkite` 会保留。** 那里有节点密钥、注册信息和上限，所以重新安装后还是同一个节点。要彻底忘掉这个节点，再删除这个目录，并在控制台里移除这台路由器：

```sh
rm -rf /etc/letkite
```

## 程序如何验证

信任链是 **软件源签名 → 软件包 → 固定的 SHA-256**：

1. 包管理器只从带 LetKite 软件源签名的索引安装 `letkite-agent`：24.10 用 usign，25.12 用 apk v3 密钥。索引里列着每个软件包的哈希。
2. 软件包的安装前脚本带着一张从 agent 发布生成的表：版本号，以及每种架构程序的 SHA-256（[`packages/letkite-agent/files/release`](packages/letkite-agent/files/release)）。
3. 脚本下载 `https://get.letkite.com/agent/v<版本>/letkite-agent-linux-<架构>`，用 `sha256sum` 核对，完全一致才安装。哈希不符、CPU 不支持、闪存不够或者下载失败时，脚本在软件包装上之前就失败，路由器上什么都不会留下。

这张表只会从这样的发布重新生成：它的 `release.json` 带有 LetKite agent 发布密钥之一的有效 Ed25519 签名（[`keys/agent-release-keys.txt`](keys/agent-release-keys.txt)，和 agent 自己信任的是同一组密钥），而且 `SHA256SUMS` 和 `release.json` 一致。[`scripts/release-table.py`](scripts/release-table.py) 负责这些检查；定时的 `bump` 工作流运行它并开 pull request，每次改动时 CI 也会拿固定的表去核对签名过的发布。

之后，agent 自己安装 procd 服务（`letkite-agent install`），并自动升级：它只安装用同一组发布密钥签名的版本，核对大小和 SHA-256，起不来的升级会自动回滚。

**为什么 `apk audit` 不报异常。** 软件包不拥有 `/opt/letkite-agent/letkite-agent`，程序文件不在包里。agent 自我升级时会替换这个文件；如果它属于软件包，替换后就会显示为被修改。软件包只拥有发布表 `/usr/share/letkite-agent/release`。init 脚本和 sysupgrade 保留清单属于 agent，由它在安装时写入、在卸载时删除，所以软件包和 agent 对服务的认识始终一致。

## 安全

请把漏洞私下报告到 **contact@letkite.com**，标题以 **`[Security]`** 开头。请不要开公开 issue。详见 [SECURITY.md](SECURITY.md)。

## 参与贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。每个提交都要带 `Signed-off-by` 行（DCO）。

## 许可

MIT，见 [LICENSE](LICENSE)。它只适用于本仓库。LetKite agent 由 LetKite 按它自己的条款分发。内置的二维码库使用 MIT 许可，见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
