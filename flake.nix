{
  description = "CLI to watch Movies/TV Shows from the terminal";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (system:
      with import nixpkgs {system = "${system}";}; let
        pkgs = import nixpkgs {inherit system;};
      in {
        packages.lobster = callPackage ./default.nix {};
        packages.default = self.packages.${system}.lobster;
      });
}
