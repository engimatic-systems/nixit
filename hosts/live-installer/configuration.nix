{ config, lib, pkgs, ... }:

let
  nixosPasswordHash = "$6$syslive01$0wi4jkHHnvt8vKxMWfyywbXm4yp6uz1EvN.48GldIWhOYGHQDNUxwtB3ql3YTq3FDDc72Q130Nj47VSKNh./5/";
in
{
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>
  ];

  image.baseName = lib.mkForce "nixboxes-live-installer-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}";

  boot.zfs.forceImportRoot = false;

  networking.hostName = "nixboxes-live";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
  };

  security.sudo.wheelNeedsPassword = false;

  users.users.root.initialHashedPassword = lib.mkForce nixosPasswordHash;
  users.users.nixos = {
    extraGroups = [ "wheel" ];
    initialHashedPassword = lib.mkForce nixosPasswordHash;
  };

  environment.systemPackages = with pkgs; [
    bashInteractive
    curl
    git
    openssh
    vim
  ];

  system.stateVersion = "26.05";
}
