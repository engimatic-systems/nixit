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
      iproute2
      openssl
      util-linux
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
  shellAttach = pkgs.replaceVars ./gui-shell-attach.sh {
    inherit runtimeDir;
    guiUid = toString guiUid;
    timeout = "${pkgs.coreutils}/bin/timeout";
    stat = "${pkgs.coreutils}/bin/stat";
    xdpyinfo = "${pkgs.xorg.xdpyinfo}/bin/xdpyinfo";
  };
in
{
  services.dbus.enable = true;
  systemd.user.services.gui-session = {
    description = "Unattended authenticated Xvfb and i3 session";
    wantedBy = [ "default.target" ];
    wants = [ "dbus.socket" ];
    after = [ "dbus.socket" ];
    unitConfig.ConditionUser = guiUser;
    serviceConfig = {
      Type = "simple";
      ExecStart = "${session}/bin/gui-vm-session";
      Restart = "always";
      RestartSec = "1s";
    };
  };
  programs.bash.loginShellInit = ''
    if [ "$UID" = "${toString guiUid}" ]; then
      . ${shellAttach}
    fi
  '';
  fonts.packages = [ pkgs.dejavu_fonts ];
  environment.systemPackages = with pkgs; [
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
