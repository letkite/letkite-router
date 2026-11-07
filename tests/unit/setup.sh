#!/bin/sh
# Run the real setup/banner/defaults scripts with only absolute paths rooted
# in a private directory. No service, host UCI or network is touched.
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
# shellcheck source=tests/unit/lib.sh
. "$here/lib.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/etc/init.d" "$work/opt/letkite-agent" "$work/etc/letkite" "$work/usr/bin" "$work/usr/share/letkite-agent"
cat > "$work/opt/letkite-agent/letkite-agent" <<'AGENT'
#!/bin/sh
echo "$*" >> "$TEST_ROOT/calls"
[ -z "${TEST_INSTALL_FAIL:-}" ] || exit 1
[ "$*" != "install --claim" ] || [ -z "${TEST_OLD_AGENT:-}" ]
AGENT
cat > "$work/usr/bin/uci" <<'UCI'
#!/bin/sh
[ "$*" = '-q get letkite.main.claim' ] || exit 1
printf '%s\n' "${TEST_CLAIM:-0}"
UCI
chmod +x "$work/opt/letkite-agent/letkite-agent" "$work/usr/bin/uci"
export TEST_ROOT="$work" PATH="$work/usr/bin:$PATH"
root_script() { sed "s@/opt/@$work/opt/@g; s@/etc/@$work/etc/@g; s@/usr/@$work/usr/@g" "$1"; }
root_script "$repo/packages/letkite-agent/files/setup.sh" > "$work/usr/share/letkite-agent/setup.sh"
chmod +x "$work/usr/share/letkite-agent/setup.sh"
root_script "$repo/packages/letkite-agent/files/uci-defaults/90-letkite-claim" > "$work/defaults.sh"
root_script "$repo/packages/letkite-agent/files/profile.d/letkite.sh" > "$work/banner.sh"
setup() { sh "$work/usr/share/letkite-agent/setup.sh"; }
calls() { cat "$work/calls" 2>/dev/null; }
reset_calls() { : > "$work/calls"; }

export TEST_CLAIM=1
setup
check_eq 'fresh claim: exact CLI' 'install --claim' "$(calls)"
check_eq 'CLI symlink' "$work/opt/letkite-agent/letkite-agent" "$(readlink "$work/usr/bin/letkite-agent")"
reset_calls
printf 'url = "https://nodes.letkite.dev"\n' > "$work/etc/letkite/setup.toml"
setup
check_eq 'custom setup: plain install' install "$(calls)"
check_eq 'custom setup preserved' 'url = "https://nodes.letkite.dev"' "$(cat "$work/etc/letkite/setup.toml")"
check_has 'unclaimed SSH hint' "$(sh "$work/banner.sh")" 'letkite-agent claim'
check_eq 'SSH banner never runs agent' install "$(calls)"
reset_calls
touch "$work/etc/letkite/agent.toml"
setup
check_eq 'enrolled identity: plain install' install "$(calls)"
check_eq 'enrolled SSH: silent' '' "$(sh "$work/banner.sh")"
rm "$work/etc/letkite/setup.toml" "$work/etc/letkite/agent.toml"
reset_calls
TEST_CLAIM=0 setup
check_eq 'opt out: plain install' install "$(calls)"
reset_calls
IPKG_INSTROOT="$work/image" setup
check_eq 'image build: no runtime invocation' '' "$(calls)"
TEST_CLAIM=0 sh "$work/defaults.sh"
check_eq 'first boot opt out: no invocation' '' "$(calls)"
sh "$work/defaults.sh"
check_eq 'first boot claim: exact CLI' 'install --claim' "$(calls)"
reset_calls
if TEST_INSTALL_FAIL=1 sh "$work/defaults.sh"; then rc=0; else rc=$?; fi
check_eq 'failed first boot: nonzero so uci-defaults retries' 1 "$rc"
check_eq 'failed first boot: no silent legacy fallback' 'install --claim' "$(calls)"
reset_calls
if TEST_OLD_AGENT=1 setup; then rc=0; else rc=$?; fi
check_eq 'postinst claim on old agent succeeds' 0 "$rc"
check_eq 'postinst claim falls back to plain install' "$(printf 'install --claim\ninstall')" "$(calls)"
reset_calls
touch "$work/etc/letkite/setup.toml"
TEST_CLAIM=0 sh "$work/defaults.sh"
check_eq 'setup-only firmware installs with claim=0' install "$(calls)"
if TEST_CLAIM=0 TEST_INSTALL_FAIL=1 sh "$work/defaults.sh"; then rc=0; else rc=$?; fi
check_eq 'setup-only firmware failure stays strict' 1 "$rc"
if TEST_INSTALL_FAIL=1 setup; then rc=0; else rc=$?; fi
check_eq 'postinst plain install failure is deferred' 0 "$rc"
reset_calls
touch "$work/etc/init.d/letkite-agent"
chmod +x "$work/etc/init.d/letkite-agent"
sh "$work/defaults.sh"
check_eq 'already installed service skips second setup' '' "$(calls)"
rm "$work/etc/init.d/letkite-agent" "$work/etc/letkite/setup.toml"
mv "$work/opt/letkite-agent/letkite-agent" "$work/opt/letkite-agent/absent"
if sh "$work/defaults.sh" >/dev/null 2>&1; then rc=0; else rc=$?; fi
check_eq 'missing firmware binary: fail for retry' 1 "$rc"
finish
