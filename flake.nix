{
  description = "Minimal image-based operating system based on NixOS";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
  };
  outputs = { self, nixpkgs }: let
    relInfo = {
      system.image.id = "nixlet-hypervisor";
      system.image.version = "0.1";
      ab-image.imageVariant.config.ab-image.updates.url = "https://github.com/peter-marshall5/nixlet/releases/latest/download/";
      system.stateVersion = "23.11";
    };
  in {
    nixosModules.nixlet = ./modules;
    packages.x86_64-linux.hypervisor = (nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.nixlet
        ./modules/profiles/hypervisor.nix
        ./modules/profiles/debug.nix
        relInfo
      ];
    }).config.system.build.ab-image;
  };
}
