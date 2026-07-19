{
  description = "gamesteam dev shell with a fully isolated, pinned VSCodium IDE";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    nix-vscode-extensions.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix-vscode-extensions }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      exts = nix-vscode-extensions.extensions.${system};

      # VSCodium with exactly this project's extensions baked in (immutable, from
      # the Nix store). If any attribute below is missing on open-vsx, swap that
      # single line to exts.vscode-marketplace.<publisher>.<name>.
      ide = pkgs.vscode-with-extensions.override {
        vscode = pkgs.vscodium;
        vscodeExtensions = [
          exts.open-vsx.jnoortheen.nix-ide            # Nix language + formatting
          exts.open-vsx.mads-hartmann.bash-ide-vscode # Bash LSP (hover/goto/complete)
          exts.open-vsx.timonwong.shellcheck          # ShellCheck diagnostics
          exts.open-vsx.foxundermoon.shell-format     # shfmt formatting
          exts.open-vsx.davidanson.vscode-markdownlint # README linting
          exts.open-vsx.mkhl.direnv                   # picks up .envrc in-editor
        ];
      };

      # Rewritten on every launch so the store paths below stay fresh.
      settings = pkgs.writeText "settings.json" (builtins.toJSON {
        "telemetry.telemetryLevel" = "off";
        "update.mode" = "none";
        "extensions.autoCheckUpdates" = false;
        "security.workspace.trust.enabled" = false;

        # Nix — nil LSP, formatting via nixpkgs-fmt (the project's formatter).
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "${pkgs.nil}/bin/nil";
        "nix.serverSettings" = {
          nil.formatting.command = [ "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt" ];
        };

        # Shell — shellcheck + shfmt, pinned to the same binaries the repo uses.
        "shellcheck.executablePath" = "${pkgs.shellcheck}/bin/shellcheck";
        "shellcheck.customArgs" = [ "-x" ];
        "shellformat.path" = "${pkgs.shfmt}/bin/shfmt";
        "shellformat.flag" = "-i 4 -ci";
        "bashIde.shellcheckPath" = "${pkgs.shellcheck}/bin/shellcheck";

        # Format-on-save for Nix (deterministic); left off for shell so the
        # hand-tuned scripts aren't reflowed unexpectedly (Format Document still works).
        "[nix]" = {
          "editor.defaultFormatter" = "jnoortheen.nix-ide";
          "editor.formatOnSave" = true;
        };
        "[shellscript]" = {
          "editor.defaultFormatter" = "foxundermoon.shell-format";
          "editor.formatOnSave" = false;
        };

        "files.associations" = {
          ".envrc" = "shellscript";
          "_envrc" = "shellscript";
          "*.zsh" = "shellscript";
        };
      });

      # Isolated launcher: per-project user-data-dir, so this editor shares no
      # state with your global VSCodium and vice versa.
      launch = ''
        set -eu
        data="$PWD/.ide/user-data"
        mkdir -p "$data/User"
        install -m600 ${settings} "$data/User/settings.json"
        exec ${ide}/bin/codium --user-data-dir="$data" "$@"
      '';
      code = pkgs.writeShellScriptBin "code" launch;
      codeDev = pkgs.writeShellScriptBin "code-dev" launch;
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          # Nix tooling
          nil
          nixpkgs-fmt
          # Shell tooling
          shellcheck
          shfmt
          # Docs + completion testing (this repo ships a man page + zsh/fish completions)
          mandoc
          zsh
          fish
          # The isolated editor — two names, same IDE
          code
          codeDev
        ];

        shellHook = ''
          echo "🎮 gamesteam dev shell — run 'code .' or 'code-dev .' for the isolated IDE"
        '';
      };
    };
}
