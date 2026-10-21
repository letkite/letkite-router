#!/usr/bin/env bash
# scripts/release-table.py, which pins agent releases, against a local
# server and a throwaway Ed25519 release key made here: it writes the table
# for a release that verifies, and refuses one that does not.
# Needs python3 and openssl 3.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
# shellcheck source=tests/unit/lib.sh
. "$here/lib.sh"

work=$(mktemp -d)
server=""
trap '[ -z "$server" ] || kill "$server" 2>/dev/null; rm -rf "$work"' EXIT

openssl genpkey -algorithm ed25519 -out "$work/key.pem" 2>/dev/null
openssl genpkey -algorithm ed25519 -out "$work/other.pem" 2>/dev/null
raw_pub() { openssl pkey -in "$1" -pubout -outform DER | tail -c 32 | base64; }
printf '# test\n%s\n' "$(raw_pub "$work/other.pem")" > "$work/keys"
printf '%s\n' "$(raw_pub "$work/key.pem")" >> "$work/keys"

# release VERSION [KEY]: a release of fake programs, signed with KEY
release() {
	local v=$1 key=${2:-$work/key.pem} d="$work/www/agent/v$1"
	rm -rf "$d"
	mkdir -p "$d"
	for p in linux-x86_64 linux-arm64 linux-armv7 windows-x86_64.exe; do
		echo "program $p $v" > "$d/letkite-agent-$p"
	done
	(cd "$d" && sha256sum letkite-agent-* > SHA256SUMS)
	python3 - "$d" "$v" > "$d/release.json" <<'PY'
import hashlib, json, os, sys
d, v = sys.argv[1], sys.argv[2]
arts = {}
for f in sorted(os.listdir(d)):
    if f.startswith("letkite-agent-"):
        data = open(os.path.join(d, f), "rb").read()
        arts[f[len("letkite-agent-"):].removesuffix(".exe")] = {
            "file": f, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
print(json.dumps({"product": "letkite-agent", "version": v, "artifacts": arts}, indent=2))
PY
	sign "$d" "$key"
}
sign() { # DIR KEY
	{ printf 'letkite-release-v1\n'; cat "$1/release.json"; } > "$work/msg"
	openssl pkeyutl -sign -inkey "$2" -rawin -in "$work/msg" | base64 -w0 > "$1/release.json.sig"
}

mkdir -p "$work/www/channels"
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 -m http.server -b 127.0.0.1 -d "$work/www" "$port" > /dev/null 2>&1 &
server=$!
for _ in $(seq 1 50); do
	python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:$port/')" 2>/dev/null && break
	sleep 0.1
done

export LETKITE_RELEASE_SITE="http://127.0.0.1:$port"
export LETKITE_RELEASE_KEYS="$work/keys"
export LETKITE_RELEASE_TABLE="$work/release"
rt() { out=$("$repo/scripts/release-table.py" "$@" 2>&1); rc=$?; }

echo "# a signed release"
release 2.0.0
rt write 2.0.0
check_eq "writes the table" 0 "$rc"
check "the version" grep -qx 'AGENT_VERSION=2.0.0' "$work/release"
check "x86_64's hash" grep -qx "AGENT_SHA256_x86_64=$(sha256sum "$work/www/agent/v2.0.0/letkite-agent-linux-x86_64" | cut -d' ' -f1)" "$work/release"
check "armv7's size" grep -qx "AGENT_SIZE_armv7=$(wc -c < "$work/www/agent/v2.0.0/letkite-agent-linux-armv7")" "$work/release"
rt check
check_eq "check agrees" 0 "$rc"
sed -i 's/^AGENT_SIZE_arm64=.*/AGENT_SIZE_arm64=1/' "$work/release"
rt check
check_eq "check notices a table edited by hand" 1 "$rc"

echo "# the channel"
echo '{"version": "2.0.0", "path": "agent/v2.0.0/"}' > "$work/www/channels/stable.json"
rt latest
check_eq "latest" 2.0.0 "$out"
echo '{"version": "2.1.0-rc.1", "path": "agent/v2.1.0-rc.1/"}' > "$work/www/channels/stable.json"
rt latest
check_eq "a pre-release is refused" 1 "$rc"
rt newer 2.10.0 2.9.1
check_eq "2.10.0 is newer than 2.9.1" 0 "$rc"
rt newer 2.0.0 2.0.0
check_eq "2.0.0 is not newer than itself" 1 "$rc"

echo "# refused"
cp "$work/release" "$work/release.before"
openssl genpkey -algorithm ed25519 -out "$work/unknown.pem" 2>/dev/null
release 3.0.0 "$work/unknown.pem"
rt write 3.0.0
check_eq "signed with an unknown key" 1 "$rc"
check_has "says so" "$out" "does not verify"
check "the table is untouched" cmp -s "$work/release" "$work/release.before"

release 3.0.0
echo " " >> "$work/www/agent/v3.0.0/release.json"
rt write 3.0.0
check_eq "release.json changed after signing" 1 "$rc"

release 3.0.0
echo "0000000000000000000000000000000000000000000000000000000000000000  letkite-agent-linux-arm64" > "$work/www/agent/v3.0.0/SHA256SUMS"
rt write 3.0.0
check_eq "SHA256SUMS disagrees" 1 "$rc"
check_has "says so" "$out" "SHA256SUMS does not match"

release 3.0.0
sed -i 's/"product": "letkite-agent"/"product": "letkite-relay"/' "$work/www/agent/v3.0.0/release.json"
sign "$work/www/agent/v3.0.0" "$work/key.pem"
rt write 3.0.0
check_eq "another product" 1 "$rc"

release 3.0.0
sed -i 's/"version": "3.0.0"/"version": "3.0.1"/' "$work/www/agent/v3.0.0/release.json"
sign "$work/www/agent/v3.0.0" "$work/key.pem"
rt write 3.0.0
check_eq "another version" 1 "$rc"

release 3.0.0
python3 - "$work/www/agent/v3.0.0/release.json" <<'PY'
import json, sys
p = sys.argv[1]; m = json.load(open(p)); del m["artifacts"]["linux-armv7"]
open(p, "w").write(json.dumps(m))
PY
sign "$work/www/agent/v3.0.0" "$work/key.pem"
rt write 3.0.0
check_eq "no armv7 program" 1 "$rc"

rt write '3.0.0/../2.0.0'
check_eq "not a version" 1 "$rc"
check "the table is still untouched" cmp -s "$work/release" "$work/release.before"

finish
