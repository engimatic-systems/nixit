{ nixpkgsPath, examplePath }:
let
  evaluated = import (nixpkgsPath + "/nixos/lib/eval-config.nix") {
    system = "x86_64-linux";
    modules = [
      (examplePath + "/configuration.nix")
      {
        # install-nixos-vm supplies this on the installed disk.
        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };
      }
    ];
  };
  c = evaluated.config;
  names = map evaluated.pkgs.lib.getName c.environment.systemPackages;
in
assert c.users.users.nixos.linger;
assert c.users.users.root.hashedPassword == "!";
assert c.services.openssh.settings.PermitRootLogin == "no";
assert c.services.openssh.settings.PasswordAuthentication == false;
assert c.security.sudo.wheelNeedsPassword == false;
assert c.networking.firewall.allowedTCPPorts == [ 22 ];
assert c.networking.firewall.allowedUDPPorts == [ ];
assert c.systemd.user.services.gui-session.unitConfig.ConditionUser == "nixos";
assert c.systemd.user.services.gui-session.serviceConfig.Restart == "always";
assert builtins.elem "default.target" c.systemd.user.services.gui-session.wantedBy;
assert !builtins.any (name: builtins.match ".*(codex|mise).*" name != null) names;
assert !(c.systemd.user.services ? codex-app-server);
assert c.systemd.user.services.gui-i3.bindsTo == [ "gui-session.service" ];
assert c.systemd.user.services.gui-vnc.bindsTo == [ "gui-session.service" ];
assert c.systemd.user.services.gui-i3.serviceConfig.Restart == "always";
assert c.systemd.user.services.gui-vnc.serviceConfig.Restart == "always";

{
  system = c.system.build.toplevel;
  sessionCheck = evaluated.pkgs.runCommand "gui-artifact-check" { } ''
    ${evaluated.pkgs.bash}/bin/bash -n ${builtins.head (evaluated.pkgs.lib.splitString " " c.systemd.user.services.gui-session.serviceConfig.ExecStartPre)}
    ${evaluated.pkgs.i3}/bin/i3 -C -c ${builtins.elemAt (evaluated.pkgs.lib.splitString " " c.systemd.user.services.gui-i3.serviceConfig.ExecStart) 2}
    ${evaluated.pkgs.bash}/bin/bash -n ${builtins.head (evaluated.pkgs.lib.splitString " " c.systemd.user.services.gui-vnc.serviceConfig.ExecStartPre)}
    touch "$out"
  '';
  loginProfile = c.environment.etc.profile.source;
}
