#!/usr/bin/env bash
# Bounded systemd preparation/readiness operations; systemd owns all daemons.
set -euo pipefail
umask 077
runtime_dir=${GUI_RUNTIME_DIR:?}
authority="$runtime_dir/gui-Xauthority"
record="$runtime_dir/gui-session.env"
ready="$runtime_dir/gui-session.ready"
export DISPLAY=${GUI_DISPLAY:?} XAUTHORITY="$authority"
export XDG_RUNTIME_DIR="$runtime_dir"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"

case "${1:?operation required}" in
  prepare-x)
    rm -f -- "$record" "$ready" "$authority" "$runtime_dir/x11vnc.pass"
    # Feed the cookie through stdin rather than exposing it in process argv.
    printf 'add %s . %s\n' "$DISPLAY" "$(mcookie)" | xauth -q -f "$authority"
    chmod 0600 "$authority"
    ;;
  wait-x)
    for _attempt in $(seq 1 100); do
      kill -0 "${MAINPID:?}"
      if timeout 1 xdpyinfo >/dev/null 2>&1; then exit 0; fi
      sleep 0.1
    done
    echo "X display did not become usable for this service invocation" >&2
    exit 1
    ;;
  publish)
    for _attempt in $(seq 1 100); do
      kill -0 "${MAINPID:?}"
      socket=$(i3 --get-socketpath 2>/dev/null || true)
      # i3's socket includes its PID: another WM/listener cannot satisfy this.
      if [[ "$socket" = "$runtime_dir/i3/ipc-socket.$MAINPID" ]] &&
        timeout 1 i3-msg -s "$socket" -t get_version >/dev/null 2>&1; then break; fi
      sleep 0.1
    done
    [[ "$socket" = "$runtime_dir/i3/ipc-socket.$MAINPID" ]]
    timeout 2 i3-msg -s "$socket" -t get_version >/dev/null
    timeout 2 xdpyinfo >/dev/null
    timeout 2 dbus-send --session --print-reply --type=method_call \
      --dest=org.freedesktop.DBus /org/freedesktop/DBus \
      org.freedesktop.DBus.ListNames >/dev/null
    xvfb_pid=$(systemctl --user show gui-session.service -p MainPID --value)
    kill -0 "$xvfb_pid"
    temporary=$(mktemp "$runtime_dir/.gui-session.XXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    printf '%s\n' "DISPLAY=$DISPLAY" "XAUTHORITY=$authority" \
      "XDG_RUNTIME_DIR=$runtime_dir" "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" \
      "I3SOCK=$socket" "ready_at=$(date --iso-8601=ns)" \
      "uptime=$(cut -d' ' -f1 /proc/uptime)" "xvfb_pid=$xvfb_pid" "i3_pid=$MAINPID" \
      > "$temporary"
    ln -sfn gui-session.env "$ready"
    mv -f -- "$temporary" "$record"
    ;;
  cleanup-i3)
    rm -f -- "$record" "$ready"
    ;;
  cleanup-x)
    rm -f -- "$record" "$ready" "$authority" "$runtime_dir/x11vnc.pass"
    ;;
  prepare-vnc)
    if [ ! -f "$runtime_dir/x11vnc.pass" ]; then
      password=$(openssl rand -hex 4)
      printf '%s\n%s\ny\n' "$password" "$password" \
        | x11vnc -storepasswd "$runtime_dir/x11vnc.pass" >/dev/null 2>&1
      unset password
      chmod 0600 "$runtime_dir/x11vnc.pass"
    fi
    ;;
  *) echo "Unknown graphical session operation" >&2; exit 2 ;;
esac
