# SPDX-License-Identifier: GPL-3.0-or-later
{
  description = "gamesteam — universal, GPU-aware Steam/Proton launch wrapper for Linux";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      # The flake's own package/overlay outputs are built for these systems.
      # The NixOS module is architecture-independent (it builds against the
      # consumer's pkgs), so it works everywhere regardless of this list.
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # NixOS module. Import as inputs.gamesteam.nixosModules.default, then set
      #   programs.gamesteam.enable = true;
      nixosModules.gamesteam = ./module.nix;
      nixosModules.default = self.nixosModules.gamesteam;

      # Standalone package: `nix run github:grenudi/gamesteam -- --help`,
      # `nix profile install github:grenudi/gamesteam`, or via the overlay.
      packages = forAllSystems (pkgs: rec {
        gamesteam = pkgs.callPackage ./package.nix { };
        default = gamesteam;
      });

      # `pkgs.gamesteam` once you add this to nixpkgs.overlays.
      overlays.default = final: _prev: {
        gamesteam = final.callPackage ./package.nix { };
      };

      # `nix flake check` builds the wrapper, which runs shellcheck on the script.
      checks = forAllSystems (pkgs: {
        gamesteam = pkgs.callPackage ./package.nix { };
      });

      formatter = forAllSystems (pkgs: pkgs.nixpkgs-fmt);
    };
}
