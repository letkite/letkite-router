#!/usr/bin/env bash
# Build the packages with the official OpenWrt SDK for x86_64 (the packages
# are architecture-independent, so one SDK builds them for every router).
#
#   scripts/sdk-build.sh VERSION OUT     # e.g. 24.10.8 dist/24.10 (.ipk)
#                                        #      25.12.6 dist/25.12 (.apk)
#
# The SDK is checked against the release's sha256sums and cached in
# $SDK_CACHE. The feeds the build needs (OpenWrt itself for lua/host, LuCI
# for luci.mk and po2lmo) are fetched shallowly at the commits the SDK pins.
# This repository's packages/ is linked in as the feed "letkite".
#
# With FEED_USIGN_KEY (24.10: a usign secret key file) or FEED_APK_KEY
# (25.12: an EC private key in PEM), the index in OUT is signed with it;
# without, OUT has the packages and an unsigned index.
#
# Tests:
#   TEST_KEYS=DIR   make a throwaway key pair in DIR with the SDK's tools
#                   (usign: test.sec, test.pub; apk: test.pem, test.pub.pem)
#                   and sign the index with it
#   TAMPER=1        build letkite-agent only, pinning a wrong SHA-256 for
#                   x86_64 (the smoke test's install that must fail)
set -euo pipefail

version=${1:?usage: sdk-build.sh VERSION OUT}
out=${2:?usage: sdk-build.sh VERSION OUT}
repo=$(cd "$(dirname "$0")/.." && pwd)
cache=${SDK_CACHE:-$HOME/.cache/letkite-router-sdk}
site=https://downloads.openwrt.org/releases/$version/targets/x86/64
jobs=$(nproc 2>/dev/null || echo 2)

die() { echo "sdk-build.sh: $*" >&2; exit 1; }
step() { echo "== $*"; }

mkdir -p "$cache" "$out"
out=$(cd "$out" && pwd)

step "SDK $version"
sums=$(curl -fsSL "$site/sha256sums")
name=$(grep -oE 'openwrt-sdk-[^ ]*x86-64[^ ]*\.tar\.zst' <<<"$sums" | head -1)
[[ -n $name ]] || die "no SDK in $site/sha256sums"
if [[ ! -f "$cache/$name.ok" ]]; then
  curl -fsSL -o "$cache/$name" "$site/$name"
  grep -F " *$name" <<<"$sums" | sed 's/ \*/  /' | (cd "$cache" && sha256sum -c --quiet -) \
    || die "$name does not match the release's sha256sums"
  echo ok > "$cache/$name.ok"
fi
sdk="$cache/${name%.tar.zst}"
if [[ ! -d $sdk ]]; then
  tar --zstd -xf "$cache/$name" -C "$cache"
fi

# A feed at the commit or tag the SDK's feeds.conf.default names, fetched
# with depth 1 (scripts/feeds would clone the whole history).
# OpenWrt itself ("base") is linked at its package/ directory.
feed() { # name
  local line url ref root="" dir="$cache/feeds-$version/$1"
  # src-git[-full] [--root=DIR] NAME URL^COMMIT or URL;TAG
  line=$(grep -E "^src-git(-full)?( --[^ ]+)* $1 " "$sdk/feeds.conf.default") || die "no feed $1 in feeds.conf.default"
  url=$(awk '{ print $NF }' <<<"$line")
  [[ $1 != base ]] || root=/package
  case "$url" in
    *^*) ref=${url#*^}; url=${url%^*} ;;
    *\;*) ref=${url#*;}; url=${url%;*} ;;
    *) die "feed $1 is not pinned: $line" ;;
  esac
  # git.openwrt.org's repositories, from their GitHub mirrors (faster; same commits)
  case "$url" in
    https://git.openwrt.org/openwrt/openwrt.git) url=https://github.com/openwrt/openwrt.git ;;
    https://git.openwrt.org/project/luci.git) url=https://github.com/openwrt/luci.git ;;
  esac
  if [[ "$(cat "$dir/.letkite-ref" 2>/dev/null)" != "$url $ref" ]]; then
    rm -rf "$dir"
    git init -q "$dir"
    git -C "$dir" fetch -q --depth 1 "$url" "$ref"
    git -C "$dir" checkout -q FETCH_HEAD
    echo "$url $ref" > "$dir/.letkite-ref"
  fi
  echo "src-link $1 $dir$root"
}

packages_dir="$repo/packages"
packages=(letkite-agent luci-app-letkite)
if [[ -n ${TAMPER:-} ]]; then
  packages_dir="$cache/tampered-$version"
  rm -rf "$packages_dir"
  mkdir -p "$packages_dir"
  cp -R "$repo/packages/letkite-agent" "$packages_dir/"
  sed -i 's/^AGENT_SHA256_x86_64=.*/AGENT_SHA256_x86_64=0000000000000000000000000000000000000000000000000000000000000000/' \
    "$packages_dir/letkite-agent/files/release"
  packages=(letkite-agent)
fi

step "feeds"
{
  feed base
  feed luci
  echo "src-link letkite $packages_dir"
} > "$sdk/feeds.conf"
cd "$sdk"
./scripts/feeds update -a > /dev/null
./scripts/feeds install -p letkite -a > /dev/null
./scripts/feeds install lua luci-base > /dev/null

step "configure"
# only our packages are built: their dependencies come from OpenWrt's feeds
cat > .config <<CFG
# CONFIG_ALL is not set
# CONFIG_ALL_NONSHARED is not set
# CONFIG_ALL_KMODS is not set
# CONFIG_SIGNED_PACKAGES is not set
CONFIG_PACKAGE_letkite-agent=m
CONFIG_PACKAGE_luci-app-letkite=m
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_LUCI_LANG_ja=y
CONFIG_LUCI_LANG_ko=y
CONFIG_LUCI_LANG_fr=y
CONFIG_LUCI_LANG_de=y
CFG
make defconfig > /dev/null

step "build"
rm -rf bin/packages/*/letkite
for pkg in "${packages[@]}"; do
  make "package/$pkg/clean" > /dev/null 2>&1 || true
  make -j"$jobs" "package/$pkg/compile" V=s > "$out/build-$pkg.log" 2>&1 \
    || { tail -n 60 "$out/build-$pkg.log"; die "building $pkg failed (log: $out/build-$pkg.log)"; }
done

feed_dir=$(ls -d bin/packages/*/letkite)
rm -f "$out"/*.ipk "$out"/*.apk "$out"/Packages* "$out"/packages.adb "$out"/index.json
cp "$feed_dir"/*.[ia]pk "$out"/

if [[ -n ${TEST_KEYS:-} ]]; then
  step "throwaway signing key"
  mkdir -p "$TEST_KEYS"
  if compgen -G "$out/*.ipk" > /dev/null; then
    [[ -f $TEST_KEYS/test.sec ]] \
      || staging_dir/host/bin/usign -G -s "$TEST_KEYS/test.sec" -p "$TEST_KEYS/test.pub" -c "letkite-router test key"
    export FEED_USIGN_KEY="$TEST_KEYS/test.sec"
  else
    if [[ ! -f $TEST_KEYS/test.pem ]]; then
      staging_dir/host/bin/openssl ecparam -name prime256v1 -genkey -noout -out "$TEST_KEYS/test.pem"
      staging_dir/host/bin/openssl ec -in "$TEST_KEYS/test.pem" -pubout -out "$TEST_KEYS/test.pub.pem" 2> /dev/null
    fi
    export FEED_APK_KEY="$TEST_KEYS/test.pem"
  fi
fi

step "index"
"$repo/scripts/make-index.sh" "$sdk" "$out"
ls -l "$out"
