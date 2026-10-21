# The package's pre-install script, after the release table above: download
# the LetKite agent for this router from get.letkite.com and check it against
# the SHA-256 pinned in the table. The feed's signature covers this script and
# the table, so what runs is what the feed's key vouches for:
# feed signature -> package -> pinned SHA-256.
#
# The program goes to /opt/letkite-agent/letkite-agent, where the agent's own
# `install` sets up its procd service (post-install). The package does not
# own that file: the agent replaces it when it updates itself.
#
# If this fails, nothing is left behind and the install fails: opkg stops
# there; apk-tools records the package with a script error (post-install
# then says to remove it).
# Only POSIX sh and what BusyBox has.

# building a firmware image (Image Builder, IPKG_INSTROOT set): there is no
# network and no router to run on; nothing to download
[ -n "${IPKG_INSTROOT:-}" ] && exit 0

# Tests only: a root to work in, and a server standing in for
# get.letkite.com. Neither can change what is installed: the hash is pinned.
root="${LETKITE_PKG_TEST_ROOT:-}"
base="${LETKITE_PKG_BASE_URL:-https://get.letkite.com/agent}"

dir="$root/opt/letkite-agent"
target="$dir/letkite-agent"
staged="$dir/letkite-agent.pkg-new"
made_dir=""

fail() {
	rm -f "$staged"
	[ -z "$made_dir" ] || rmdir "$dir" 2>/dev/null
	echo "letkite-agent: $*" >&2
	exit 1
}

# A is B or newer: X.Y.Z, and a pre-release (X.Y.Z-rc.1) comes before X.Y.Z
version_ge() {
	awk -v a="$1" -v b="$2" '
		function parse(v, out,   n, core, c) {
			n = index(v, "-")
			out["pre"] = n ? substr(v, n + 1) : ""
			core = n ? substr(v, 1, n - 1) : v
			split(core, c, ".")
			out[1] = c[1] + 0; out[2] = c[2] + 0; out[3] = c[3] + 0
		}
		BEGIN {
			parse(a, x); parse(b, y)
			for (i = 1; i <= 3; i++) {
				if (x[i] > y[i]) exit 0
				if (x[i] < y[i]) exit 1
			}
			if (x["pre"] == y["pre"] || x["pre"] == "") exit 0
			if (y["pre"] == "") exit 1
			exit (x["pre"] >= y["pre"]) ? 0 : 1
		}'
}

fetch() { # URL FILE
	if command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -q -T 60 -O "$2" "$1"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -T 60 -O "$2" "$1"
	elif command -v curl >/dev/null 2>&1; then
		curl -fsSL --max-time 600 -o "$2" "$1"
	else
		echo "letkite-agent: needs uclient-fetch, wget or curl" >&2
		return 1
	fi
}

# OpenWrt's package architecture says which program runs here. The agent is
# built for x86_64, aarch64 and ARMv7 with a VFPv3 floating-point unit
# (armv7-unknown-linux-musleabihf, statically linked).
distrib_arch=$(
	DISTRIB_ARCH=""
	# shellcheck disable=SC1091
	. "$root/etc/openwrt_release" 2>/dev/null
	echo "$DISTRIB_ARCH"
)
case "$distrib_arch" in
	x86_64) arch=x86_64 ;;
	aarch64_*) arch=arm64 ;;
	arm_*)
		grep -qE '^(Features|flags)[[:space:]]*:.* (vfpv3|vfpv4)( |$)' "$root/proc/cpuinfo" 2>/dev/null \
			|| fail "this router's CPU ($distrib_arch) has no VFPv3 floating-point unit; the LetKite agent needs ARMv7 with VFPv3 (or x86_64, aarch64)"
		arch=armv7 ;;
	mips*)
		fail "there is no LetKite agent for MIPS routers ($distrib_arch) yet; supported: x86_64, aarch64, ARMv7 with VFPv3" ;;
	"")
		fail "cannot read DISTRIB_ARCH from /etc/openwrt_release; this package is for OpenWrt" ;;
	*)
		fail "there is no LetKite agent for $distrib_arch; supported: x86_64, aarch64, ARMv7 with VFPv3" ;;
esac

eval "want=\${AGENT_SHA256_$arch:-}"
eval "size=\${AGENT_SIZE_$arch:-0}"
# shellcheck disable=SC2154 # set by the eval above
[ -n "$want" ] || fail "this package lists no program for $arch"
file="letkite-agent-linux-$arch"

# An agent that updated itself since is newer than this table; keep it.
if [ -x "$target" ]; then
	have=$("$target" --version 2>/dev/null | awk '{ print $2 }')
	if [ -n "$have" ] && version_ge "$have" "$AGENT_VERSION"; then
		echo "letkite-agent: keeping $target ($have; this package has $AGENT_VERSION)"
		exit 0
	fi
fi

if [ ! -d "$dir" ]; then
	mkdir -p "$dir" || fail "cannot create $dir"
	made_dir=1
fi
chmod 0755 "$dir"

# a router's flash is small: room for the program twice (an update writes the
# new one beside the old), and a megabyte to spare
# shellcheck disable=SC2154 # set by the eval above
need=$((size * 2 / 1024 + 1024))
free=$(df -Pk "$dir" | awk 'NR == 2 { print $4 }')
[ "${free:-0}" -ge "$need" ] || fail "$dir has ${free:-0} KB free; the LetKite agent needs $need KB"

url="$base/v$AGENT_VERSION/$file"
echo "letkite-agent: downloading $url"
rm -f "$staged"
fetch "$url" "$staged" || fail "cannot download $url; check that this router reaches get.letkite.com"
got=$(sha256sum "$staged" | awk '{ print $1 }')
[ "$got" = "$want" ] || fail "$file does not match the SHA-256 pinned in this package (expected $want, got $got); not installing it"
chmod 0755 "$staged"
"$staged" --version >/dev/null 2>&1 || fail "$file does not run on this router"
mv -f "$staged" "$target" || fail "cannot write $target"
echo "letkite-agent: installed $target ($AGENT_VERSION, SHA-256 verified)"
