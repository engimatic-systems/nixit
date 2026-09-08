{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Keep consumer choices here. Supply a public SSH key before installation.
  guiUser = "nixos";
  guiUid = config.users.users.${guiUser}.uid;
  runtimeDir = "/run/user/${toString guiUid}";
  i3Config = pkgs.writeText "headless-i3-config" ''
    set $mod Mod4
    font pango:DejaVu Sans Mono 10
    floating_modifier $mod
    focus_follows_mouse yes
    bindsym $mod+Return exec ${pkgs.xterm}/bin/xterm
    bindsym $mod+d exec ${pkgs.dmenu}/bin/dmenu_run
    bindsym $mod+Shift+q kill
    bindsym $mod+Shift+e exit
    exec --no-startup-id ${pkgs.xorg.xsetroot}/bin/xsetroot -solid "#25324a"
  '';
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
  imports = lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;
  boot.loader.grub.devices = [ "/dev/vda" ];
  networking.hostName = "headless-i3";
  networking.useDHCP = true;
  networking.firewall.enable = true;

  services.dbus.enable = true;
  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
    };
  };
  users.users.root.hashedPassword = "!";
  users.users.${guiUser} = {
    isNormalUser = true;
    uid = 1000;
    linger = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [ ]; # Supply the VM owner's public key.
  };
  security.sudo.wheelNeedsPassword = false;

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
  environment.systemPackages = with pkgs; [
    bashInteractive
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
  fonts.packages = [ pkgs.dejavu_fonts ];
  system.stateVersion = "26.05";
}
