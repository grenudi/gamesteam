{
  description = "NixOS system configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # CachyOS kernel with BORE scheduler, NTSync, FUTEX2, LTO, and more.
    # Use the /release branch for stable, tested builds.
    # Do NOT add nixpkgs.follows — the repo pins its own nixpkgs to match its
    # binary-cache hashes. Overriding it causes cache misses and local compiles.
    # https://github.com/xddxdd/nix-cachyos-kernel
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";

    # gamesteam — universal, GPU-aware Steam/Proton launch wrapper.
    # Following nixpkgs IS safe here (unlike the cachyos kernel above): the NixOS
    # module builds gamesteam against THIS system's pkgs, so the follows only
    # affects gamesteam's own standalone package outputs, which we don't use.
    gamesteam.url = "github:grenudi/gamesteam";
    gamesteam.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, nix-cachyos-kernel, gamesteam, ... }:
    let
      constants = import ./constants.nix;
    in {
      nixosConfigurations.${constants.hostname} = nixpkgs.lib.nixosSystem {
        system = constants.system;

        specialArgs = {
          inherit constants;
          # All CachyOS kernel variants for this system, keyed by variant name.
          # Pass to cachyos-optimizations via cachyosOptimizations.kernelPackage.
          # Available variants: linuxPackages-cachyos-bore, linuxPackages-cachyos-latest,
          # linuxPackages-cachyos-lts, linuxPackages-cachyos-bore-lto, etc.
          # Full list: nix flake show github:xddxdd/nix-cachyos-kernel/release
          cachyosKernels = nix-cachyos-kernel.legacyPackages.${constants.system};
        };

        modules = [
          ./nixos/configuration.nix

          # gamesteam NixOS module. Enable it in your configuration with:
          #     programs.gamesteam.enable = true;
          gamesteam.nixosModules.default
        ];
      };
    };
}
