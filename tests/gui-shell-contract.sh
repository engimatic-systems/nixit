#!/usr/bin/env bash
# shellcheck disable=SC2016
# Child shell expressions are deliberately passed literally.
# Run only inside an explicitly identified disposable proof VM, as its GUI user.
set -euo pipefail
: "${GUI_TEST_DISPOSABLE:?Set only in a dedicated disposable proof guest}"
[[ $(hostname) = gui-cleanup-* ]]
runtime=/run/user/$(id -u)
record=$runtime/gui-session.env
fixture=$(mktemp -d)
cp "$record" "$fixture/original"
restore() { cp "$fixture/original" "$record.next"; chmod 600 "$record.next"; mv "$record.next" "$record"; }
trap 'restore; rm -rf "$fixture"' EXIT
login() { env -u DISPLAY -u XAUTHORITY -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS bash -e -lc "$1" >"$fixture/out" 2>"$fixture/err"; }
warns() { login 'printf "ordinary-ok\n"; test -z "${DISPLAY:-}"'; grep -Fx ordinary-ok "$fixture/out"; grep -q '^GUI attachment unavailable:' "$fixture/err"; }
login 'test "$DISPLAY" = :0; xdpyinfo >/dev/null; i3-msg -t get_version >/dev/null'
test ! -s "$fixture/err"
rm "$record"
warns
restore
printf 'DISPLAY=:0\n' >> "$record"
warns
restore
sed -i '/^XAUTHORITY=/d' "$record"
warns
restore
sed -i 's/^DISPLAY=.*/DISPLAY=:98765/' "$record"
warns
restore
sed -i 's|^XAUTHORITY=.*|XAUTHORITY=/invalid|' "$record"
warns
restore
sed -i 's|^I3SOCK=.*|I3SOCK=/invalid|' "$record"
warns
restore
chmod 0644 "$record"
warns
restore
# A complete record must never be sourced as code.
printf 'NOT_A_FIELD=$(touch %s/injected)\n' "$fixture" >> "$record"
login 'test "$DISPLAY" = :0'
test ! -e "$fixture/injected"
restore
DISPLAY=:98765 XAUTHORITY=/caller bash -e -lc 'test "$DISPLAY" = :98765; test "$XAUTHORITY" = /caller; echo ordinary-ok' >"$fixture/out" 2>"$fixture/err"
grep -Fx ordinary-ok "$fixture/out"
grep -q 'preserving it' "$fixture/err"
DISPLAY=:0 XAUTHORITY=/invalid bash -e -lc 'test "$XAUTHORITY" = /invalid; echo ordinary-ok' >"$fixture/out" 2>"$fixture/err"
grep -Fx ordinary-ok "$fixture/out"
grep -q '^GUI attachment unavailable:' "$fixture/err"
# A valid default authority must preserve an unset XAUTHORITY.
mkdir -p "$fixture/home/.config/sys"
cp "$runtime/gui-Xauthority" "$fixture/home/.Xauthority"
printf 'export GITHUB_HOOK_FIXTURE=loaded\n' > "$fixture/home/.config/sys/github.env"
HOME="$fixture/home" DISPLAY=:0 env -u XAUTHORITY bash -e -lc 'test -z "${XAUTHORITY+x}"; xdpyinfo >/dev/null' >"$fixture/out" 2>"$fixture/err"
test ! -s "$fixture/err"
# Sys's actual profile composes its existing non-secret GitHub hook.
if [ "$(id -un)" = agent ]; then
  HOME="$fixture/home" env -u DISPLAY -u XAUTHORITY bash -e -lc 'test "$GITHUB_HOOK_FIXTURE" = loaded; test "$DISPLAY" = :0; echo github-ok' >"$fixture/out" 2>"$fixture/err"
  grep -Fx github-ok "$fixture/out"
fi
printf 'PASS: actual installed login profile/parser, invalid records, caller preservation, default authority and hook composition\n'
