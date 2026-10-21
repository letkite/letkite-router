#!/usr/bin/env bash
# Index (and sign) a directory of built packages as an OpenWrt feed, with the
# SDK's own tools, as `make package/index` does:
#
#   scripts/make-index.sh SDK DIR
#
# .ipk (24.10): Packages, Packages.gz, and with FEED_USIGN_KEY (a usign
# secret key file) Packages.sig. .apk (25.12): packages.adb, signed with
# FEED_APK_KEY (an EC private key in PEM) if given.
set -euo pipefail

sdk=${1:?usage: make-index.sh SDK DIR}
dir=${2:?usage: make-index.sh SDK DIR}
host="$sdk/staging_dir/host/bin"
# the SDK's scripts call its host tools by name or through $MKHASH
export PATH="$host:$PATH" MKHASH="$host/mkhash"
cd "$dir"

die() { echo "make-index.sh: $*" >&2; exit 1; }

if compgen -G '*.ipk' > /dev/null; then
  "$sdk/scripts/ipkg-make-index.sh" . > Packages.manifest
  grep -vE '^(Maintainer|LicenseFiles|Source|SourceName|Require|SourceDateEpoch)' Packages.manifest > Packages
  rm -f Packages.manifest
  # usign's SHA-512 bug: OpenWrt pads these lengths (package/Makefile)
  case "$(((64 + $(stat -L -c%s Packages)) % 128))" in
    110 | 111) { echo ""; echo ""; } >> Packages ;;
  esac
  gzip -9nc Packages > Packages.gz
  rm -f Packages.sig
  if [[ -n ${FEED_USIGN_KEY:-} ]]; then
    "$host/usign" -S -m Packages -s "$FEED_USIGN_KEY"
    echo "signed Packages"
  fi
elif compgen -G '*.apk' > /dev/null; then
  sign=()
  [[ -z ${FEED_APK_KEY:-} ]] || sign=(--sign "$FEED_APK_KEY")
  "$host/apk" mkndx --allow-untrusted "${sign[@]}" --output packages.adb ./*.apk
  [[ -z ${FEED_APK_KEY:-} ]] || echo "signed packages.adb"
else
  die "no .ipk or .apk in $dir"
fi
