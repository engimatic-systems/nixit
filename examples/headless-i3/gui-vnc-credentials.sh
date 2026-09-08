#!/usr/bin/env bash
# Nix supplies paths and tools; credentials are generated only in guest state.
set -euo pipefail
umask 077
[[ $(id -u) = "$GUI_UID" ]] || { echo 'Run this command as the graphical user.' >&2; exit 1; }
state=${GUI_VNC_STATE_DIR:?}
legacy=${GUI_RUNTIME_DIR:?}/x11vnc.pass
password_file=$state/passwd
operation=${1:-ensure}
case "$operation" in ensure|rotate) ;; *) echo 'Usage: gui-vnc-credentials [ensure|rotate]' >&2; exit 2 ;; esac
if [ ! -e "$state" ]; then install -d -m 0700 "$state"; fi
if [ -L "$state" ] || [ ! -d "$state" ] || [ "$(stat -c '%u:%a' "$state")" != "$GUI_UID:700" ]; then
  echo 'VNC state directory must be private and owned by the graphical user.' >&2
  exit 1
fi
[[ ! -L "$state/.lock" ]] || { echo 'Invalid VNC state lock.' >&2; exit 1; }
exec {lock_fd}>"$state/.lock"
flock "$lock_fd"
private_password() {
  [ ! -L "$1" ] && [ -f "$1" ] && [ "$(stat -c '%u:%a:%s' "$1")" = "$GUI_UID:600:8" ]
}
if [ -e "$password_file" ] || [ -L "$password_file" ]; then
  private_password "$password_file" || { echo 'Existing VNC credential has unsafe metadata; refusing to replace it.' >&2; exit 1; }
  if [ "$operation" = ensure ]; then exit 0; fi
fi
temporary=$(mktemp "$state/.passwd.XXXXXX")
restart_vnc=0
cleanup() {
  rm -f -- "$temporary"
  flock -u "$lock_fd"
  if [ "$restart_vnc" = 1 ]; then systemctl --user start gui-vnc.service; fi
}
trap cleanup EXIT
if [ "$operation" = ensure ] && { [ -e "$legacy" ] || [ -L "$legacy" ]; }; then
  private_password "$legacy" || { echo 'Legacy runtime VNC credential has unsafe metadata.' >&2; exit 1; }
  cat "$legacy" > "$temporary"
else
  # Classic VNC consumes eight characters; SSH provides transport encryption.
  # Password bytes go through stdin, never argv, the Nix store or the journal.
  password=$(openssl rand -hex 4)
  printf '%s\n%s\ny\n' "$password" "$password" \
    | x11vnc -storepasswd "$temporary" >/dev/null 2>&1
  unset password
fi
chmod 0600 "$temporary"
private_password "$temporary"
if [ "$operation" = rotate ]; then
  # Stop only VNC so no new viewer can authenticate against an old in-memory
  # credential after publication. X, i3 and GUI applications keep running.
  systemctl --user stop gui-vnc.service
  restart_vnc=1
fi
mv -f -- "$temporary" "$password_file"
if [ "$operation" = ensure ]; then rm -f -- "$legacy"; fi
# Release the lock before startup: ExecStartPre runs this helper's ensure.
flock -u "$lock_fd"
if [ "$operation" = rotate ]; then
  restart_vnc=0
  if ! systemctl --user start gui-vnc.service; then
    echo 'Credential rotated; VNC startup failed. Inspect gui-vnc journal, then restart it and refetch the credential.' >&2
    exit 1
  fi
  echo 'VNC credential rotated. Refetch the private password file and reconnect viewers.'
fi
