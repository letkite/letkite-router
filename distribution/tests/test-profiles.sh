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
echo "All distribution profile checks passed"
