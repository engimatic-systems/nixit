{
  configurationPath,
  nixpkgsPath,
}:

let
  nixpkgs = builtins.toPath nixpkgsPath;
  configuration = builtins.toPath configurationPath;
  hardwareEvaluationFixture = {
    fileSystems."/" = {
      device = "/dev/vda2";
      fsType = "ext4";
    };
  };
  evaluated = import (nixpkgs + "/nixos/lib/eval-config.nix") {
    system = "x86_64-linux";
    modules = [
      configuration
      hardwareEvaluationFixture
    ];
  };
  inherit (evaluated) config pkgs;
  inherit (pkgs) lib;
  xrdpOverrides = config.services.xrdp.extraConfDirCommands;
in
assert config.boot.loader.grub.devices == [ "/dev/vda" ];
assert config.networking.useDHCP;
assert config.networking.firewall.enable;
assert config.networking.firewall.allowedTCPPorts == [ 22 ];
assert config.networking.firewall.allowedUDPPorts == [ ];
assert config.services.openssh.enable;
assert config.services.openssh.settings.PasswordAuthentication;
assert config.services.openssh.settings.PermitRootLogin == "no";
assert config.users.users.root.hashedPassword == "!";
assert config.users.users.nixos.initialPassword == "nixos";
assert lib.elem "wheel" config.users.users.nixos.extraGroups;
assert config.security.sudo.enable;
assert config.security.sudo.wheelNeedsPassword;
assert !config.services.xserver.enable;
assert config.services.xserver.windowManager.i3.enable;
assert lib.hasSuffix "-minimal-i3-config" (
  toString config.services.xserver.windowManager.i3.configFile
);
assert lib.elem pkgs.xterm config.environment.systemPackages;
assert lib.elem pkgs.dmenu config.environment.systemPackages;
assert lib.elem pkgs.i3status config.environment.systemPackages;
assert lib.elem pkgs.dejavu_fonts config.fonts.packages;
assert config.services.xrdp.enable;
assert !config.services.xrdp.openFirewall;
assert config.services.xrdp.port == 3389;
assert lib.hasSuffix "-xrdp-i3-session" config.services.xrdp.defaultWindowManager;
assert lib.hasInfix "EnableUserWindowManager=false" xrdpOverrides;
assert lib.hasInfix "AllowRootLogin=false" xrdpOverrides;
assert lib.hasInfix "Policy=UB" xrdpOverrides;
assert lib.hasInfix "KillDisconnected=false" xrdpOverrides;
assert lib.hasInfix "DisconnectedTimeLimit=0" xrdpOverrides;
assert config.system.build.toplevel.drvPath != "";
"minimal-i3 contract passed"
