#compdef gamesteam
# SPDX-License-Identifier: GPL-3.0-or-later
# zsh completion for gamesteam

_gamesteam() {
    _arguments -s -S \
        '(-g --graphics)'{-g,--graphics}'[GPU to render on]:target:(auto discrete integrated nvidia amd intel integrated-intel integrated-amd)' \
        '--force-discrete[force the discrete GPU]' \
        '--force-integrated[force the integrated GPU]' \
        '--list-gpus[list detected GPUs and exit]' \
        '--gamescope[run inside a native-resolution gamescope]' \
        '--no-gamescope[do not use gamescope]' \
        '--res[gamescope output resolution]:WxH:' \
        '--refresh[refresh-rate cap]:Hz:' \
        '--render-scale[internal render scale 0.1-1.0]:factor:' \
        '--native[render at output resolution, no upscaling]' \
        '--fsr[force FSR upscaling on]' \
        '--no-fsr[force FSR upscaling off]' \
        '--hdr[enable HDR output]' \
        '--gamemode[wrap in gamemoderun]' \
        '--no-gamemode[do not use gamemode]' \
        '--power-profile[power profile for the session]:profile:(performance balanced power-saver)' \
        '--no-power-profile[leave the power profile unchanged]' \
        '--hud[enable the MangoHud overlay]' \
        '--no-hud[disable the MangoHud overlay]' \
        '--cachyos[apply CachyOS-Proton tuning]' \
        '--no-cachyos[disable CachyOS tuning]' \
        '(-n --dry-run)'{-n,--dry-run}'[print the plan and exit]' \
        '(-v --verbose)'{-v,--verbose}'[explain decisions on stderr]' \
        '(-q --quiet)'{-q,--quiet}'[suppress warnings]' \
        '(-h --help)'{-h,--help}'[show help and exit]' \
        '(-V --version)'{-V,--version}'[show version and exit]' \
        '*::command:_command_names -e'
}

_gamesteam "$@"
