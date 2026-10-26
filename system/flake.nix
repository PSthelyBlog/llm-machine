{
  description = "llm-machine: an operating system that Claude Code builds and maintains";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      lib = nixpkgs.lib;

      # Every directory in hosts/ is a machine; its name is the hostname.
      hosts = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts));

      mkSystem =
        name:
        lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            ./core
            ./features
            ./hosts/${name}
            {
              networking.hostName = lib.mkDefault name;
              system.configurationRevision = self.rev or self.dirtyRev or null;
            }
          ];
        };
    in
    {
      nixosConfigurations = lib.genAttrs hosts mkSystem;
      nixosModules.core = ./core;
    };
}
