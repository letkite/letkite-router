#!/usr/bin/env bash
# Run ShellCheck over every shell script here, including the ones that only
# exist once built: the letkite-agent pre-install script (files/release,
# then files/fetch.sh) and the install scripts inside the Makefiles
# (define Package/<name>/<postinst|prerm|postrm>, with make's $$ as $).
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

files=(
  packages/luci-app-letkite/root/usr/libexec/rpcd/letkite
  packages/letkite-agent/files/setup.sh
  packages/letkite-agent/files/profile.d/*.sh
  packages/letkite-agent/files/uci-defaults/*
  tests/fake-agent/letkite-agent
  tests/unit/*.sh
  tests/openwrt/*.sh
  scripts/*.sh
  distribution/scripts/*.sh
  distribution/tests/*.sh
  distribution/files/etc/uci-defaults/*
)

{ echo '#!/bin/sh'; cat packages/letkite-agent/files/release packages/letkite-agent/files/fetch.sh; } \
  > "$tmp/letkite-agent.preinst"
files+=("$tmp/letkite-agent.preinst")

for mk in packages/*/Makefile; do
  pkg=$(basename "$(dirname "$mk")")
  for script in postinst prerm postrm; do
    body=$(awk -v start="define Package/$pkg/$script" '
      $0 == start { on = 1; next }
      on && $0 == "endef" { exit }
      on { print }' "$mk")
    [[ -n $body ]] || continue
    printf '%s\n' "${body//\$\$/\$}" > "$tmp/$pkg.$script"
    files+=("$tmp/$pkg.$script")
  done
done

echo "shellcheck: ${#files[@]} files"
shellcheck -x "${files[@]}"
