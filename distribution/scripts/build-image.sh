#!/usr/bin/env bash
# Build OpenWrt images for a LetKite Router OS profile with the official,
# checksummed OpenWrt ImageBuilder. Never flashes or touches a device.
#
#   distribution/scripts/build-image.sh --profile ax3000t|x86-full [--dry-run]
#
# Requires bash, curl, sha256sum, tar, zstd, make, awk, grep and the OpenWrt
# ImageBuilder's own prerequisites. Images land in distribution/out/<profile>/
# with a SHA256SUMS of their own.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
version=${OPENWRT_VERSION:-25.12.6}
cache=${IMAGEBUILDER_CACHE:-"$root/distribution/.cache"}
choice=""
dry=0
die() { echo "build-image: $*" >&2; exit 1; }
while (($#)); do
  case "$1" in
    --profile) (($# >= 2)) || die "missing --profile value"; choice=$2; shift 2 ;;
    --dry-run) dry=1; shift ;;
    *) die "unknown argument: $1" ;;
  esac
done
case "$choice" in ax3000t|x86-full) ;; *) die "supported profiles: ax3000t, x86-full" ;; esac
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "invalid OpenWrt version: $version"
# Profiles are reviewed files in this repository, never caller-supplied paths.
# shellcheck source=/dev/null
source "$root/distribution/profiles/$choice.env"
packages="$BASE_PACKAGES"
case "${ENABLE_DOCKER:-$DOCKER_SUPPORTED}" in
  0) ;;
  1) [[ $DOCKER_SUPPORTED == 1 ]] || die "Docker is not available on the $choice profile"
     packages="$packages $EXTRA_PACKAGES" ;;
  *) die "ENABLE_DOCKER must be 0 or 1" ;;
esac
# The agent is not in the images yet: no authenticated way to install the
# signed letkite-agent and luci-app-letkite packages in ImageBuilder has been
# qualified. Install them after flashing (README.md, "LetKite").
case "${ENABLE_LETKITE:-0}" in
  0) ;;
  1) die "ENABLE_LETKITE: the LetKite packages are not built into images yet; install them after flashing (distribution/README.md)" ;;
  *) die "ENABLE_LETKITE must be 0 or 1" ;;
esac
site="https://downloads.openwrt.org/releases/$version/targets/$TARGET/$SUBTARGET"
out="$root/distribution/out/$choice"
echo "OpenWrt=$version hardware=$choice target=$TARGET/$SUBTARGET profile=$PROFILE"
echo "Packages=$packages"
echo "Site=$site"
echo "Output=$out"
if ((dry)); then exit 0; fi
for tool in curl sha256sum tar make zstd awk grep; do command -v "$tool" >/dev/null || die "missing $tool"; done
mkdir -p "$cache"
sums="$cache/sha256sums-$version-$TARGET-$SUBTARGET"
curl -fsSL --proto '=https' --retry 3 "$site/sha256sums" -o "$sums"
name=$(awk '{f=$2; sub(/^\*/, "", f); print f}' "$sums" | grep -E '^openwrt-imagebuilder-.*\.Linux-x86_64\.tar\.zst$' | head -n 1)
[[ -n $name && $name != */* ]] || die "no ImageBuilder in the release's sha256sums"
want=$(awk -v n="$name" '{f=$2; sub(/^\*/, "", f); if (f == n) print $1}' "$sums")
[[ $want =~ ^[0-9a-f]{64}$ ]] || die "no SHA-256 for $name"
archive="$cache/$name"
if [[ ! -f $archive ]] || [[ $(sha256sum "$archive" | awk '{print $1}') != "$want" ]]; then
  rm -f "$archive"
  curl -fsSL --proto '=https' --retry 3 "$site/$name" -o "$archive.part"
  mv "$archive.part" "$archive"
fi
[[ $(sha256sum "$archive" | awk '{print $1}') == "$want" ]] || die "SHA-256 mismatch for $name"
# Extract afresh unless this tree came from exactly this archive: a reused
# tree must not outlive the archive it was checked against.
ib="$cache/${name%.tar.zst}"
if [[ ! -f $ib/.letkite-archive-sha256 ]] || [[ $(cat "$ib/.letkite-archive-sha256") != "$want" ]]; then
  rm -rf "$ib"
  tar --zstd -xf "$archive" -C "$cache"
  [[ -f $ib/Makefile ]] || die "ImageBuilder not extracted"
  echo "$want" > "$ib/.letkite-archive-sha256"
fi
# Images from an earlier build of this target must not reach this output.
bin="$ib/bin/targets/$TARGET/$SUBTARGET"
rm -rf "$bin" "$out"
mkdir -p "$out"
make -C "$ib" image PROFILE="$PROFILE" PACKAGES="$packages" FILES="$root/distribution/files" \
  ${ROOTFS_MB:+ROOTFS_PARTSIZE="$ROOTFS_MB"}
find "$bin" -maxdepth 1 -type f \( -name '*sysupgrade*' -o -name '*combined*' -o -name '*factory*' \
  -o -name '*initramfs*' -o -name '*.manifest' \) -exec cp {} "$out/" \;
(cd "$out" && find . -maxdepth 1 -type f -printf '%P\0' | sort -z | xargs -0 -r sha256sum > "$cache/SHA256SUMS.$$") \
  || die "checksum generation failed"
mv "$cache/SHA256SUMS.$$" "$out/SHA256SUMS"
[[ -s "$out/SHA256SUMS" ]] || die "no images were built"
echo "Built: $out"
