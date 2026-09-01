{
  config,
  lib,
  pkgs,
  ...
}:

let
  i3Config = pkgs.writeText "minimal-i3-config" ''
    set $mod Mod4
    font pango:DejaVu Sans Mono 10
    floating_modifier $mod
    focus_follows_mouse yes

    bindsym $mod+Return exec ${pkgs.xterm}/bin/xterm
    bindsym $mod+d exec ${pkgs.dmenu}/bin/dmenu_run
    bindsym $mod+Shift+q kill
    bindsym $mod+Shift+e exit

    bar {
      status_command ${pkgs.i3status}/bin/i3status
      position bottom
    }

    exec --no-startup-id ${pkgs.xterm}/bin/xterm
  '';

  xrdpI3Session = pkgs.writeShellScript "xrdp-i3-session" ''
    if [ -z "''${XDG_RUNTIME_DIR:-}" ] || [ ! -d "$XDG_RUNTIME_DIR" ]; then
      echo "xrdp PAM did not provide XDG_RUNTIME_DIR" >&2
      exit 1
    fi

    export DBUS_SESSION_BUS_ADDRESS="''${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
    export XDG_SESSION_TYPE=x11
    export XDG_CURRENT_DESKTOP=i3
    export XDG_SESSION_DESKTOP=i3
    export DESKTOP_SESSION=i3

    ${config.systemd.package}/bin/systemctl --user import-environment \
      PATH DISPLAY XAUTHORITY DESKTOP_SESSION \
      XDG_CONFIG_DIRS XDG_DATA_DIRS XDG_RUNTIME_DIR XDG_SESSION_ID \
      XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP \
      DBUS_SESSION_BUS_ADDRESS || true

    ${pkgs.dbus}/bin/dbus-update-activation-environment \
      --systemd --all || true

    exec ${pkgs.i3}/bin/i3 -c ${i3Config}
  '';
in
{
  imports = lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  boot.loader.grub.devices = [ "/dev/vda" ];

  networking = {
    hostName = "nixos";
    useDHCP = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ ];
      allowedUDPPorts = [ ];
    };
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };

  users.users.root.hashedPassword = "!";
  users.users.nixos = {
    isNormalUser = true;
    initialPassword = "nixos";
    extraGroups = [ "wheel" ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
  };

  services.xserver = {
    enable = false;
    windowManager.i3 = {
      enable = true;
      configFile = i3Config;
      extraPackages = [
        pkgs.dmenu
        pkgs.i3status
      ];
    };
  };

  services.xrdp = {
    enable = true;
    openFirewall = false;
    defaultWindowManager = "${xrdpI3Session}";
    extraConfDirCommands = ''
      substituteInPlace $out/sesman.ini \
        --replace-fail 'EnableUserWindowManager=true' 'EnableUserWindowManager=false' \
        --replace-fail 'AllowRootLogin=true' 'AllowRootLogin=false' \
        --replace-fail 'Policy=Default' 'Policy=UB'

      grep -Fxq 'KillDisconnected=false' $out/sesman.ini
      grep -Fxq 'DisconnectedTimeLimit=0' $out/sesman.ini
    '';
  };

  environment.systemPackages = [ pkgs.xterm ];
  fonts.packages = [ pkgs.dejavu_fonts ];

  system.stateVersion = "26.05";
}
