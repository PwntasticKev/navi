# shellcheck shell=bash
# Small test helpers for the release scripts. Source it from a *.test.sh file, define
# test_* functions, then call run_tests.
# shellcheck disable=SC2034 # used by the test files that source this one
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
failures=0

assert_eq() {
  if [[ $1 != "$2" ]]; then
    printf '  FAIL %s\n    expected: %q\n    actual:   %q\n' "$3" "$1" "$2"
    failures=$((failures + 1))
  fi
}

assert_fails() {
  local what=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  FAIL %s: expected a failure\n' "$what"
    failures=$((failures + 1))
  fi
}

run_tests() {
  local name before
  for name in $(declare -F | awk '{print $3}' | grep '^test_'); do
    before=$failures
    "$name"
    if (( failures == before )); then echo "  ok   $name"; else echo "  FAIL $name"; fi
  done
  if (( failures > 0 )); then
    echo "$failures failed"
    exit 1
  fi
}
