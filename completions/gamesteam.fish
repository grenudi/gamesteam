# SPDX-License-Identifier: GPL-3.0-or-later
# fish completion for gamesteam

# GPU
complete -c gamesteam -s g -l graphics -d 'GPU to render on' -x -a 'auto discrete integrated nvidia amd intel integrated-intel integrated-amd'
complete -c gamesteam -l force-discrete   -d 'force the discrete GPU'
complete -c gamesteam -l force-integrated -d 'force the integrated GPU'
complete -c gamesteam -l list-gpus        -d 'list detected GPUs and exit'

# gamescope
complete -c gamesteam -l gamescope     -d 'run inside a native-resolution gamescope'
complete -c gamesteam -l no-gamescope  -d 'do not use gamescope'
complete -c gamesteam -l res           -d 'gamescope output resolution (WxH)' -x
complete -c gamesteam -l refresh       -d 'refresh-rate cap (Hz)' -x
complete -c gamesteam -l render-scale  -d 'internal render scale 0.1-1.0' -x
complete -c gamesteam -l native        -d 'render at output resolution, no upscaling'
complete -c gamesteam -l fsr           -d 'force FSR upscaling on'
complete -c gamesteam -l no-fsr        -d 'force FSR upscaling off'
complete -c gamesteam -l hdr           -d 'enable HDR output'

# system
complete -c gamesteam -l gamemode          -d 'wrap in gamemoderun'
complete -c gamesteam -l no-gamemode       -d 'do not use gamemode'
complete -c gamesteam -l power-profile     -d 'power profile for the session' -x -a 'performance balanced power-saver'
complete -c gamesteam -l no-power-profile  -d 'leave the power profile unchanged'
complete -c gamesteam -l hud               -d 'enable the MangoHud overlay'
complete -c gamesteam -l no-hud            -d 'disable the MangoHud overlay'

# tuning
complete -c gamesteam -l cachyos     -d 'apply CachyOS-Proton tuning'
complete -c gamesteam -l no-cachyos  -d 'disable CachyOS tuning'

# general
complete -c gamesteam -s n -l dry-run  -d 'print the plan and exit'
complete -c gamesteam -s v -l verbose  -d 'explain decisions on stderr'
complete -c gamesteam -s q -l quiet    -d 'suppress warnings'
complete -c gamesteam -s h -l help     -d 'show help and exit'
complete -c gamesteam -s V -l version  -d 'show version and exit'
