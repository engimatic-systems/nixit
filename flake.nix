{
  description = "Development dependencies for nixit headless RDP smoke tests";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/5dfba6236110080a54247d6460bc2ff5dda939cc";

  outputs = { nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      devShells.${system}.rdp-smoke = pkgs.mkShellNoCC {
        packages = with pkgs; [
          coreutils
          freerdp
          imagemagick
          openssh
          qemu
          util-linux
          xdotool
          xvfb
          xvfb-run
        ];

        NIXPKGS_PATH = toString nixpkgs;
      };
    };
}
