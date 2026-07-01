{ lib, pkgs, ... }:

{
  imports = lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  boot.loader.grub.devices = [ "/dev/vda" ];

  networking.hostName = "nixos";
  networking.useDHCP = true;

  services.openssh = {
    enable = true;
    openFirewall = true;
  };

  users.users.root.hashedPassword = "!";
  users.users.nixos = {
    isNormalUser = true;
    initialPassword = "nixos";
    extraGroups = [ "wheel" ];
  };

  environment.systemPackages = with pkgs; [
    curl
    git
    vim
  ];

  system.stateVersion = "26.05";
}
