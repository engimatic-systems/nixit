{ guiUser }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  guiUid = config.users.users.${guiUser}.uid;
  runtimeDir = "/run/user/${toString guiUid}";
  vncStateDir = "${config.users.users.${guiUser}.home}/.local/state/gui-vnc";
  i3Config = pkgs.replaceVars ./i3.config {
    xterm = "${pkgs.xterm}/bin/xterm";
    dmenu = "${pkgs.dmenu}/bin/dmenu_run";
    xsetroot = "${pkgs.xorg.xsetroot}/bin/xsetroot";
  };
  session = pkgs.writeShellApplication {
    name = "gui-vm-session";
    runtimeInputs = with pkgs; [
      coreutils
      dbus
      gnugrep
      i3
      openssl
      util-linux
      systemd
      x11vnc
      xorg.xauth
      xorg.xdpyinfo
      xorg.xorgserver
    ];
    text = ''
      export GUI_RUNTIME_DIR=${lib.escapeShellArg runtimeDir}
      export GUI_DISPLAY=:0
      export GUI_I3_CONFIG=${i3Config}
    ''
    + builtins.readFile ./gui-vm-session.sh;
  };
  vncCredentials = pkgs.writeShellApplication {
    name = "gui-vnc-credentials";
    runtimeInputs = with pkgs; [
      coreutils
      openssl
      util-linux
      x11vnc
      systemd
    ];
    text = ''
      export GUI_UID=${toString guiUid}
      export GUI_RUNTIME_DIR=${lib.escapeShellArg runtimeDir}
      export GUI_VNC_STATE_DIR=${lib.escapeShellArg vncStateDir}
    ''
    + builtins.readFile ./gui-vnc-credentials.sh;
  };
  sessionEnvironment = {
    DISPLAY = ":0";
    XAUTHORITY = "${runtimeDir}/gui-Xauthority";
    XDG_RUNTIME_DIR = runtimeDir;
    DBUS_SESSION_BUS_ADDRESS = "unix:path=${runtimeDir}/bus";
  };
  shellAttach = pkgs.replaceVars ./gui-shell-attach.sh {
    inherit runtimeDir;
    guiUid = toString guiUid;
    timeout = "${pkgs.coreutils}/bin/timeout";
    stat = "${pkgs.coreutils}/bin/stat";
    i3msg = "${pkgs.i3}/bin/i3-msg";
    dbusSend = "${pkgs.dbus}/bin/dbus-send";
    xdpyinfo = "${pkgs.xorg.xdpyinfo}/bin/xdpyinfo";
  };
in
{
  services.dbus.enable = true;
  # The display owns session lifetime. Its Wants starts dependents again after
  # recovery; their BindsTo/After stops them when X is lost. Neither dependent
  # can propagate its own failure back to X or to another dependent.
  systemd.user.services.gui-session = {
    description = "Authenticated unattended X display";
    wantedBy = [ "default.target" ];
    wants = [
      "dbus.socket"
      "gui-i3.service"
      "gui-vnc.service"
    ];
    after = [ "dbus.socket" ];
    unitConfig = {
      ConditionUser = guiUser;
      StartLimitIntervalSec = 0;
    };
    environment = sessionEnvironment;
    serviceConfig = {
      Type = "exec";
      ExecStartPre = "${session}/bin/gui-vm-session prepare-x";
      ExecStart = "${pkgs.xorg.xorgserver}/bin/Xvfb :0 -screen 0 1280x800x24 -nolisten tcp -auth ${runtimeDir}/gui-Xauthority";
      ExecStartPost = "${session}/bin/gui-vm-session wait-x";
      ExecStopPost = "${session}/bin/gui-vm-session cleanup-x";
      Restart = "always";
      RestartSec = "1s";
      TimeoutStartSec = "15s";
      UMask = "0077";
    };
  };
  systemd.user.services.gui-i3 = {
    description = "Window manager and desktop attachment readiness";
    bindsTo = [ "gui-session.service" ];
    after = [ "gui-session.service" ];
    partOf = [ "gui-session.service" ];
    unitConfig = {
      ConditionUser = guiUser;
      StartLimitIntervalSec = 0;
    };
    environment = sessionEnvironment;
    serviceConfig = {
      Type = "exec";
      ExecStart = "${pkgs.i3}/bin/i3 -c ${i3Config}";
      ExecStartPost = "${session}/bin/gui-vm-session publish";
      ExecStopPost = "${session}/bin/gui-vm-session cleanup-i3";
      Restart = "always";
      RestartSec = "1s";
      TimeoutStartSec = "15s";
      UMask = "0077";
    };
  };
  systemd.user.services.gui-vnc = {
    description = "Loopback VNC attachment to the current X display";
    bindsTo = [ "gui-session.service" ];
    after = [ "gui-session.service" ];
    partOf = [ "gui-session.service" ];
    unitConfig = {
      ConditionUser = guiUser;
      StartLimitIntervalSec = 0;
    };
    environment = sessionEnvironment;
    serviceConfig = {
      Type = "exec";
      ExecStartPre = "${vncCredentials}/bin/gui-vnc-credentials ensure";
      ExecStart = "${pkgs.x11vnc}/bin/x11vnc -display :0 -auth ${runtimeDir}/gui-Xauthority -rfbauth ${vncStateDir}/passwd -rfbport 5900 -localhost -forever -shared -noxdamage";
      Restart = "always";
      RestartSec = "1s";
      UMask = "0077";
    };
  };
  programs.bash.loginShellInit = ''
    if [ "$UID" = "${toString guiUid}" ]; then
      . ${shellAttach}
    fi
  '';
  fonts.packages = [ pkgs.dejavu_fonts ];
  environment.systemPackages = with pkgs; [
    vncCredentials
    dbus
    dmenu
    i3
    imagemagick
    xdotool
    xorg.xauth
    xorg.xdpyinfo
    xorg.xprop
    xorg.xwininfo
    xterm
  ];
}
