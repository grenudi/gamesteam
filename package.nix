# SPDX-License-Identifier: GPL-3.0-or-later
#
# package.nix — builds the gamesteam wrapper from a package set.
# callPackage-compatible: `pkgs.callPackage ./package.nix { }`.
#
# The script (./gamesteam.sh) is installed verbatim — it stays a complete,
# standalone, distro-agnostic program. We shellcheck it at build time, pin the
# tools it calls onto its PATH, and ship the man page + shell completions.
{
  lib,
  runCommandLocal,
  makeWrapper,
  shellcheck,
  gamemode,
  mangohud,
  power-profiles-daemon,
  coreutils,
  gawk,
  gnugrep,
  gnused,
  # Override these to vendor your own copies.
  src ? ./gamesteam.sh,
  man ? ./gamesteam.1,
  bashCompletion ? ./completions/gamesteam.bash,
  zshCompletion ? ./completions/gamesteam.zsh,
  fishCompletion ? ./completions/gamesteam.fish,
}:

runCommandLocal "gamesteam"
{
  nativeBuildInputs = [ makeWrapper shellcheck ];
  meta = {
    description = "Universal, GPU-aware Steam/Proton launch wrapper (gamemode + power profile; optional gamescope)";
    homepage = "https://github.com/grenudi/gamesteam";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "gamesteam";
  };
}
  ''
    install -Dm755 ${src} $out/bin/gamesteam

    # Fail the build on any shellcheck regression (default profile).
    shellcheck $out/bin/gamesteam
    shellcheck ${bashCompletion}

    # Man page and shell completions — NixOS aggregates these directories from
    # every package in environment.systemPackages, so they "just work".
    install -Dm644 ${man}            $out/share/man/man1/gamesteam.1
    install -Dm644 ${bashCompletion} $out/share/bash-completion/completions/gamesteam
    install -Dm644 ${zshCompletion}  $out/share/zsh/site-functions/_gamesteam
    install -Dm644 ${fishCompletion} $out/share/fish/vendor_completions.d/gamesteam.fish

    # Pin the tools gamesteam calls onto its PATH — but deliberately NOT
    # gamescope: makeWrapper --prefix prepends to PATH, which would shadow the
    # CAP_SYS_NICE wrapper installed by programs.gamescope and break --rt.
    # gamescope is resolved from the ambient system PATH instead.
    wrapProgram $out/bin/gamesteam \
      --prefix PATH : ${lib.makeBinPath [
        gamemode
        mangohud
        power-profiles-daemon
        coreutils
        gawk
        gnugrep
        gnused
      ]}
  ''
