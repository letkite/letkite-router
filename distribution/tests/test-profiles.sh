#!/usr/bin/env bash
# build-image.sh without building: profiles, switches, and what it refuses.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
build="$root/distribution/scripts/build-image.sh"
fail() { echo "test-profiles: $*" >&2; exit 1; }

bash "$build" --profile ax3000t --dry-run | grep -q 'profile=xiaomi_mi-router-ax3000t$' || fail "AX3000T profile"
bash "$build" --profile x86-full --dry-run | grep -q 'dockerd docker luci-app-dockerman' || fail "x86 Docker by default"
if ENABLE_DOCKER=0 bash "$build" --profile x86-full --dry-run | grep -q dockerd; then fail "ENABLE_DOCKER=0 kept Docker"; fi
if ENABLE_DOCKER=1 bash "$build" --profile ax3000t --dry-run >/dev/null 2>&1; then fail "Docker accepted on AX3000T"; fi
if ENABLE_DOCKER=yes bash "$build" --profile x86-full --dry-run >/dev/null 2>&1; then fail "bad ENABLE_DOCKER accepted"; fi
for p in rd08 ../profiles/ax3000t ""; do
  if bash "$build" --profile "$p" --dry-run >/dev/null 2>&1; then fail "profile '$p' accepted"; fi
done
if OPENWRT_VERSION='25.12;x' bash "$build" --profile ax3000t --dry-run >/dev/null 2>&1; then fail "bad version accepted"; fi
# No proxy software in any profile
for p in ax3000t x86-full; do
  if bash "$build" --profile "$p" --dry-run | grep -Eiq 'sing-box|mihomo|clash'; then fail "proxy package in $p"; fi
done

# ENABLE_LETKITE=1 stops before any download or build, dry run or not.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for command in curl make tar; do
  printf '#!/bin/sh\necho unexpected-call >&2\nexit 99\n' > "$work/$command"
  chmod 755 "$work/$command"
done
if PATH="$work:$PATH" ENABLE_LETKITE=1 bash "$build" --profile x86-full >"$work/log" 2>&1; then
  fail "ENABLE_LETKITE=1 accepted"
fi
grep -q 'not built into images yet' "$work/log" || fail "ENABLE_LETKITE=1 message"
if grep -q unexpected-call "$work/log"; then fail "ENABLE_LETKITE=1 reached curl, tar or make"; fi
for p in ax3000t x86-full; do
  if ENABLE_LETKITE=1 bash "$build" --profile "$p" --dry-run >/dev/null 2>&1; then fail "ENABLE_LETKITE=1 dry run accepted"; fi
  diff <(bash "$build" --profile "$p" --dry-run) <(ENABLE_LETKITE=0 bash "$build" --profile "$p" --dry-run)
done
if ENABLE_LETKITE=invalid bash "$build" --profile ax3000t --dry-run >/dev/null 2>&1; then fail "bad ENABLE_LETKITE accepted"; fi

# The overlay that goes into every image holds no node identity or agent.
if find "$root/distribution/files" \( -iname '*agent*' -o -iname '*node.key*' -o -iname '*setup.toml*' \
  -o -iname '*ceiling*' \) | grep -q .; then
  fail "agent data in distribution/files"
fi
echo "All distribution profile checks passed"
