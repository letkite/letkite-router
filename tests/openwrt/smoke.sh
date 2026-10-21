#!/usr/bin/env bash
# The packages on a real OpenWrt, in QEMU: installed from a signed feed the
# way a router owner would, with the real agent release pinned in this
# repository downloaded from get.letkite.com.
#
#   tests/openwrt/smoke.sh VERSION FEED KEY [TAMPERED_FEED]
#
# VERSION is an OpenWrt release (24.10.x: .ipk and opkg; 25.12.x: .apk and
# apk). FEED is a directory of built packages with a signed index
# (scripts/sdk-build.sh), KEY the public key that index is signed with (a
# usign key for 24.10, a PEM key for 25.12). TAMPERED_FEED, if given, is a
# feed whose letkite-agent pins a wrong SHA-256: installing it must fail and
# leave nothing behind.
#
# 1. Not paired: the package downloads and verifies the agent, the LuCI app
#    answers on ubus and over HTTP (with the LuCI login's ACL), the view is
#    served. The agent's service is registered if the agent can install it
#    before pairing; older agents install it once paired.
# 2. Paired (a made-up enrollment whose gateway does not answer; nothing
#    here is a secret): installing again registers the procd service through
#    the agent's own `install`, and it runs.
# 3. Uninstalled: no service, no program, no rpcd object; /etc/letkite stays.
#
# Needs what vm.sh needs, and python3. A VM of its own, stopped at the end.
# shellcheck disable=SC2016 # commands for the VM, single-quoted on purpose
set -euo pipefail

version=${1:?usage: smoke.sh VERSION FEED KEY [TAMPERED_FEED]}
feed=$(cd "${2:?FEED}" && pwd)
key=${3:?KEY}
tampered=${4:-}
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
vm="$here/vm.sh"
name="lk-smoke-$$"
started=$SECONDS
www=$(mktemp -d)
server=""

die() { echo "smoke.sh: FAILED: $*" >&2; exit 1; }
on() { "$vm" ssh "$name" "$@"; }
step() { echo "== $* ($((SECONDS - started))s)"; }

cleanup() {
  local status=$?
  if ((status != 0)); then
    echo "-- logread --"
    on 'logread | tail -n 40' 2>/dev/null || true
  fi
  [[ -z $server ]] || kill "$server" 2>/dev/null || true
  "$vm" stop "$name" > /dev/null 2>&1 || true
  rm -rf "${OPENWRT_VMS:-$HOME/.local/state/letkite-openwrt}/$name" "$www"
}
trap cleanup EXIT

# the pinned release
# shellcheck source=packages/letkite-agent/files/release
. "$repo/packages/letkite-agent/files/release"

case "$version" in
  24.10.*) pm=opkg ;;
  25.12.*) pm=apk ;;
  *) die "OpenWrt 24.10.x or 25.12.x, not $version" ;;
esac

# The feeds, served to the VM: QEMU's user network shows this machine's
# 127.0.0.1 to it as 192.168.1.2.
ln -s "$feed" "$www/feed"
[[ -z $tampered ]] || ln -s "$(cd "$tampered" && pwd)" "$www/tampered"
port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
python3 -m http.server -b 127.0.0.1 -d "$www" "$port" > /dev/null 2>&1 &
server=$!
url="http://192.168.1.2:$port"

step "start OpenWrt $version"
"$vm" start x86_64 "$version" "$name"

# use_feed DIR: the package manager reads our feed DIR (and OpenWrt's own,
# which the network may drop now and then: three tries)
use_feed() {
  local update
  if [[ $pm == opkg ]]; then
    on "sed -i '/letkite/d' /etc/opkg/customfeeds.conf && echo 'src/gz letkite $url/$1' >> /etc/opkg/customfeeds.conf"
    update='opkg update > /tmp/update.log 2>&1'
  else
    on "echo '$url/$1/packages.adb' > /etc/apk/repositories.d/letkite.list"
    update='apk update > /tmp/update.log 2>&1'
  fi
  for try in 1 2 3; do
    on "$update" && return
    on 'tail -n 20 /tmp/update.log'
    ((try < 3)) && sleep 10
  done
  die "$pm update failed three times"
}
pkg_install() {
  if [[ $pm == opkg ]]; then on "opkg install $*"; else on "apk add $*"; fi
}
# uninstall, as the README says: the agent and what depends on it
uninstall_all() {
  if [[ $pm == opkg ]]; then
    on 'opkg remove --force-removal-of-dependent-packages letkite-agent'
  else
    on 'apk del -r letkite-agent'
  fi
}
installed() {
  if [[ $pm == opkg ]]; then on "opkg list-installed | grep -q '^$1 '"; else on "apk info -e $1 > /dev/null"; fi
}

step "trust the test feed's key"
if [[ $pm == opkg ]]; then
  "$vm" put "$name" "$key" /tmp/feed.pub
  on 'opkg-key add /tmp/feed.pub'
else
  "$vm" put "$name" "$key" /etc/apk/keys/letkite-test.pem
fi

nothing_installed() {
  ! installed letkite-agent \
    && on 'test ! -e /opt/letkite-agent && test ! -e /etc/init.d/letkite-agent && test ! -e /usr/bin/letkite-agent'
}

if [[ -n $tampered ]]; then
  step "a package that pins a wrong SHA-256"
  use_feed tampered
  if out=$(pkg_install letkite-agent 2>&1); then
    echo "$out"
    die "letkite-agent installed although the program does not match its pinned SHA-256"
  fi
  echo "$out" | tail -n 5
  grep -q "does not match the SHA-256 pinned" <<<"$out" || die "no word of the mismatch"
  on 'test ! -e /opt/letkite-agent && test ! -e /etc/init.d/letkite-agent && test ! -e /usr/bin/letkite-agent' \
    || die "the failed install left the program or a service behind"
  if [[ $pm == apk ]]; then
    # apk-tools goes on after a failed pre-install script and records the
    # package (with a script error); it holds nothing but its table, and
    # removing it leaves nothing
    grep -q "pre-install: exited with error" <<<"$out" || die "apk did not report the failed pre-install"
    uninstall_all
  fi
  nothing_installed || die "the failed install left something behind"
fi

step "install from the signed feed"
use_feed feed
out=$(pkg_install luci-app-letkite luci-i18n-letkite-zh-cn 2>&1) || { echo "$out"; die "install"; }
echo "$out" | grep -i letkite || true
grep -q "SHA-256 verified" <<<"$out" || die "the package did not say it verified the program"

step "the program is the pinned release"
got=$(on 'sha256sum /opt/letkite-agent/letkite-agent' | awk '{ print $1 }')
[[ $got == "$AGENT_SHA256_x86_64" ]] || die "/opt/letkite-agent/letkite-agent is $got, not the pinned $AGENT_SHA256_x86_64"
on 'ls -l /opt/letkite-agent/letkite-agent' | grep -q '^-rwxr-xr-x ' || die "not mode 0755"
on '/opt/letkite-agent/letkite-agent --version' | grep -qx "letkite-agent $AGENT_VERSION" || die "not version $AGENT_VERSION"
on 'test "$(readlink /usr/bin/letkite-agent)" = /opt/letkite-agent/letkite-agent' || die "no /usr/bin/letkite-agent"

step "the package does not own the program (the agent replaces it when it updates)"
if [[ $pm == opkg ]]; then
  on 'opkg files letkite-agent' | grep -q /opt/letkite-agent && die "letkite-agent owns /opt/letkite-agent"
else
  on 'apk info -L letkite-agent' | grep -q opt/letkite-agent && die "letkite-agent owns /opt/letkite-agent"
  on 'apk audit letkite-agent luci-app-letkite' | grep . && die "apk audit reports changes"
fi

full_cli=""
on '/opt/letkite-agent/letkite-agent status --json > /dev/null 2>&1' && full_cli=1

service_pid() {
  on 'ubus call service list "{\"name\":\"letkite-agent\"}"' \
    | sed -n 's/.*"pid": *\([0-9]*\).*/\1/p' | head -1
}

step "ubus call letkite status"
st=$(on 'ubus call letkite status')
echo "$st"
on "jsonfilter -s '$st' -e @.installed" | grep -qx true || die "status: not installed"
on "jsonfilter -s '$st' -e @.agent.version" | grep -qx "$AGENT_VERSION" || die "status: not version $AGENT_VERSION"
on "jsonfilter -s '$st' -e @.agent.enrolled" | grep -qx false || die "status: enrolled already"
if [[ -n $full_cli ]]; then
  on 'test -x /etc/init.d/letkite-agent' || die "this agent can install its service before pairing, but there is none"
else
  echo "(agent $AGENT_VERSION installs its service once paired: the package says so)"
  grep -q "not paired yet" <<<"$out" || die "the package did not say how to pair"
fi

step "LuCI: the view, the menu, the ACL"
on 'uclient-fetch -q -O /dev/null http://127.0.0.1/luci-static/resources/view/letkite/overview.js' \
  || die "uhttpd does not serve view/letkite/overview.js"
on 'uclient-fetch -q -O /dev/null http://127.0.0.1/luci-static/resources/letkite/qrcode.js' \
  || die "uhttpd does not serve letkite/qrcode.js"
on 'test -s /usr/lib/lua/luci/i18n/letkite.zh-cn.lmo' || die "no Chinese translation"
# LuCI's own login, as a browser does it, from this machine through a
# forwarded port: root has no password on a fresh image
web=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
"$vm" forward "$name" "$web"
jar="$www/cookies"
code=$(curl -s -o /dev/null -w '%{http_code}' -c "$jar" --data 'luci_username=root&luci_password=' \
  "http://127.0.0.1:$web/cgi-bin/luci/")
[[ $code == 302 || $code == 200 ]] || die "LuCI login answered $code"
code=$(curl -s -o "$www/page.html" -w '%{http_code}' -b "$jar" "http://127.0.0.1:$web/cgi-bin/luci/admin/services/letkite/overview")
[[ $code == 200 ]] || die "Services > LetKite answered $code"
grep -q "letkite/overview" "$www/page.html" || die "the LuCI page does not load the LetKite view"
sid=$(awk '$6 ~ /^sysauth/ { print $7 }' "$jar" | head -1)
[[ -n $sid ]] || die "no LuCI session cookie"
rpc() { # SESSION METHOD
  curl -s --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"call\",\"params\":[\"$1\",\"letkite\",\"$2\",{}]}" \
    "http://127.0.0.1:$web/ubus"
}
reply=$(rpc "$sid" status)
grep -q "\"version\": *\"$AGENT_VERSION\"" <<<"$reply" || die "the LuCI session cannot call letkite status: $reply"
reply=$(rpc 00000000000000000000000000000000 status)
grep -q '"error"' <<<"$reply" || die "an anonymous session called letkite status: $reply"
reply=$(rpc 00000000000000000000000000000000 pause)
grep -q '"error"' <<<"$reply" || die "an anonymous session called letkite pause: $reply"

step "remove (not paired)"
uninstall_all
on 'test ! -e /usr/lib/lua/luci/i18n/letkite.zh-cn.lmo' || die "the translation is still there"
nothing_installed || die "removing left something behind"
on 'ubus list letkite' > /dev/null 2>&1 && die "the rpcd object letkite is still there"

step "paired: install again"
# A node that was enrolled: a fresh key, made here (BusyBox has no base64),
# and a gateway nobody listens on.
nodekey=$(head -c 32 /dev/urandom | base64)
pinned=$(head -c 32 /dev/urandom | base64)
on "mkdir -p /etc/letkite && chmod 700 /etc/letkite \
  && umask 077 && echo '$nodekey' > /etc/letkite/node.key \
  && printf '%s\n' 'node_id = \"n_smoke\"' \
       'connect_url = \"wss://127.0.0.1:9/v1/connect\"' \
       'gateway_keys = [\"$pinned\"]' > /etc/letkite/agent.toml"
pkg_install luci-app-letkite

step "the agent's procd service"
on 'test -x /etc/init.d/letkite-agent && test -L /etc/rc.d/S99letkite-agent \
  && test -f /lib/upgrade/keep.d/letkite-agent' || die "the agent did not install its service"
on 'grep -q "command /opt/letkite-agent/letkite-agent" /etc/init.d/letkite-agent' \
  || die "the service does not run /opt/letkite-agent/letkite-agent"
first=""
for _ in $(seq 1 20); do
  first=$(service_pid)
  [[ -n $first ]] && break
  sleep 1
done
[[ -n $first ]] || die "procd does not run letkite-agent"
sleep 5
[[ "$(service_pid)" == "$first" ]] || die "letkite-agent does not stay up"
st=$(on 'ubus call letkite status')
on "jsonfilter -s '$st' -e @.agent.enrolled" | grep -qx true || die "status: not enrolled: $st"
on "jsonfilter -s '$st' -e @.agent.service_running" | grep -qx true || die "status: service not running: $st"
on 'ubus call letkite log "{\"lines\":5}"' | grep -q letkite || die "letkite log shows nothing"

step "uninstall"
uninstall_all
nothing_installed || die "uninstall left the program or the service behind"
on 'test ! -e /etc/rc.d/S99letkite-agent && test ! -e /lib/upgrade/keep.d/letkite-agent' \
  || die "uninstall left the service's links or keep list"
[[ -z "$(service_pid)" ]] || die "letkite-agent still runs after uninstall"
on 'test -f /etc/letkite/agent.toml' || die "uninstall removed /etc/letkite (it should stay)"

step "passed"
