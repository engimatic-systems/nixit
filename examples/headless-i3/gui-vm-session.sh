#!/usr/bin/env bash
# Nix supplies executable dependencies through PATH and these explicit inputs.
set -euo pipefail
umask 077

runtime_dir=${GUI_RUNTIME_DIR:?}
display=${GUI_DISPLAY:?}
i3_config=${GUI_I3_CONFIG:?}
authority="$runtime_dir/gui-Xauthority"
ready="$runtime_dir/gui-session.ready"
environment_file="$runtime_dir/gui-session.env"
vnc_password_file="$runtime_dir/x11vnc.pass"
pids=()

cleanup() {
  trap - EXIT INT TERM
  rm -f -- "$ready" "$environment_file" "$authority" "$vnc_password_file"
  if (( ${#pids[@]} )); then
    kill "${pids[@]}" 2>/dev/null || true
    wait "${pids[@]}" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 0' INT TERM
rm -f -- "$authority" "$ready" "$environment_file" "$vnc_password_file"
xauth -f "$authority" add "$display" . "$(mcookie)"
chmod 0600 "$authority"

Xvfb "$display" -screen 0 1280x800x24 -nolisten tcp -auth "$authority" \
  >"$runtime_dir/Xvfb.log" 2>&1 &
xvfb_pid=$!
pids+=("$xvfb_pid")
export DISPLAY="$display" XAUTHORITY="$authority"
export XDG_RUNTIME_DIR="$runtime_dir"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus"
for _attempt in $(seq 1 100); do
  if xdpyinfo >/dev/null 2>&1; then break; fi
  kill -0 "$xvfb_pid"
  sleep 0.1
done
xdpyinfo >/dev/null
dbus-send --session --type=method_call --dest=org.freedesktop.DBus \
  /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null

i3 -c "$i3_config" >"$runtime_dir/i3.log" 2>&1 &
i3_pid=$!
pids+=("$i3_pid")
for _attempt in $(seq 1 100); do
  if i3-msg -t get_version >/dev/null 2>&1; then break; fi
  kill -0 "$i3_pid"
  sleep 0.1
done
i3-msg -t get_version >/dev/null

# Classic VNC authentication consumes eight characters. SSH provides transport
# encryption; the VNC listener is intentionally restricted to guest loopback.
vnc_password=$(openssl rand -hex 4)
printf '%s\n%s\ny\n' "$vnc_password" "$vnc_password" \
  | x11vnc -storepasswd "$vnc_password_file" >/dev/null 2>&1
unset vnc_password
chmod 0600 "$vnc_password_file"
x11vnc -display "$display" -auth "$authority" -rfbauth "$vnc_password_file" \
  -rfbport 5900 -localhost -forever -shared -noxdamage \
  >"$runtime_dir/x11vnc.log" 2>&1 &
x11vnc_pid=$!
pids+=("$x11vnc_pid")
for _attempt in $(seq 1 100); do
  if ss -lnt | grep -q '127.0.0.1:5900'; then break; fi
  kill -0 "$x11vnc_pid"
  sleep 0.1
done
ss -lnt | grep -q '127.0.0.1:5900'

printf '%s\n' "DISPLAY=$display" "XAUTHORITY=$authority" \
  "XDG_RUNTIME_DIR=$runtime_dir" "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" \
  > "$environment_file"
printf '%s\n' "ready_at=$(date --iso-8601=ns)" "uptime=$(cut -d' ' -f1 /proc/uptime)" \
  "xvfb_pid=$xvfb_pid" "i3_pid=$i3_pid" "x11vnc_pid=$x11vnc_pid" > "$ready"

# Only graphical processes participate. An independently launched command
# server neither starts this session nor determines its lifetime.
wait -n "${pids[@]}"
