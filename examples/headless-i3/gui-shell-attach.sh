# shellcheck shell=bash
# Sourced by the configured graphical user's Bash login shells.
_gui_shell_attach() {
  # A working caller-selected display needs no discovery; XAUTHORITY may
  # legitimately be unset (for example with the default ~/.Xauthority).
  if [ -n "${DISPLAY:-}" ] &&
    @timeout@ 2 @xdpyinfo@ >/dev/null 2>&1; then
    return 0
  fi

  local record=@runtimeDir@/gui-session.env
  local name value
  local -A session_values=()
  if [ ! -r "$record" ] ||
    [ "$(@stat@ -c '%u:%a' "$record" 2>/dev/null)" != "@guiUid@:600" ]; then
    printf 'GUI attachment unavailable: no private session record.\n' >&2
    return 0
  fi

  # Parse data, never execute it. In particular, do not import the
  # separate session-owned CODEX_APP_SERVER_SOCKET from this record.
  while IFS='=' read -r name value; do
    case "$name" in
      DISPLAY|XAUTHORITY|XDG_RUNTIME_DIR|DBUS_SESSION_BUS_ADDRESS|I3SOCK)
        if [[ -v session_values[$name] ]] || [ -z "$value" ]; then
          printf 'GUI attachment unavailable: ambiguous or incomplete session record.\n' >&2
          return 0
        fi
        session_values[$name]=$value
        ;;
    esac
  done < "$record"
  for name in DISPLAY XAUTHORITY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS I3SOCK; do
    if [[ ! -v session_values[$name] ]]; then
      printf 'GUI attachment unavailable: incomplete session record.\n' >&2
      return 0
    fi
  done

  if [ "${session_values[DISPLAY]}" != :0 ] ||
    [ "${session_values[XAUTHORITY]}" != @runtimeDir@/gui-Xauthority ] ||
    [ "${session_values[XDG_RUNTIME_DIR]}" != @runtimeDir@ ] ||
    [ "${session_values[DBUS_SESSION_BUS_ADDRESS]}" != unix:path=@runtimeDir@/bus ] ||
    [[ ! "${session_values[I3SOCK]}" =~ ^@runtimeDir@/i3/ipc-socket\.[0-9]+$ ]]; then
    printf 'GUI attachment unavailable: invalid session record.\n' >&2
    return 0
  fi

  # Never borrow a different display's authority for a caller-selected
  # display that failed its connectivity check.
  if [ -n "${DISPLAY:-}" ] && [ "$DISPLAY" != "${session_values[DISPLAY]}" ]; then
    printf 'GUI attachment unavailable: existing DISPLAY is unreachable; preserving it.\n' >&2
    return 0
  fi
  local next_display="${DISPLAY:-${session_values[DISPLAY]}}"
  local next_authority="${XAUTHORITY-${session_values[XAUTHORITY]}}"
  local next_runtime="${XDG_RUNTIME_DIR-${session_values[XDG_RUNTIME_DIR]}}"
  local next_bus="${DBUS_SESSION_BUS_ADDRESS-${session_values[DBUS_SESSION_BUS_ADDRESS]}}"
  if DISPLAY="$next_display" XAUTHORITY="$next_authority" \
    @timeout@ 2 @xdpyinfo@ >/dev/null 2>&1 &&
    @timeout@ 2 @i3msg@ -s "${session_values[I3SOCK]}" -t get_version >/dev/null 2>&1 &&
    DBUS_SESSION_BUS_ADDRESS="$next_bus" @timeout@ 2 @dbusSend@ --session \
      --print-reply --type=method_call --dest=org.freedesktop.DBus \
      /org/freedesktop/DBus org.freedesktop.DBus.ListNames >/dev/null 2>&1; then
    export DISPLAY="$next_display" XAUTHORITY="$next_authority"
    export XDG_RUNTIME_DIR="$next_runtime" DBUS_SESSION_BUS_ADDRESS="$next_bus"
  else
    printf 'GUI attachment unavailable: X connection failed; preserving existing environment.\n' >&2
  fi
  return 0
}
_gui_shell_attach
unset -f _gui_shell_attach
