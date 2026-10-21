# shellcheck shell=sh
# Assertions for the unit tests (POSIX sh, BusyBox included).
passed=0
failed=0

ok() { passed=$((passed + 1)); echo "ok - $1"; }
not_ok() { failed=$((failed + 1)); echo "not ok - $1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }

# check NAME COMMAND...: the command succeeds
check() {
	name=$1; shift
	if "$@"; then ok "$name"; else not_ok "$name"; fi
}

# check_eq NAME EXPECTED ACTUAL
check_eq() {
	if [ "$2" = "$3" ]; then ok "$1"; else not_ok "$1" "expected: $2
actual:   $3"; fi
}

# check_has NAME HAYSTACK NEEDLE
check_has() {
	case "$2" in *"$3"*) ok "$1" ;; *) not_ok "$1" "no \"$3\" in:
$2" ;; esac
}

finish() {
	echo "# $passed passed, $failed failed"
	[ "$failed" -eq 0 ]
}
