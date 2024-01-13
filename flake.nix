{
  description = "A read-only server OS based on NixOS";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-unstable;
  };
  outputs = { self, nixpkgs }: {
    nixosModules.appliance = ./modules/appliance;
    packages.x86_64-linux.default = (nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.appliance
        ./profiles/server/configuration.nix
        {
          release = "1";
          updateUrl = "https://github.com/peter-marshall5/nixos-appliance/releases/latest/download/";
        }
      ];
    }).config.system.build.release;
  };
}
