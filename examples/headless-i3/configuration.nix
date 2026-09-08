{
  lib,
  pkgs,
  ...
}:

let
  # Keep consumer choices here. Supply a public SSH key before installation.
  guiUser = "nixos";

in
{
  imports = [
    (import ./graphical.nix { inherit guiUser; })
  ]
  ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;
  boot.loader.grub.devices = [ "/dev/vda" ];
  networking.hostName = "headless-i3";
  networking.useDHCP = true;
  networking.firewall.enable = true;

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

  environment.systemPackages = with pkgs; [
    bashInteractive
  ];

  system.stateVersion = "26.05";
}
