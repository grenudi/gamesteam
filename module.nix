# SPDX-License-Identifier: GPL-3.0-or-later
#
# module.nix — NixOS module for gamesteam.
#
# Builds gamesteam against the *consuming* system's pkgs (via callPackage), so
# it works on any architecture and needs no nixpkgs.follows. It also enables the
# daemons/capabilities the wrapper depends on — installing the binaries alone
# would leave gamemode and gamescope's --rt silently doing nothing.
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.gamesteam;
in
{
  options.programs.gamesteam = {
    enable = lib.mkEnableOption "gamesteam, a universal GPU-aware Steam/Proton launch wrapper";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The gamesteam package to install.";
    };

    gamescope.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable {option}`programs.gamescope` with `capSysNice` so gamesteam's
        `--rt` realtime scheduling is permitted. Disable if you configure
        gamescope yourself.
      '';
    };

    gamemode.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable {option}`programs.gamemode` (daemon + polkit rules). Without it,
        `gamemoderun` is inert. Disable if gamemode is enabled elsewhere.
      '';
    };

    powerProfilesDaemon.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Enable {option}`services.power-profiles-daemon` so gamesteam can switch
        to the performance profile for the session (restored on exit). Set to
        `false` if you use TLP — the two conflict. gamesteam tolerates the daemon
        being absent and simply skips the profile switch.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    { environment.systemPackages = [ cfg.package ]; }

    (lib.mkIf cfg.gamescope.enable {
      programs.gamescope = {
        enable = true;
        capSysNice = true;
      };
    })

    (lib.mkIf cfg.gamemode.enable {
      programs.gamemode.enable = true;
    })

    (lib.mkIf cfg.powerProfilesDaemon.enable {
      services.power-profiles-daemon.enable = true;
    })
  ]);
}
