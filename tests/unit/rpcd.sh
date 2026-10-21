#!/bin/sh
# The rpcd plugin (/usr/libexec/rpcd/letkite) against the fake agent
# (tests/fake-agent). Needs what an OpenWrt router has: BusyBox, jshn and
# jsonfilter; tests/unit/run.sh runs it in OpenWrt's rootfs container.
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
# shellcheck source=tests/unit/lib.sh
. "$here/lib.sh"

plugin="$repo/packages/luci-app-letkite/root/usr/libexec/rpcd/letkite"
work=$(mktemp -d)
trap 'pkill -f "$work" 2>/dev/null; rm -rf "$work"' EXIT

export FAKE_AGENT_STATE="$work/agent"
export LETKITE_AGENT="$repo/tests/fake-agent/letkite-agent"
export LETKITE_RUN_DIR="$work/run"
export LETKITE_CONFIG_DIR="$work/etc"
export LETKITE_LOGREAD="$work/logread"
mkdir -p "$FAKE_AGENT_STATE" "$LETKITE_CONFIG_DIR"
cat > "$LETKITE_LOGREAD" <<'L'
#!/bin/sh
# logread -e letkite: three lines, one with characters JSON escapes
[ "$1 $2" = "-e letkite" ] || exit 1
echo 'Oct 21 10:00:00 letkite-agent[1]: started'
echo 'Oct 21 10:00:01 letkite-agent[1]: "quoted" \ back	tab'
echo 'Oct 21 10:00:02 letkite-agent[1]: reconnecting in 5 s'
L
chmod +x "$LETKITE_LOGREAD"

call() { # METHOD [JSON]
	printf '%s' "${2:-}" | "$plugin" call "$1"
}
field() { # JSON EXPR
	jsonfilter -s "$1" -e "$2" 2>/dev/null
}
calls() { cat "$FAKE_AGENT_STATE/calls" 2>/dev/null; }
reset_calls() { : > "$FAKE_AGENT_STATE/calls"; }
valid() { [ "$(jsonfilter -s "$1" -t '@' 2>/dev/null)" = object ]; }

echo "# list"
out=$("$plugin" list)
check "list is a JSON object" valid "$out"
for m in status enroll_start enroll_poll pause resume ceiling_get ceiling_set log; do
	check "list has $m" [ "$(jsonfilter -s "$out" -t "@.$m")" = object ]
done
check_eq "list has nothing else" 8 "$(jsonfilter -s "$out" -e '@.*' | wc -l | tr -d ' ')"

echo "# status"
out=$(call status)
check "status is JSON" valid "$out"
check_eq "status: cli" true "$(field "$out" '@.cli')"
check_eq "status: agent version" 9.9.9 "$(field "$out" '@.agent.version')"
check_eq "status: not enrolled" false "$(field "$out" '@.agent.enrolled')"
check_eq "status: paused_until null passes through" "" "$(field "$out" '@.agent.paused_until')"
check_eq "status: argv" "status|--json" "$(calls | tail -n 1)"

echo "# status, an agent without status --json"
out=$(FAKE_FAIL=status call status)
check "fallback is JSON" valid "$out"
check_eq "fallback: cli false" false "$(field "$out" '@.cli')"
check_eq "fallback: version from --version" 9.9.9 "$(field "$out" '@.agent.version')"
check_eq "fallback: enrolled from agent.toml" false "$(field "$out" '@.agent.enrolled')"

echo "# status, no agent"
out=$(LETKITE_AGENT=/nonexistent call status)
check_eq "no agent: installed false" false "$(field "$out" '@.installed')"

echo "# pause and resume"
reset_calls
out=$(call pause '{"duration":"30m"}')
check_eq "pause 30m: ok" true "$(field "$out" '@.ok')"
check_eq "pause 30m: argv" "pause|--for|30m" "$(calls)"
reset_calls
out=$(call pause '{}')
check_eq "pause: ok" true "$(field "$out" '@.ok')"
check_eq "pause until resumed: argv" "pause" "$(calls)"
# shellcheck disable=SC2016 # literally, as an attacker would send them
for bad in '1h;reboot' '$(reboot)' '1 h' '1hh' 'h' '99999m' '-1h' '1h\nreboot' '1s'; do
	reset_calls
	out=$(call pause "{\"duration\":\"$bad\"}")
	check_eq "pause refuses \"$bad\"" false "$(field "$out" '@.ok')"
	check_eq "pause \"$bad\" runs nothing" "" "$(calls)"
done
reset_calls
out=$(call pause '{"duration":42}')
check_eq "pause refuses a number" false "$(field "$out" '@.ok')"
reset_calls
out=$(call resume)
check_eq "resume: ok" true "$(field "$out" '@.ok')"
check_eq "resume: argv" "resume" "$(calls)"
out=$(FAKE_FAIL=resume call resume)
check_eq "a failing command: ok false" false "$(field "$out" '@.ok')"
check_has "a failing command: its error" "$(field "$out" '@.error')" "resume failed"

echo "# ceiling"
out=$(call ceiling_get)
check "ceiling_get is JSON" valid "$out"
check_eq "ceiling_get: supported" true "$(field "$out" '@.supported')"
check_eq "ceiling_get: exec" true "$(field "$out" '@.ceiling.exec')"
check_has "ceiling_get: the switches LuCI may set" "$(field "$out" '@.switches')" terminal
reset_calls
out=$(call ceiling_set '{"switch":"exec","value":false}')
check_eq "ceiling_set exec false: ok" true "$(field "$out" '@.ok')"
check_eq "ceiling_set: argv" "ceiling|set|exec|false" "$(calls)"
check_eq "ceiling_set took effect" false "$(field "$(call ceiling_get)" '@.ceiling.exec')"
reset_calls
out=$(call ceiling_set '{"switch":"mesh","value":true}')
check_eq "ceiling_set mesh true: argv" "ceiling|set|mesh|true" "$(calls)"
for bad in '{"switch":"gui","value":true}' '{"switch":"exec files","value":true}' \
	'{"switch":"exec;reboot","value":true}' '{"switch":"exec","value":"yes"}' \
	'{"switch":"exec","value":1}' '{"switch":"exec"}' '{"value":true}' 'not json'; do
	reset_calls
	out=$(call ceiling_set "$bad")
	check_eq "ceiling_set refuses $bad" false "$(field "$out" '@.ok')"
	check_eq "ceiling_set $bad runs nothing" "" "$(calls)"
done
out=$(FAKE_FAIL=ceiling call ceiling_get)
check_eq "ceiling_get, an agent without it: unsupported" false "$(field "$out" '@.supported')"

echo "# log"
out=$(call log '{"lines":2}')
check "log is JSON" valid "$out"
check_eq "log: the last 2 lines" 2 "$(jsonfilter -s "$out" -e '@.lines[*]' | wc -l | tr -d ' ')"
check_eq "log: escaped and back" 'Oct 21 10:00:01 letkite-agent[1]: "quoted" \ back	tab' "$(field "$out" '@.lines[0]')"
out=$(call log)
check_eq "log: all 3 by default" 3 "$(jsonfilter -s "$out" -e '@.lines[*]' | wc -l | tr -d ' ')"
for bad in 0 1001 '"10;reboot"' '"-5"' '"1e3"'; do
	out=$(call log "{\"lines\":$bad}")
	check_eq "log refuses $bad" false "$(field "$out" '@.ok')"
done

echo "# enrolling"
out=$(call enroll_poll)
check_eq "nothing started: idle" idle "$(field "$out" '@.state')"
reset_calls
export FAKE_ENROLL=wait
out=$(call enroll_start '{"name":"my-router"}')
check_eq "enroll_start: ok" true "$(field "$out" '@.ok')"
i=0
while [ $i -lt 20 ]; do
	out=$(call enroll_poll)
	[ "$(field "$out" '@.state')" = code ] && break
	i=$((i + 1)); sleep 1
done
check_eq "the code shows" code "$(field "$out" '@.state')"
check_eq "the user code" ABCD-EFGH "$(field "$out" '@.code.user_code')"
check_eq "the link" "https://id.example/activate?code=ABCD-EFGH" "$(field "$out" '@.code.verification_uri_complete')"
check_eq "expires_in" 600 "$(field "$out" '@.code.expires_in')"
check_eq "running while waiting" true "$(field "$out" '@.running')"
check_eq "status: enrolling" true "$(field "$(call status)" '@.enrolling')"
check_eq "enroll argv" "enroll|--no-browser|--json|--name|my-router" "$(grep '^enroll' "$FAKE_AGENT_STATE/calls")"
touch "$FAKE_AGENT_STATE/approve"
i=0
while [ $i -lt 20 ]; do
	out=$(call enroll_poll)
	[ "$(field "$out" '@.running')" = false ] && break
	i=$((i + 1)); sleep 1
done
check_eq "approved: enrolled" enrolled "$(field "$out" '@.state')"
check_eq "the node" n_fake "$(field "$out" '@.node_id')"
check_eq "the name" my-router "$(field "$out" '@.name')"
check_eq "the service is installed after enrolling" true "$(field "$out" '@.service_installed')"
check "install ran after enroll" grep -qx install "$FAKE_AGENT_STATE/calls"
rm -f "$FAKE_AGENT_STATE/approve"

FAKE_ENROLL=error call enroll_start '{}' > /dev/null
i=0
while [ $i -lt 20 ]; do
	out=$(call enroll_poll)
	[ "$(field "$out" '@.running')" = false ] && break
	i=$((i + 1)); sleep 1
done
check_eq "a failed enrollment: error" error "$(field "$out" '@.state')"
check_eq "its message" "the code expired" "$(field "$out" '@.error.message')"
check_eq "no service install after a failure" "" "$(field "$out" '@.service_installed')"

reset_calls
# shellcheck disable=SC2016
for bad in '{"name":"a b"}' '{"name":"$(reboot)"}' '{"name":"-x"}' '{"name":"x;y"}' "{\"name\":\"$(printf 'a%.0s' $(seq 1 64))\"}"; do
	out=$(call enroll_start "$bad")
	check_eq "enroll_start refuses $bad" false "$(field "$out" '@.ok')"
done
check_eq "nothing ran for bad names" "" "$(calls)"

echo "# unknown"
out=$(call reboot)
check_eq "an unknown method" false "$(field "$out" '@.ok')"

finish
