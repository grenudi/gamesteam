# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# bash completion for gamesteam

_gamesteam() {
    local cur prev opts graphics profiles
    cur=${COMP_WORDS[COMP_CWORD]}
    prev=${COMP_WORDS[COMP_CWORD-1]}

    opts="-g --graphics --force-discrete --force-integrated --list-gpus \
--gamescope --no-gamescope --res --refresh --render-scale --native --fsr --no-fsr --hdr \
--gamemode --no-gamemode --power-profile --no-power-profile --hud --no-hud \
--cachyos --no-cachyos -n --dry-run -v --verbose -q --quiet -h --help -V --version"
    graphics="auto discrete integrated nvidia amd intel integrated-intel integrated-amd"
    profiles="performance balanced power-saver"

    case $prev in
        -g|--graphics)
            mapfile -t COMPREPLY < <(compgen -W "$graphics" -- "$cur"); return ;;
        --power-profile)
            mapfile -t COMPREPLY < <(compgen -W "$profiles" -- "$cur"); return ;;
        --res|--refresh|--render-scale)
            return ;;
    esac

    if [[ $cur == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$opts" -- "$cur")
    else
        # after the options comes the game command; complete commands then files
        mapfile -t COMPREPLY < <(compgen -c -- "$cur")
    fi
}
complete -F _gamesteam gamesteam
