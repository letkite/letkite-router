#!/usr/bin/env bash
# Build target-specific OpenWrt images from checksummed upstream ImageBuilder.
# Never flashes a device. Requires bash, curl, tar, sha256sum, zstd, make.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
version=${OPENWRT_VERSION:-25.12.6}
cache=${IMAGEBUILDER_CACHE:-"$root/distribution/.cache"}
profile=""
dry=0
die() { echo "build-image: $*" >&2; exit 1; }
while (($#)); do
  case "$1" in
    --profile) (($# >= 2)) || die "missing --profile value"; profile=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done
case "$profile" in ax3000t|x86-full) ;; *) die "supported profiles: ax3000t, x86-full (RD08 intentionally blocked)" ;; esac
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid OpenWrt version"
# Profiles are audited source-controlled files, never externally supplied.
# shellcheck source=/dev/null
source "$root/distribution/profiles/$profile.env"
packages="$BASE_PACKAGES $EXTRA_PACKAGES"
if [[ ${ENABLE_DOCKER:-1} == 0 ]]; then
  packages=${packages//dockerd/}
  packages=${packages//docker/}
elif [[ $DOCKER_SUPPORTED == 0 && ${ENABLE_DOCKER:-0} == 1 ]]; then
  die "Docker is disabled on this constrained Xiaomi profile"
fi
if [[ ${ENABLE_PROXY:-0} == 1 ]]; then packages="$packages sing-box"; fi
site="https://downloads.openwrt.org/releases/$version/targets/$TARGET/$SUBTARGET"
out="$root/distribution/out/$profile"
echo "OpenWrt=$version hardware=$profile target=$TARGET/$SUBTARGET profile=$PROFILE"
echo "Packages=$packages"
echo "Site=$site"
if ((dry)); then exit 0; fi
for tool in curl sha256sum tar make zstd awk grep; do command -v "$tool" >/dev/null || die "missing $tool"; done
mkdir -p "$out" "$cache"
curl -fsSL --retry 3 "$site/sha256sums" -o "$cache/sha256sums-$version-$TARGET-$SUBTARGET"
sums="$cache/sha256sums-$version-$TARGET-$SUBTARGET"
name=$(awk '{print $2}' "$sums" | sed 's/^\*//' | grep -E '^openwrt-imagebuilder-.*\.Linux-x86_64\.tar\.zst$' | head -n 1)
[[ -n $name && $name != */* ]] || die "ImageBuilder archive not present in official checksum list"
archive="$cache/$name"
[[ -f $archive ]] || curl -fsSL --retry 3 "$site/$name" -o "$archive"
(cd "$cache" && awk -v n="$name" '{f=$2; if (substr(f,1,1)=="*") f=substr(f,2); if (f==n) print $1 "  " n}' "$sums" | sha256sum --check --status) || die "SHA-256 mismatch for $archive"
ib="$cache/${name%.tar.zst}"
[[ -d $ib ]] || tar --zstd -xf "$archive" -C "$cache"
[[ -f $ib/Makefile ]] || die "ImageBuilder not extracted"
# Keep files overlay deliberately minimal; never ship private data in it.
make -C "$ib" image PROFILE="$PROFILE" PACKAGES="$packages" FILES="$root/distribution/files"
find "$ib/bin/targets/$TARGET/$SUBTARGET" -maxdepth 1 -type f \( -name '*sysupgrade*' -o -name '*combined*' -o -name '*initramfs*' \) -exec cp -v {} "$out/" \;
(cd "$out" && sha256sum ./* > SHA256SUMS) || die "no output images"
echo "Build output: $out"
