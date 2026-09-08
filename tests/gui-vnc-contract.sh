#!/usr/bin/env bash
# Exercise the installed helper only in the explicitly named disposable guest.
set -euo pipefail
: "${GUI_TEST_DISPOSABLE:?Set only in a dedicated disposable proof guest}"
[[ $(hostname) = gui-cleanup-* ]]
state=$HOME/.local/state/gui-vnc
fixture=$(mktemp -d)
cp "$state/passwd" "$fixture/original"
restore() {
  chmod 0600 "$state/passwd" 2>/dev/null || true
  cp "$fixture/original" "$state/passwd"
  chmod 0600 "$state/passwd"
  rm -rf "$fixture"
}
trap restore EXIT
test "$(stat -c '%u:%a' "$state")" = "$(id -u):700"
test "$(stat -c '%u:%a:%s' "$state/passwd")" = "$(id -u):600:8"
gui-vnc-credentials ensure
cmp "$fixture/original" "$state/passwd"
chmod 0644 "$state/passwd"
if gui-vnc-credentials ensure >"$fixture/out" 2>"$fixture/err"; then exit 1; fi
test ! -s "$fixture/out"
grep -q 'unsafe metadata' "$fixture/err"
cmp "$fixture/original" "$state/passwd"
chmod 0600 "$state/passwd"
# First-use generation runs the real installed artifact without legacy state.
rm "$state/passwd"
gui-vnc-credentials ensure
test "$(stat -c '%u:%a:%s' "$state/passwd")" = "$(id -u):600:8"
cp "$state/passwd" "$fixture/generated"
gui-vnc-credentials ensure &
first=$!
gui-vnc-credentials ensure &
second=$!
wait "$first" "$second"
cmp "$fixture/generated" "$state/passwd"
printf 'PASS: first-use, private modes, reuse, concurrent ensure and unsafe-file refusal against installed credential helper\n'
