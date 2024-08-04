{
  description = "CLI to watch Movies/TV Shows from the terminal";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default-linux";
  };

  outputs = {
    self,
    nixpkgs,
    systems,
  }: let
    inherit (nixpkgs) lib;
    eachSystem = lib.genAttrs (import systems);
    pkgsFor = eachSystem (system:
      import nixpkgs {
        config = {};
        localSystem = system;
        overlays = [];
      });
  in {
    packages = eachSystem (system: {
      lobster = pkgsFor.${system}.callPackage ./default.nix {};
      default = self.packages.${system}.lobster;
    });
  };
}

