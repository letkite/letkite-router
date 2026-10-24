#!/usr/bin/env bash
# The letkite-agent package's pre-install script (packages/letkite-agent:
# files/release, then files/fetch.sh, as the Makefile puts them together)
# against a local server standing in for get.letkite.com, in a scratch root.
# Needs python3, wget or curl, sha256sum.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
# shellcheck source=tests/unit/lib.sh
. "$here/lib.sh"

work=$(mktemp -d)
server=""
trap '[ -z "$server" ] || kill "$server" 2>/dev/null; rm -rf "$work"' EXIT

# the "releases": scripts that say which version they are
mkdir -p "$work/www"
release() { # VERSION ARCH [CONTENT [FILE]]
	mkdir -p "$work/www/v$1"
	printf '#!/bin/sh\necho "letkite-agent %s"\n# %s\n' "$1" "${3:-$2}" > "$work/www/v$1/${4:-letkite-agent-linux-$2}"
}
for a in x86_64 arm64 armv7; do release 1.5.0 $a; done
# the router build (letkite/letkite#530), beside the full one
release 1.5.0 x86_64 "router x86_64" letkite-agent-router-linux-x86_64
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 -m http.server -b 127.0.0.1 -d "$work/www" "$port" > /dev/null 2>&1 &
server=$!
for _ in $(seq 1 50); do
	python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$port/')" 2>/dev/null && break
	sleep 0.1
done

sha() { sha256sum "$1" | awk '{ print $1 }'; }

# preinst [SHA256 for x86_64 [FILE for x86_64]]: the script as the package has it
preinst() {
	local file=${2:-letkite-agent-linux-x86_64}
	{
		echo '#!/bin/sh'
		sed "s/^AGENT_VERSION=.*/AGENT_VERSION=1.5.0/" "$repo/packages/letkite-agent/files/release" \
			| sed "s/^AGENT_FILE_x86_64=.*/AGENT_FILE_x86_64=$file/" \
			| sed "s/^AGENT_FILE_arm64=.*/AGENT_FILE_arm64=letkite-agent-linux-arm64/" \
			| sed "s/^AGENT_FILE_armv7=.*/AGENT_FILE_armv7=letkite-agent-linux-armv7/" \
			| sed "s/^AGENT_SHA256_x86_64=.*/AGENT_SHA256_x86_64=${1:-$(sha "$work/www/v1.5.0/$file")}/" \
			| sed "s/^AGENT_SHA256_arm64=.*/AGENT_SHA256_arm64=$(sha "$work/www/v1.5.0/letkite-agent-linux-arm64")/" \
			| sed "s/^AGENT_SHA256_armv7=.*/AGENT_SHA256_armv7=$(sha "$work/www/v1.5.0/letkite-agent-linux-armv7")/"
		cat "$repo/packages/letkite-agent/files/fetch.sh"
	} > "$work/preinst"
	chmod +x "$work/preinst"
}

# router ARCH [CPU FEATURES]: a fresh root with this DISTRIB_ARCH
router() {
	rm -rf "$work/root"
	mkdir -p "$work/root/etc" "$work/root/proc"
	echo "DISTRIB_ID='OpenWrt'" > "$work/root/etc/openwrt_release"
	[ -z "$1" ] || echo "DISTRIB_ARCH='$1'" >> "$work/root/etc/openwrt_release"
	printf 'processor\t: 0\nFeatures\t: %s\n' "${2:-}" > "$work/root/proc/cpuinfo"
}

run() {
	out=$(LETKITE_PKG_TEST_ROOT="$work/root" LETKITE_PKG_BASE_URL="http://127.0.0.1:$port" "$work/preinst" 2>&1)
	rc=$?
}
installed() { sed -n 's/^# //p' "$work/root/opt/letkite-agent/letkite-agent" 2>/dev/null; }
nothing_left() { [ ! -e "$work/root/opt/letkite-agent" ]; }

echo "# x86_64"
preinst; router x86_64; run
check_eq "installs" 0 "$rc"
check_eq "the x86_64 program" x86_64 "$(installed)"
check_eq "mode 0755" 755 "$(stat -c %a "$work/root/opt/letkite-agent/letkite-agent")"
check "nothing staged left over" [ ! -e "$work/root/opt/letkite-agent/letkite-agent.pkg-new" ]
check_has "says it verified" "$out" "SHA-256 verified"

echo "# a wrong pinned hash"
preinst 0000000000000000000000000000000000000000000000000000000000000000; router x86_64; run
check_eq "fails" 1 "$rc"
check_has "says why" "$out" "does not match the SHA-256 pinned"
check "leaves nothing" nothing_left
preinst

echo "# a program that changed on the server"
release 1.5.0 x86_64 tampered
router x86_64; run
check_eq "fails" 1 "$rc"
check "leaves nothing" nothing_left
release 1.5.0 x86_64; preinst

echo "# aarch64 and armv7"
router aarch64_cortex-a53; run
check_eq "aarch64 installs" 0 "$rc"
check_eq "the arm64 program" arm64 "$(installed)"
router arm_cortex-a7_neon-vfpv4 "half thumb fastmult vfp edsp neon vfpv3 tls vfpv4 idiva idivt vfpd32 lpae evtstrm"; run
check_eq "armv7 with VFPv4 installs" 0 "$rc"
check_eq "the armv7 program" armv7 "$(installed)"
router arm_cortex-a9 "half thumb fastmult edsp tls"; run
check_eq "armv7 without VFP fails" 1 "$rc"
check_has "says it needs VFPv3" "$out" "VFPv3"
check "leaves nothing" nothing_left
router arm_arm1176jzf-s_vfp "half thumb fastmult vfp edsp java tls"; run
check_eq "ARMv6 (VFPv2) fails" 1 "$rc"

echo "# unsupported"
router mipsel_24kc; run
check_eq "mipsel fails" 1 "$rc"
check_has "says MIPS" "$out" "MIPS"
check "leaves nothing" nothing_left
router i386_pentium4; run
check_eq "i386 fails" 1 "$rc"
router ""; run
check_eq "not OpenWrt fails" 1 "$rc"
check_has "says it is for OpenWrt" "$out" "for OpenWrt"

echo "# an agent already there"
keep() { # VERSION: an installed program of this version
	router x86_64
	mkdir -p "$work/root/opt/letkite-agent"
	printf '#!/bin/sh\necho "letkite-agent %s"\n# old %s\n' "$1" "$1" > "$work/root/opt/letkite-agent/letkite-agent"
	chmod 755 "$work/root/opt/letkite-agent/letkite-agent"
}
keep 1.6.0; run
check_eq "a newer one (updated itself): kept" "old 1.6.0" "$(installed)"
check_eq "and that is fine" 0 "$rc"
keep 1.5.0; cp "$work/www/v1.5.0/letkite-agent-linux-x86_64" "$work/root/opt/letkite-agent/letkite-agent"; run
check_eq "the same version, this very program: kept" x86_64 "$(installed)"
check_has "says it keeps it" "$out" "keeping"
keep 1.5.0; run
check_eq "the same version, another program: replaced" x86_64 "$(installed)"
keep 1.4.2; run
check_eq "an older one: replaced" x86_64 "$(installed)"
keep 1.5.0-rc.3; run
check_eq "a pre-release of this version: replaced" x86_64 "$(installed)"
keep 1.10.0; run
check_eq "1.10.0 is newer than 1.5.0" "old 1.10.0" "$(installed)"
keep 1.6.0; preinst 0000000000000000000000000000000000000000000000000000000000000000
release 1.5.0 x86_64; run
check_eq "a newer one is kept even if the table is wrong" "old 1.6.0" "$(installed)"
keep 1.5.0; run
check_eq "a failed update keeps the program there" "old 1.5.0" "$(installed)"
preinst

echo "# the router build (letkite/letkite#530)"
preinst "" letkite-agent-router-linux-x86_64
router x86_64; run
check_eq "installs" 0 "$rc"
check_eq "the router build" "router x86_64" "$(installed)"
keep 1.5.0; cp "$work/www/v1.5.0/letkite-agent-linux-x86_64" "$work/root/opt/letkite-agent/letkite-agent"; run
check_eq "the full build of the same version: replaced by the router build" "router x86_64" "$(installed)"
run
check_eq "the router build of the same version: kept" "router x86_64" "$(installed)"
check_has "says it keeps it" "$out" "keeping"
keep 1.6.0; run
check_eq "a newer one (updated itself): kept" "old 1.6.0" "$(installed)"
preinst "" letkite-agent-linux-arm64; router x86_64; run
check_eq "another architecture's file fails" 1 "$rc"
check_has "says so" "$out" "unexpected program"
check "leaves nothing" nothing_left
preinst

echo "# the download fails"
router x86_64
mv "$work/www/v1.5.0" "$work/www/gone"; run; mv "$work/www/gone" "$work/www/v1.5.0"
check_eq "fails" 1 "$rc"
check_has "says it cannot download" "$out" "cannot download"
check "leaves nothing" nothing_left

echo "# building a firmware image"
router x86_64
out=$(IPKG_INSTROOT="$work/root" LETKITE_PKG_TEST_ROOT="$work/root" LETKITE_PKG_BASE_URL="http://127.0.0.1:$port" "$work/preinst" 2>&1); rc=$?
check_eq "does nothing" 0 "$rc"
check "downloads nothing" nothing_left

echo "# the real table"
# shellcheck source=packages/letkite-agent/files/release
. "$repo/packages/letkite-agent/files/release"
check "a version" [ -n "$AGENT_VERSION" ]
for a in x86_64 arm64 armv7; do
	h="" s="" f=""
	eval "h=\$AGENT_SHA256_$a s=\$AGENT_SIZE_$a f=\$AGENT_FILE_$a"
	check "$a: a file" grep -qxE "letkite-agent-(router-)?linux-$a" <<<"$f"
	check "$a: a SHA-256" grep -qxE '[0-9a-f]{64}' <<<"$h"
	check "$a: a size" grep -qxE '[0-9]+' <<<"$s"
done

finish
