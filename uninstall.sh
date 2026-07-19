#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Remove gamesteam (script, man page, and bash/zsh/fish completions) installed
# by install.sh, from both user and system locations. Runtime dependencies
# (gamescope, gamemode, mangohud, power-profiles-daemon) are left installed.
#
# Run from a clone (./uninstall.sh) or straight from the web:
#     curl -fsSL https://raw.githubusercontent.com/grenudi/gamesteam/main/uninstall.sh | sh
set -eu

NAME="gamesteam"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
FISHCONF="${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions"

msg() { printf '%s\n' "$*"; }

# All locations install.sh could have written to (system + user), one per line.
candidates() {
    command -v "$NAME" 2>/dev/null || true
    printf '%s\n' \
        "/usr/local/bin/$NAME" \
        "/usr/bin/$NAME" \
        "$HOME/.local/bin/$NAME" \
        "$HOME/bin/$NAME" \
        "/usr/local/share/man/man1/$NAME.1" \
        "/usr/share/man/man1/$NAME.1" \
        "$DATA/man/man1/$NAME.1" \
        "/usr/local/share/bash-completion/completions/$NAME" \
        "/usr/share/bash-completion/completions/$NAME" \
        "$DATA/bash-completion/completions/$NAME" \
        "/usr/local/share/zsh/site-functions/_$NAME" \
        "/usr/share/zsh/site-functions/_$NAME" \
        "$DATA/zsh/site-functions/_$NAME" \
        "/usr/local/share/fish/vendor_completions.d/$NAME.fish" \
        "/usr/share/fish/vendor_completions.d/$NAME.fish" \
        "$FISHCONF/$NAME.fish"
}

# De-duplicate into a temp file, then iterate in the current shell (so the
# counter survives and word-splitting is avoided).
list="$(mktemp)"
trap 'rm -f "$list"' EXIT INT TERM
candidates | awk 'NF && !seen[$0]++' > "$list"

found=0
while IFS= read -r p; do
    [ -e "$p" ] || continue
    d="$(dirname -- "$p")"
    if [ -w "$d" ]; then
        if rm -f "$p"; then msg "removed  $p"; found=1; fi
    else
        if command -v sudo >/dev/null 2>&1; then
            msg "removing $p (needs sudo)"
            if sudo rm -f "$p"; then msg "removed  $p"; found=1; fi
        else
            msg "skipped  $p (need sudo or write access to $d)"
        fi
    fi
done < "$list"

if [ "$found" = 0 ]; then
    msg "$NAME not found in any known location. Nothing to remove."
else
    msg ""
    msg "$NAME uninstalled. Runtime dependencies were left installed — remove"
    msg "them with your package manager if you no longer want them."
fi
