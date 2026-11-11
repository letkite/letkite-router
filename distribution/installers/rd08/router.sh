#!/bin/sh
# No network, enrollment, service activation, vendor init edits or flash operations.
set -eu
PATH=/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 077
ROOT=/
BASE=/data/letkite-rd08
fail() { echo "rd08: $*" >&2; exit 1; }
plain_path() {
    case "$1" in /*) ;; *) fail 'absolute paths required';; esac
    case "$1" in *'/../'*|*'/./'*|*/..|*/.|*'//'*) fail 'noncanonical path';; esac
    walk=$1
    while [ "$walk" != / ]; do
        [ ! -L "$walk" ] || fail "symlink: $walk"
        walk=${walk%/*}; [ -n "$walk" ] || walk=/
    done
}
fingerprint() {
    for f in etc/openwrt_release usr/share/xiaoqiang/xiaoqiang_version proc/sys/kernel/osrelease proc/cpuinfo tmp/sysinfo/board_name; do
        plain_path "${ROOT%/}/$f"
        [ -f "${ROOT%/}/$f" ] || fail "missing fingerprint: $f"
    done
    release=${ROOT%/}/etc/openwrt_release
    for pair in "DISTRIB_ID='OpenWrt'" "DISTRIB_RELEASE='18.06-SNAPSHOT'" "DISTRIB_TARGET='ipq53xx/generic'" "DISTRIB_ARCH='aarch64_cortex-a53_neon-vfpv4'"; do
        key=${pair%%=*}
        [ "$(grep -c "^$key=" "$release")" = 1 ] || fail 'ambiguous release'
        grep -Fx "$pair" "$release" >/dev/null || fail 'OEM release mismatch'
    done
    version=${ROOT%/}/usr/share/xiaoqiang/xiaoqiang_version
    [ "$(grep -Ec "^[[:space:]]*option ROM " "$version")" = 1 ] || fail 'ambiguous ROM'
    grep -Eq "^[[:space:]]*option ROM '1[.]1[.](96|123)'[[:space:]]*$" "$version" || fail 'unknown ROM'
    [ "$(grep -Ec "^[[:space:]]*option HARDWARE " "$version")" = 1 ] || fail 'ambiguous hardware'
    grep -Eq "^[[:space:]]*option HARDWARE 'RD08'[[:space:]]*$" "$version" || fail 'wrong hardware'
    [ "$(cat "${ROOT%/}/proc/sys/kernel/osrelease")" = 5.4.213 ] || fail 'wrong kernel'
    grep -Eiq '(^|[^[:alnum:]_])IPQ5332([^[:alnum:]_]|$)' "${ROOT%/}/proc/cpuinfo" || fail 'wrong SoC'
    case "$(cat "${ROOT%/}/tmp/sysinfo/board_name")" in RD08|xiaomi,rd08) ;; *) fail 'unverified board';; esac
}
verify() {
    dir=$1
    plain_path "$dir"
    [ -d "$dir" ] || fail 'missing bundle'
    for f in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
        [ -e "$f" ] || { [ ! -L "$f" ] || fail 'dangling symlink'; continue; }
        [ -f "$f" ] && [ ! -L "$f" ] || fail 'nonregular bundle entry'
        case "${f##*/}" in letkite-agent|mihomo|manifest.json|SHA256SUMS|SIZES) ;; *) fail 'unexpected bundle entry';; esac
    done
    for n in letkite-agent manifest.json SHA256SUMS SIZES; do [ -f "$dir/$n" ] || fail "missing $n"; done
    count=2; [ ! -f "$dir/mihomo" ] || count=3
    # Reject arbitrary checksum paths, duplicate entries and malformed hashes before sha256sum.
    awk -v expected="$count" '
      NF != 2 || length($1) != 64 || $1 ~ /[^0-9a-f]/ {exit 1}
      $2 != "letkite-agent" && $2 != "mihomo" && $2 != "manifest.json" {exit 1}
      seen[$2]++ {exit 1}
      END {if (NR != expected || !seen["letkite-agent"] || !seen["manifest.json"]) exit 1}
    ' "$dir/SHA256SUMS" || fail 'unsafe checksums'
    (cd "$dir" && sha256sum -c SHA256SUMS) || fail 'bundle hash mismatch'
    awk -v expected="$count" '
      NF != 2 || $1 !~ /^[0-9]+$/ || $1 < 1 || $1 > 134217728 {exit 1}
      $2 != "letkite-agent" && $2 != "mihomo" && $2 != "manifest.json" {exit 1}
      seen[$2]++ {exit 1}
      END {if (NR != expected || !seen["letkite-agent"] || !seen["manifest.json"]) exit 1}
    ' "$dir/SIZES" || fail 'unsafe sizes'
    while read -r size name; do
        [ "$(wc -c < "$dir/$name" | tr -d ' ')" = "$size" ] || fail 'size mismatch'
    done < "$dir/SIZES"
    # Verify ARM64 header independently on router; do not execute supplied code.
    for n in letkite-agent mihomo; do
        [ -f "$dir/$n" ] || continue
        magic=$(od -An -tx1 -N7 "$dir/$n" | tr -d ' \n')
        machine=$(od -An -tx1 -j16 -N8 "$dir/$n" | tr -d ' \n')
        [ "$magic" = 7f454c46020101 ] || fail 'not ELF64 little endian'
        case "$machine" in 0200b70001000000|0300b70001000000) ;; *) fail 'not ARM64 ELF';; esac
    done
}
mode=${1:-}; bundle=${2:-}
case "$mode" in --check|--dry-run|--apply|--rollback) ;; *) fail 'usage: router.sh --check|--dry-run|--apply BUNDLE [--snapshot ROOT] OR --rollback';; esac
if [ "$mode" = --rollback ]; then
    [ "$#" = 1 ] || fail 'rollback takes no bundle'
else
    [ "$#" = 2 ] || {
        [ "$#" = 4 ] && [ "$3" = --snapshot ] || fail 'invalid arguments'
        case "$mode" in --check|--dry-run) ROOT=$4;; *) fail 'snapshot is check-only';; esac
        plain_path "$ROOT"
    }
fi
fingerprint
plain_path "$BASE"
if [ "$mode" != --rollback ]; then verify "$bundle"; fi
case "$mode" in --check|--dry-run) echo 'Verified without writes; ABI and hardware operation untested; activation manual.'; exit 0;; esac
[ "$(id -u)" = 0 ] || fail 'root required for application storage only'
[ -d /data ] || fail 'missing OEM /data mount'
awk '$2 == "/data" && $4 ~ /(^|,)rw(,|$)/ {ok=1} END {exit !ok}' /proc/mounts || fail '/data is not a writable mount'
mkdir -p "$BASE"
mkdir "$BASE/lock" 2>/dev/null || fail 'installer locked; inspect interrupted transaction manually'
trap 'rmdir "$BASE/lock"' EXIT HUP INT TERM
if [ "$mode" = --rollback ]; then
    verify "$BASE/current"; verify "$BASE/previous"
    [ ! -e "$BASE/staged" ] || fail 'interrupted transaction requires manual review'
    mv "$BASE/current" "$BASE/staged"
    mv "$BASE/previous" "$BASE/current" || { mv "$BASE/staged" "$BASE/current"; fail 'rollback failed'; }
    mv "$BASE/staged" "$BASE/previous"
    echo 'Rolled back application files only; no process was started or stopped.'
    exit 0
fi
[ ! -e "$BASE/staged" ] || fail 'interrupted transaction requires manual review'
if [ -e "$BASE/current" ]; then
    verify "$BASE/current"
    if cmp -s "$bundle/SHA256SUMS" "$BASE/current/SHA256SUMS"; then echo 'Already installed; no payload change.'; exit 0; fi
fi
[ ! -e "$BASE/previous" ] || fail 'previous backup retained; archive it manually before another update'
# Reserve twice the staged payload plus 1 MiB; backup is a rename, never a vendor copy.
need=$(du -sk "$bundle" | awk '{print $1 * 2 + 1024}')
free=$(df -Pk "$BASE" | awk 'END {print $4}')
[ "$free" -ge "$need" ] || fail 'insufficient space'
mkdir "$BASE/staged"
for n in letkite-agent mihomo manifest.json SHA256SUMS SIZES; do
    [ ! -f "$bundle/$n" ] || cp "$bundle/$n" "$BASE/staged/$n"
done
chmod 700 "$BASE/staged/letkite-agent"
[ ! -f "$BASE/staged/mihomo" ] || chmod 600 "$BASE/staged/mihomo"
verify "$BASE/staged"
[ ! -d "$BASE/current" ] || mv "$BASE/current" "$BASE/previous"
if ! mv "$BASE/staged" "$BASE/current"; then
    [ ! -d "$BASE/previous" ] || mv "$BASE/previous" "$BASE/current"
    fail 'activation rename failed'
fi
echo 'Staged only. Review /data/letkite-rd08/current; manual activation and pairing required.'
