#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
#
# gamesteam installer for non-NixOS Linux distributions. Installs the script,
# man page, and shell completions (bash/zsh/fish), and offers to install the
# optional runtime dependencies with your package manager.
#
# Run from a clone (./install.sh) or straight from the web:
#     curl -fsSL https://raw.githubusercontent.com/grenudi/gamesteam/main/install.sh | sh
#     curl -fsSL .../install.sh | sh -s -- --user      # no sudo, into ~/.local
#
# On NixOS this refuses to run — use the flake module instead
# (programs.gamesteam.enable = true).
set -eu

REPO_RAW="https://raw.githubusercontent.com/grenudi/gamesteam/main"
NAME="gamesteam"
PREFIX="${PREFIX:-/usr/local}"
USER_INSTALL=0
DO_DEPS=1

usage() {
    cat <<EOF
gamesteam installer

usage: install.sh [--user] [--prefix DIR] [--no-deps] [-h|--help]

  --user        install into ~/.local (no sudo) instead of /usr/local
  --prefix DIR  install prefix for a system install (default: /usr/local)
  --no-deps     do not check for or offer to install dependencies
  -h, --help    this help
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --user)     USER_INSTALL=1; shift ;;
        --prefix)   PREFIX="${2:?--prefix needs a directory}"; shift 2 ;;
        --prefix=*) PREFIX="${1#*=}"; shift ;;
        --no-deps)  DO_DEPS=0; shift ;;
        -h|--help)  usage; exit 0 ;;
        *)          echo "unknown argument: $1 (see --help)" >&2; exit 1 ;;
    esac
done

msg()  { printf '%s\n' "$*"; }
err()  { printf '%s: error: %s\n' "$NAME" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# Ask on the terminal, not the piped stdin (so it works under curl | sh).
ask() {
    printf '%s [y/N] ' "$1"
    if read -r _a </dev/tty 2>/dev/null; then
        case "$_a" in y|Y|yes|YES) return 0 ;; esac
    fi
    return 1
}

# --- refuse on NixOS -------------------------------------------------------
if [ -r /etc/os-release ] && grep -qiE '^ID=nixos' /etc/os-release; then
    err "this is NixOS — use the flake module instead: programs.gamesteam.enable = true (see the README)"
fi

# --- target directories ----------------------------------------------------
if [ "$USER_INSTALL" = 1 ]; then
    DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
    BIN="$HOME/.local/bin"
    MAN="$DATA/man/man1"
    BASHC="$DATA/bash-completion/completions"
    ZSHC="$DATA/zsh/site-functions"
    FISHC="${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions"
else
    BIN="$PREFIX/bin"
    MAN="$PREFIX/share/man/man1"
    BASHC="$PREFIX/share/bash-completion/completions"
    ZSHC="$PREFIX/share/zsh/site-functions"
    FISHC="$PREFIX/share/fish/vendor_completions.d"
fi

# --- obtain a repo file: local (clone) or download -------------------------
SELF_DIR=""
if _p="$(CDPATH='' cd -- "$(dirname -- "$0")" 2>/dev/null && pwd)"; then SELF_DIR="$_p"; fi
WORK=""
cleanup() { [ -n "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

obtain() { # obtain RELPATH -> echo local path, or empty + return 1
    _rp="$1"
    if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/$_rp" ]; then
        printf '%s\n' "$SELF_DIR/$_rp"; return 0
    fi
    [ -n "$WORK" ] || WORK="$(mktemp -d)" || err "mktemp failed"
    _out="$WORK/$(basename "$_rp")"
    if have curl; then
        curl -fsSL "$REPO_RAW/$_rp" -o "$_out" 2>/dev/null && { printf '%s\n' "$_out"; return 0; }
    elif have wget; then
        wget -qO "$_out" "$REPO_RAW/$_rp" 2>/dev/null && { printf '%s\n' "$_out"; return 0; }
    fi
    return 1
}

# --- install a file, using sudo only when needed ---------------------------
install_file() { # install_file SRC DEST MODE
    _src="$1"; _dest="$2"; _mode="$3"; _dir="$(dirname "$_dest")"
    if [ ! -d "$_dir" ]; then
        if ! mkdir -p "$_dir" 2>/dev/null; then
            have sudo || return 1
            sudo mkdir -p "$_dir" || return 1
        fi
    fi
    if [ -w "$_dir" ]; then
        cp "$_src" "$_dest" && chmod "$_mode" "$_dest"
    else
        have sudo || { msg "  need sudo or write access to $_dir"; return 1; }
        sudo cp "$_src" "$_dest" && sudo chmod "$_mode" "$_dest"
    fi
}

# --- dependency check / prompt ---------------------------------------------
pkg_for() { # pkg_for TOOL MANAGER -> package name for that manager
    case "$2:$1" in
        xbps-install:mangohud)        echo "MangoHud" ;;
        emerge:gamescope)             echo "gui-wm/gamescope" ;;
        emerge:gamemode)              echo "games-util/gamemode" ;;
        emerge:mangohud)              echo "games-util/mangohud" ;;
        emerge:power-profiles-daemon) echo "sys-power/power-profiles-daemon" ;;
        *)                            echo "$1" ;;
    esac
}

if [ "$DO_DEPS" = 1 ]; then
    missing=""
    have gamescope        || missing="$missing gamescope"
    have gamemoderun      || missing="$missing gamemode"
    have mangohud         || missing="$missing mangohud"
    have powerprofilesctl || missing="$missing power-profiles-daemon"
    missing="${missing# }"

    if [ -n "$missing" ]; then
        MGR=""
        for m in pacman apt-get dnf zypper xbps-install emerge; do
            if have "$m"; then MGR="$m"; break; fi
        done
        pkgs=""
        for tool in $missing; do pkgs="$pkgs $(pkg_for "$tool" "$MGR")"; done
        pkgs="${pkgs# }"
        case "$MGR" in
            pacman)       CMD="sudo pacman -S --needed $pkgs" ;;
            apt-get)      CMD="sudo apt-get update && sudo apt-get install -y $pkgs" ;;
            dnf)          CMD="sudo dnf install -y $pkgs" ;;
            zypper)       CMD="sudo zypper install -y $pkgs" ;;
            xbps-install) CMD="sudo xbps-install -Sy $pkgs" ;;
            emerge)       CMD="sudo emerge --ask $pkgs" ;;
            *)            CMD="" ;;
        esac

        msg ""
        msg "Optional tools not found: $missing"
        msg "(all are optional — gamesteam runs without them; gamescope is opt-in via --gamescope)"
        if [ -n "$CMD" ]; then
            msg ""
            msg "Suggested command:  $CMD"
            if ask "Install these now?"; then
                sh -c "$CMD" || msg "dependency install failed or was declined; continuing"
            else
                msg "Skipping dependency install."
            fi
        else
            msg "Could not detect a supported package manager — install manually: $missing"
        fi
    fi
fi

# --- install the artifacts -------------------------------------------------
msg ""
src="$(obtain "$NAME.sh")" || err "could not obtain $NAME.sh (need curl or wget, or run from a clone)"
install_file "$src" "$BIN/$NAME" 0755 || err "failed to install $BIN/$NAME"
msg "installed  $BIN/$NAME"

if src="$(obtain "$NAME.1")"; then
    if install_file "$src" "$MAN/$NAME.1" 0644; then msg "installed  $MAN/$NAME.1"; else msg "skipped    man page"; fi
else
    msg "skipped    man page (not obtained)"
fi

if src="$(obtain "completions/$NAME.bash")"; then
    if install_file "$src" "$BASHC/$NAME" 0644; then msg "installed  $BASHC/$NAME (bash)"; else msg "skipped    bash completion"; fi
fi
if src="$(obtain "completions/$NAME.zsh")"; then
    if install_file "$src" "$ZSHC/_$NAME" 0644; then msg "installed  $ZSHC/_$NAME (zsh)"; else msg "skipped    zsh completion"; fi
fi
if src="$(obtain "completions/$NAME.fish")"; then
    if install_file "$src" "$FISHC/$NAME.fish" 0644; then msg "installed  $FISHC/$NAME.fish (fish)"; else msg "skipped    fish completion"; fi
fi

# --- post-install notes ----------------------------------------------------
case ":$PATH:" in
    *":$BIN:"*) : ;;
    *)
        msg ""
        msg "NOTE: $BIN is not in your PATH. Add it, e.g.:"
        msg "    echo 'export PATH=\"$BIN:\$PATH\"' >> ~/.profile   # then re-login"
        ;;
esac
if [ "$USER_INSTALL" = 1 ]; then
    msg ""
    msg "For zsh completion, ensure this is in your fpath before compinit:"
    msg "    fpath=($ZSHC \$fpath)"
fi
msg ""
msg "Done. Set your Steam launch options to:   $NAME %command%"
msg "Docs:   man $NAME      Quick check:   $NAME -n -v -- /bin/true"
