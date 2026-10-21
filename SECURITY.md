# Security

## Reporting a vulnerability

Please report security issues privately by email to **contact@letkite.com**, with a subject that starts with **`[Security]`**. Do not open a public issue or pull request for them.

Please include:

- what is affected: the `letkite-agent` package, `luci-app-letkite`, the feed, or the build and publishing workflows;
- the OpenWrt version and architecture;
- steps to reproduce, and what an attacker gains.

We will acknowledge your report and keep you informed while we fix it.

## Scope

This repository is the packaging and the LuCI app. Reports about the LetKite agent program itself, the LetKite service or `get.letkite.com` are welcome at the same address.

Of particular interest here:

- anything that lets a package install a program other than the release pinned in `packages/letkite-agent/files/release`;
- the rpcd plugin (`/usr/libexec/rpcd/letkite`): arguments that reach a shell, or methods reachable without the LuCI ACL;
- the workflows: anything that lets a pull request reach the signing keys or the publishing role.
