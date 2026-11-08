#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
build="$root/distribution/scripts/build-image.sh"
bash "$build" --profile ax3000t --dry-run | grep -q 'xiaomi_mi-router-ax3000t'
bash "$build" --profile x86-full --dry-run | grep -q 'dockerd docker luci-app-dockerman'
if ENABLE_DOCKER=0 bash "$build" --profile x86-full --dry-run | grep -q 'dockerd'; then echo "Docker disable failed" >&2; exit 1; fi
ENABLE_PROXY=1 bash "$build" --profile ax3000t --dry-run | grep -q 'sing-box'
if ENABLE_DOCKER=1 bash "$build" --profile ax3000t --dry-run >/dev/null 2>&1; then
  echo "ERROR: AX3000T Docker should be blocked" >&2; exit 1
fi
if bash "$build" --profile rd08 --dry-run >/dev/null 2>&1; then
  echo "ERROR: RD08 generic image must be blocked" >&2; exit 1
fi
# Poison network/make commands: even a non-dry opt-in must stop before them.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
for command in curl make; do
  printf '#!/bin/sh\necho unexpected-provider-access >&2\nexit 99\n' > "$work/$command"
  chmod 755 "$work/$command"
done
if PATH="$work:$PATH" ENABLE_LETKITE=1 bash "$build" --profile x86-full >"$work/log" 2>&1; then
  echo "ERROR: absent provider accepted" >&2; exit 1
fi
grep -q 'authenticated apk provider not qualified' "$work/log"
if grep -q unexpected-provider-access "$work/log"; then
  echo "ERROR: opt-in reached network or make" >&2; exit 1
fi
# Opt-in fails before any downloads, overlay generation or image mutation.
for profile in ax3000t x86-full; do
  if ENABLE_LETKITE=1 bash "$build" --profile "$profile" --dry-run >/dev/null 2>&1; then
    echo "ERROR: unauthenticated LetKite provider accepted" >&2; exit 1
  fi
  diff <(bash "$build" --profile "$profile" --dry-run) <(ENABLE_LETKITE=0 bash "$build" --profile "$profile" --dry-run)
done
if ENABLE_LETKITE=invalid bash "$build" --profile ax3000t --dry-run >/dev/null 2>&1; then
  echo "ERROR: invalid LetKite toggle accepted" >&2; exit 1
fi
if find "$root/distribution/files" -iname '*agent*' -o -iname '*node.key*' -o -iname '*setup.toml*' | grep -q .; then
  echo "ERROR: agent data in default overlay" >&2; exit 1
fi
echo "All distribution profile checks passed"
