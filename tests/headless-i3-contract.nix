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
{
  system = c.system.build.toplevel;
  sessionCheck =
    evaluated.pkgs.runCommand "headless-i3-session-check"
      {
        nativeBuildInputs = [ evaluated.pkgs.bash ];
      }
      ''
            bash -n ${c.systemd.user.services.gui-session.serviceConfig.ExecStart}
        i3_config=$(${evaluated.pkgs.gnused}/bin/sed -n 's/^export GUI_I3_CONFIG=//p' ${c.systemd.user.services.gui-session.serviceConfig.ExecStart})
        ${evaluated.pkgs.i3}/bin/i3 -C -c "$i3_config"
            touch "$out"
      '';
  loginProfile = c.environment.etc.profile.source;
}
