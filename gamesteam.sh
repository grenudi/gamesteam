#!/usr/bin/env bash
#
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 YOUR NAME <idunerg@gmail.com>
#
# gamesteam — universal, GPU-aware Steam/Proton launch wrapper
# ===========================================================================
# Applies GPU- and system-tuned environment, runs a game under gamemode, and
# switches the system to a performance power profile for the session (restored
# on exit). For integrated GPUs it also wraps the game in a native-resolution
# gamescope compositor with FSR upscaling (auto; discrete GPUs render native).
# Everything external is probed at runtime, so the same script runs on any
# Linux — it is not NixOS-specific.
#
# Design notes
#   * strict mode is nounset + pipefail, deliberately NOT errexit: the script
#     probes a lot of optional hardware/tools and must not abort on an expected
#     non-zero probe. Anything that must succeed is guarded with || die/|| warn.
#   * GPUs are read from /sys (no lspci). Selection prefers the discrete GPU and
#     applies vendor-correct routing: NVIDIA PRIME offload, or Mesa DRI_PRIME +
#     MESA_VK_DEVICE_SELECT for AMD/Intel, plus gamescope --prefer-vk-device.
#   * Defaults live in two optional config files (see FILES in --help); flags
#     always win. New behaviour slots in as one option + one branch.
#
# Steam → Properties → Launch Options (or global compatibility options):
#     gamesteam %command%
# ===========================================================================
set -uo pipefail

readonly VERSION="1.0.0"
readonly SELF="${0##*/}"

# --------------------------------------------------------------------------- #
# Defaults (overridable by config files, then by flags)
# --------------------------------------------------------------------------- #
: "${GAMESTEAM_SYSFS:=/sys}"          # sysfs root; override to unit-test detection

GRAPHICS="auto"        # auto|discrete|integrated|nvidia|amd|intel|integrated-intel|integrated-amd
USE_GAMESCOPE="auto"  # auto|on|off  (auto = on for integrated GPUs, off for discrete)
USE_GAMEMODE="auto"    # auto|on|off
DO_POWER_PROFILE=1     # 1|0
POWER_PROFILE="performance"
WANT_HUD="${MANGOHUD:-0}"   # 0|1
CACHYOS="auto"         # auto|on|off
RES=""                 # WxH override
REFRESH=""             # Hz override
RENDER_SCALE=""        # 0.1..1.0 (empty => per-GPU default)
FORCE_FSR="auto"       # auto|on|off
WANT_HDR=0             # 0|1
DRYRUN=0
VERBOSE=0
QUIET=0
LIST_ONLY=0
COMMAND=()

# --------------------------------------------------------------------------- #
# Small helpers
# --------------------------------------------------------------------------- #
have() { command -v "$1" >/dev/null 2>&1; }
log()  { if [ "$VERBOSE" = 1 ]; then printf '%s: %s\n' "$SELF" "$*" >&2; fi; }
warn() { if [ "$QUIET" != 1 ]; then printf '%s: warning: %s\n' "$SELF" "$*" >&2; fi; }
die()  { printf '%s: error: %s\n' "$SELF" "$*" >&2; exit 1; }

vendor_name() {
    case "$1" in
        0x10de) echo NVIDIA ;;
        0x1002) echo AMD ;;
        0x8086) echo Intel ;;
        *)      echo "vendor $1" ;;
    esac
}

is_uint() { case "${1:-}" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }

valid_res() {
    case "$1" in *[!0-9x]* | *x*x* | x* | *x) return 1 ;; *x*) : ;; *) return 1 ;; esac
    is_uint "${1%x*}" && is_uint "${1#*x}"
}

valid_scale() { awk -v s="$1" 'BEGIN { exit !(s + 0 > 0 && s + 0 <= 1.0) }' 2>/dev/null; }

# --------------------------------------------------------------------------- #
# Config files: /etc/gamesteam/config then $XDG_CONFIG_HOME/gamesteam/config.
# Plain shell assigning the variables above, e.g.  GRAPHICS=nvidia
# --------------------------------------------------------------------------- #
load_config() {
    local f
    for f in /etc/gamesteam/config "${XDG_CONFIG_HOME:-$HOME/.config}/gamesteam/config"; do
        if [ -r "$f" ]; then
            # shellcheck source=/dev/null
            . "$f" || warn "could not read config file: $f"
        fi
    done
}

# --------------------------------------------------------------------------- #
# Usage
# --------------------------------------------------------------------------- #
usage() {
    cat <<EOF
$SELF $VERSION — universal, GPU-aware Steam/Proton launch wrapper

USAGE
    $SELF [options] %command%            (in Steam launch options)
    $SELF [options] -- <command>
    $SELF --list-gpus | --help | --version

The default (no options) tunes the environment for the discrete GPU, runs the
game under gamemode, and sets the performance power profile for the session.
gamescope is opt-in.

GPU
    -g, --graphics <target>   GPU to render on (default: auto). One of:
                                auto  discrete  integrated  nvidia  amd  intel
                                integrated-intel  integrated-amd
        --force-discrete      alias for -g discrete
        --force-integrated    alias for -g integrated
        --list-gpus           list detected GPUs and exit

GAMESCOPE (auto: on for integrated GPUs, off for discrete; the options below
           apply only when gamescope is active)
        --gamescope           always run inside a native-resolution gamescope
        --no-gamescope        never use gamescope
        --res <WxH>           output resolution (default: auto-detect native)
        --refresh <Hz>        refresh-rate cap (default: display native)
        --render-scale <f>    internal render scale 0.1..1.0
                              (default: 1.0 discrete, 0.75 integrated)
        --native              render at output resolution (no upscaling)
        --fsr | --no-fsr      force FSR upscaling on/off
        --hdr                 enable HDR output

SYSTEM
        --gamemode            wrap in gamemoderun (default: on when available)
        --no-gamemode         do not use gamemode
        --power-profile <p>   power profile for the session (default: performance)
        --no-power-profile    leave the power profile unchanged
        --hud | --no-hud      MangoHud overlay (default: off, or MANGOHUD=1)

TUNING
        --cachyos             apply CachyOS-Proton tuning
        --no-cachyos          disable it (default: auto-detect)

GENERAL
    -n, --dry-run             print the resolved plan and exit; run nothing
    -v, --verbose             explain detection/decisions on stderr
    -q, --quiet               suppress warnings
    -h, --help                show this help and exit
    -V, --version             show version and exit

EXAMPLES
    $SELF %command%                         auto, discrete, gamemode
    $SELF -g nvidia --gamescope %command%   force NVIDIA, wrap in gamescope
    $SELF --force-integrated --gamescope --render-scale 0.7 %command%
    $SELF --no-power-profile --no-gamemode %command%
    $SELF -n -v -- /bin/true                inspect the plan for this machine

ENVIRONMENT
    MANGOHUD=1                start with the overlay (same as --hud)
    GAMESTEAM_SYSFS=<dir>     sysfs root to read GPUs/displays from (testing)

FILES
    /etc/gamesteam/config                       system defaults
    \${XDG_CONFIG_HOME:-~/.config}/gamesteam/config   user defaults
    Both are shell fragments setting the variables above; flags override them.

NOTES
  * PROTON_*/VKD3D_* tuning needs Proton-CachyOS or Proton-GE; stock Valve
    Proton ignores the CachyOS-specific variables harmlessly.
  * CachyOS mode auto-detects via /etc/os-release, a *-cachyos kernel, or a
    game-performance binary — so it also fires on NixOS running that kernel.
  * gamescope --adaptive-sync (VRR) requires the compositor's VRR to be enabled
    when nested; NVIDIA + gamescope wants a recent driver (>= 555).
  * Intel Arc (discrete) is not auto-distinguished from an Intel iGPU; use
    -g intel to select it regardless.
EOF
}

# --------------------------------------------------------------------------- #
# Argument parsing — leading options; first non-option token begins %command%.
# --------------------------------------------------------------------------- #
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            # GPU
            -g | --graphics)      [ $# -ge 2 ] || die "$1 needs an argument"; GRAPHICS="$2"; shift 2 ;;
            --graphics=*)         GRAPHICS="${1#*=}"; shift ;;
            --force-discrete)     GRAPHICS="discrete"; shift ;;
            --force-integrated)   GRAPHICS="integrated"; shift ;;
            --list-gpus)          LIST_ONLY=1; shift ;;
            # gamescope
            --gamescope)          USE_GAMESCOPE="on"; shift ;;
            --no-gamescope)       USE_GAMESCOPE="off"; shift ;;
            --res)                [ $# -ge 2 ] || die "--res needs WxH"; RES="$2"; shift 2 ;;
            --res=*)              RES="${1#*=}"; shift ;;
            --refresh)            [ $# -ge 2 ] || die "--refresh needs Hz"; REFRESH="$2"; shift 2 ;;
            --refresh=*)          REFRESH="${1#*=}"; shift ;;
            --render-scale)       [ $# -ge 2 ] || die "--render-scale needs a value"; RENDER_SCALE="$2"; shift 2 ;;
            --render-scale=*)     RENDER_SCALE="${1#*=}"; shift ;;
            --native)             RENDER_SCALE="1.0"; FORCE_FSR="off"; shift ;;
            --fsr)                FORCE_FSR="on"; shift ;;
            --no-fsr)             FORCE_FSR="off"; shift ;;
            --hdr)                WANT_HDR=1; shift ;;
            # system
            --gamemode)           USE_GAMEMODE="on"; shift ;;
            --no-gamemode)        USE_GAMEMODE="off"; shift ;;
            --power-profile)      [ $# -ge 2 ] || die "--power-profile needs a name"; POWER_PROFILE="$2"; DO_POWER_PROFILE=1; shift 2 ;;
            --power-profile=*)    POWER_PROFILE="${1#*=}"; DO_POWER_PROFILE=1; shift ;;
            --no-power-profile)   DO_POWER_PROFILE=0; shift ;;
            --hud)                WANT_HUD=1; shift ;;
            --no-hud)             WANT_HUD=0; shift ;;
            # tuning
            --cachyos)            CACHYOS="on"; shift ;;
            --no-cachyos)         CACHYOS="off"; shift ;;
            # general
            -n | --dry-run)       DRYRUN=1; shift ;;
            -v | --verbose)       VERBOSE=1; shift ;;
            -q | --quiet)         QUIET=1; shift ;;
            -h | --help)          usage; exit 0 ;;
            -V | --version)       echo "$SELF $VERSION"; exit 0 ;;
            --)                   shift; COMMAND=("$@"); break ;;
            -*)                   die "unknown option: $1 (try --help)" ;;
            *)                    COMMAND=("$@"); break ;;
        esac
    done
}

validate_opts() {
    case "$GRAPHICS" in
        auto | discrete | integrated | nvidia | amd | intel | integrated-intel | integrated-amd) : ;;
        *) die "invalid --graphics value: '$GRAPHICS' (try --help)" ;;
    esac
    [ -z "$RES" ] || valid_res "$RES" || die "invalid --res value: '$RES' (expected WxH, e.g. 2560x1440)"
    [ -z "$REFRESH" ] || is_uint "$REFRESH" || die "invalid --refresh value: '$REFRESH' (expected an integer)"
    [ -z "$RENDER_SCALE" ] || valid_scale "$RENDER_SCALE" || die "invalid --render-scale value: '$RENDER_SCALE' (expected 0.1..1.0)"
}

# --------------------------------------------------------------------------- #
# GPU detection (parallel arrays, populated from sysfs)
# --------------------------------------------------------------------------- #
GPU_VENDOR=(); GPU_DEV=(); GPU_BOOT=(); GPU_PCI=(); GPU_TYPE=()

detect_gpus() {
    local d cls ven dev boot addr n i
    shopt -s nullglob
    for d in "$GAMESTEAM_SYSFS"/bus/pci/devices/*/; do
        [ -r "${d}class" ] || continue
        cls=$(<"${d}class")
        case "$cls" in 0x03*) : ;; *) continue ;; esac   # PCI class 0x03 = display controller
        if [ -r "${d}vendor" ]; then ven=$(<"${d}vendor"); else continue; fi
        if [ -r "${d}device" ]; then dev=$(<"${d}device"); else dev="0x0000"; fi
        boot=0; if [ -r "${d}boot_vga" ]; then boot=$(<"${d}boot_vga"); fi
        addr=$(basename "$d")
        GPU_VENDOR+=("$ven"); GPU_DEV+=("$dev"); GPU_BOOT+=("$boot")
        GPU_PCI+=("$addr");   GPU_TYPE+=("")
    done
    shopt -u nullglob

    n=${#GPU_VENDOR[@]}
    for ((i = 0; i < n; i++)); do
        case "${GPU_VENDOR[i]}" in
            0x10de) GPU_TYPE[i]="discrete-nvidia" ;;
            0x8086) GPU_TYPE[i]="integrated-intel" ;;   # Arc dGPU not auto-distinguished
            0x1002)
                if   [ "$n" -gt 1 ] && [ "${GPU_BOOT[i]}" = 1 ]; then GPU_TYPE[i]="integrated-amd"
                elif [ "$n" -gt 1 ];                              then GPU_TYPE[i]="discrete-amd"
                else                                                  GPU_TYPE[i]="amd"
                fi ;;
            *) GPU_TYPE[i]="other" ;;
        esac
    done
    log "detected $n display controller(s)"
}

print_gpus() {
    local n=${#GPU_VENDOR[@]} i
    if [ "$n" -eq 0 ]; then echo "no display controllers found under $GAMESTEAM_SYSFS"; return; fi
    for ((i = 0; i < n; i++)); do
        printf '  [%d] %-6s %s  type=%-16s boot_vga=%s\n' \
            "$i" "$(vendor_name "${GPU_VENDOR[i]}")" "${GPU_PCI[i]}" "${GPU_TYPE[i]}" "${GPU_BOOT[i]}"
    done
}

# --------------------------------------------------------------------------- #
# GPU selection
# --------------------------------------------------------------------------- #
SEL_IDX=-1
select_gpu() {
    local n=${#GPU_VENDOR[@]} i
    SEL_IDX=-1
    [ "$n" -gt 0 ] || return 0

    case "$GRAPHICS" in
        auto | discrete)
            for ((i = 0; i < n; i++)); do case "${GPU_TYPE[i]}" in discrete-*) SEL_IDX=$i; break ;; esac; done
            if [ "$SEL_IDX" -lt 0 ]; then
                for ((i = 0; i < n; i++)); do if [ "${GPU_BOOT[i]}" != 1 ]; then SEL_IDX=$i; break; fi; done
            fi
            [ "$SEL_IDX" -lt 0 ] && SEL_IDX=0 ;;
        integrated)
            for ((i = 0; i < n; i++)); do case "${GPU_TYPE[i]}" in integrated-*) SEL_IDX=$i; break ;; esac; done
            if [ "$SEL_IDX" -lt 0 ]; then
                for ((i = 0; i < n; i++)); do if [ "${GPU_BOOT[i]}" = 1 ]; then SEL_IDX=$i; break; fi; done
            fi
            [ "$SEL_IDX" -lt 0 ] && SEL_IDX=0 ;;
        nvidia)
            for ((i = 0; i < n; i++)); do if [ "${GPU_VENDOR[i]}" = 0x10de ]; then SEL_IDX=$i; break; fi; done ;;
        intel | integrated-intel)
            for ((i = 0; i < n; i++)); do if [ "${GPU_VENDOR[i]}" = 0x8086 ]; then SEL_IDX=$i; break; fi; done ;;
        amd)
            for ((i = 0; i < n; i++)); do case "${GPU_TYPE[i]}" in discrete-amd) SEL_IDX=$i; break ;; esac; done
            if [ "$SEL_IDX" -lt 0 ]; then
                for ((i = 0; i < n; i++)); do if [ "${GPU_VENDOR[i]}" = 0x1002 ]; then SEL_IDX=$i; break; fi; done
            fi ;;
        integrated-amd)
            for ((i = 0; i < n; i++)); do if [ "${GPU_TYPE[i]}" = integrated-amd ]; then SEL_IDX=$i; break; fi; done
            if [ "$SEL_IDX" -lt 0 ]; then
                for ((i = 0; i < n; i++)); do if [ "${GPU_VENDOR[i]}" = 0x1002 ]; then SEL_IDX=$i; break; fi; done
            fi ;;
    esac

    if [ "$SEL_IDX" -lt 0 ]; then
        warn "no GPU matches --graphics=$GRAPHICS; falling back to auto"
        for ((i = 0; i < n; i++)); do case "${GPU_TYPE[i]}" in discrete-*) SEL_IDX=$i; break ;; esac; done
        [ "$SEL_IDX" -lt 0 ] && SEL_IDX=0
    fi
}

# --------------------------------------------------------------------------- #
# CachyOS detection
# --------------------------------------------------------------------------- #
is_cachyos() {
    case "$CACHYOS" in on) return 0 ;; off) return 1 ;; esac
    grep -qiE '^(ID|ID_LIKE)=.*cachyos' /etc/os-release 2>/dev/null && return 0
    case "$(uname -r 2>/dev/null)" in *cachyos*) return 0 ;; esac
    have game-performance && return 0
    return 1
}

# --------------------------------------------------------------------------- #
# Environment tuning
# --------------------------------------------------------------------------- #
SEL_VENDOR=""; SEL_DEV=""; SEL_PCI=""; SEL_TYPE=""; SEL_BOOT=""; MULTI=0
PREFER_VK=""

apply_env() {
    local n=${#GPU_VENDOR[@]}
    [ "$n" -gt 1 ] && MULTI=1
    if [ "$SEL_IDX" -ge 0 ]; then
        SEL_VENDOR="${GPU_VENDOR[$SEL_IDX]}"; SEL_DEV="${GPU_DEV[$SEL_IDX]}"
        SEL_PCI="${GPU_PCI[$SEL_IDX]}";       SEL_TYPE="${GPU_TYPE[$SEL_IDX]}"
        SEL_BOOT="${GPU_BOOT[$SEL_IDX]}"
        [ "$MULTI" = 1 ] && PREFER_VK="${SEL_VENDOR#0x}:${SEL_DEV#0x}"
    fi

    # Universal base (portable across Proton/driver stacks).
    export __GL_SYNC_TO_VBLANK=0           # driver VSync off (OpenGL); gamescope governs VSync otherwise
    export VKD3D_CONFIG=dxr11,dxr          # DXR + DXR 1.1 ray tracing (RT, not "DirectX 11")
    export VKD3D_FEATURE_LEVEL=12_2        # advertise D3D12 feature level 12_2
    export DXVK_NVAPI_LOG_LEVEL=none       # quiet DXVK-NVAPI
    export ENABLE_GAMESCOPE_WSI=1          # Vulkan present straight into gamescope
    [ "$WANT_HDR" = 1 ] && export DXVK_HDR=1

    case "$SEL_VENDOR" in
        0x10de)  # NVIDIA (proprietary)
            export PROTON_ENABLE_NVAPI=1                 # DLSS / Reflex (upstream Proton)
            export __GL_SHADER_DISK_CACHE=1
            export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
            export __GL_THREADED_OPTIMIZATIONS=1         # helps native OpenGL titles
            if [ "$MULTI" = 1 ] && [ "$SEL_BOOT" != 1 ]; then
                export __NV_PRIME_RENDER_OFFLOAD=1       # render on the dGPU behind an iGPU
                export __VK_LAYER_NV_optimus=NVIDIA_only
                export __GLX_VENDOR_LIBRARY_NAME=nvidia
                log "NVIDIA PRIME render offload enabled"
            fi ;;
        0x1002)  # AMD (Mesa / RADV)
            export AMD_VULKAN_ICD=RADV                   # prefer RADV over AMDVLK if both present
            export RADV_PERFTEST=gpl                     # graphics pipeline library (default on recent Mesa)
            export MESA_SHADER_CACHE_MAX_SIZE=12G
            if [ "$MULTI" = 1 ]; then
                export DRI_PRIME="pci-${SEL_PCI//[.:]/_}"
                export MESA_VK_DEVICE_SELECT="${SEL_VENDOR#0x}:${SEL_DEV#0x}"
                log "Mesa device selected: DRI_PRIME=$DRI_PRIME"
            fi ;;
        0x8086)  # Intel (Mesa / ANV)
            export MESA_SHADER_CACHE_MAX_SIZE=12G
            if [ "$MULTI" = 1 ]; then
                export DRI_PRIME="pci-${SEL_PCI//[.:]/_}"
                export MESA_VK_DEVICE_SELECT="${SEL_VENDOR#0x}:${SEL_DEV#0x}"
                log "Mesa device selected: DRI_PRIME=$DRI_PRIME"
            fi ;;
    esac
}

apply_cachyos() {
    export PROTON_USE_NTSYNC=1             # needs kernel >=6.14; newer Proton default-on ignores it
    export PROTON_NO_WM_DECORATION=1       # cleaner fullscreen handoff to gamescope (CachyOS-Proton)
    export PROTON_XESS_UPGRADE=1           # auto-update XeSS (works on any vendor via DP4a)
    case "$SEL_VENDOR" in
        0x10de)
            export PROTON_NVIDIA_LIBS_NO_32BIT=1   # RTX 4000+ performance fix
            export PROTON_DLSS_UPGRADE=1           # auto-update the DLSS DLL
            ;;
        0x1002)
            export PROTON_FSR4_UPGRADE=1           # RDNA4 only; no-op on older AMD
            ;;
    esac
    log "CachyOS tuning applied"
}

# --------------------------------------------------------------------------- #
# Native resolution detection (first connected connector's preferred mode)
# --------------------------------------------------------------------------- #
detect_res() {
    local c modes first
    shopt -s nullglob
    for c in "$GAMESTEAM_SYSFS"/class/drm/*/status; do
        [ -r "$c" ] || continue
        [ "$(<"$c")" = connected ] || continue
        modes="${c%/status}/modes"
        [ -r "$modes" ] || continue
        first=$(head -n1 "$modes" 2>/dev/null) || continue
        case "$first" in
            *x*) printf '%s %s\n' "${first%x*}" "${first#*x}"; shopt -u nullglob; return 0 ;;
        esac
    done
    shopt -u nullglob
    return 1
}

# --------------------------------------------------------------------------- #
# gamescope argument vector
# --------------------------------------------------------------------------- #
GS_ARGS=()
build_gamescope_args() {
    local W H rw rh scale use_fsr

    if [ -n "$RES" ]; then
        W="${RES%x*}"; H="${RES#*x}"
    else
        read -r W H < <(detect_res) || true
        W="${W:-}"; H="${H:-}"
    fi

    scale="$RENDER_SCALE"
    if [ -z "$scale" ]; then
        case "$SEL_TYPE" in integrated-*) scale="0.75" ;; *) scale="1.0" ;; esac
    fi

    use_fsr=0
    case "$FORCE_FSR" in
        on)  use_fsr=1 ;;
        off) use_fsr=0 ;;
        auto) if awk -v s="$scale" 'BEGIN { exit !(s < 0.999) }'; then use_fsr=1; fi ;;
    esac
    [ -n "$W" ] && [ -n "$H" ] || use_fsr=0     # upscaling needs a known output size

    GS_ARGS=(--backend wayland --fullscreen --adaptive-sync --rt)
    if [ -n "$W" ] && [ -n "$H" ]; then
        GS_ARGS+=(-W "$W" -H "$H")
        if [ "$use_fsr" = 1 ]; then
            rw=$(awk -v v="$W" -v s="$scale" 'BEGIN { n=int(v*s); n-=n%2; print n }')
            rh=$(awk -v v="$H" -v s="$scale" 'BEGIN { n=int(v*s); n-=n%2; print n }')
            GS_ARGS+=(-w "$rw" -h "$rh" -F fsr)
            log "internal render ${rw}x${rh} -> FSR upscale to ${W}x${H}"
        fi
    fi
    [ -n "$REFRESH" ]   && GS_ARGS+=(-r "$REFRESH")
    [ -n "$PREFER_VK" ] && GS_ARGS+=(--prefer-vk-device "$PREFER_VK")
    [ "$WANT_HDR" = 1 ] && GS_ARGS+=(--hdr-enabled)
    [ "$WANT_HUD" = 1 ] && GS_ARGS+=(--mangoapp)
}

# --------------------------------------------------------------------------- #
# Power profile (switch for the session, restore on exit)
# --------------------------------------------------------------------------- #
PPD_PREV=""
ppd_start() {
    PPD_PREV="$(powerprofilesctl get 2>/dev/null || echo balanced)"
    powerprofilesctl set "$POWER_PROFILE" 2>/dev/null \
        || warn "could not set power profile '$POWER_PROFILE'"
    log "power profile: $PPD_PREV -> $POWER_PROFILE"
}
ppd_restore() {
    [ -n "$PPD_PREV" ] || return
    powerprofilesctl set "$PPD_PREV" 2>/dev/null || true
}

# --------------------------------------------------------------------------- #
# Plan (dry-run / verbose)
# --------------------------------------------------------------------------- #
print_plan() {
    local use_gs="$1" use_gm="$2" cachyos_on="$3" pp="$4"
    {
        echo "── gamesteam plan ──────────────────────────────────────────"
        print_gpus
        if [ "$SEL_IDX" -ge 0 ]; then
            printf 'selected      : [%d] %s %s (%s)\n' \
                "$SEL_IDX" "$(vendor_name "$SEL_VENDOR")" "$SEL_PCI" "$SEL_TYPE"
        else
            echo "selected      : none (no GPU detected)"
        fi
        printf 'cachyos       : %s\n' "$cachyos_on"
        printf 'gamescope     : %s\n' "$use_gs"
        printf 'gamemode      : %s\n' "$use_gm"
        printf 'power profile : %s\n' "$pp"
        printf 'hud           : %s\n' "$([ "$WANT_HUD" = 1 ] && echo on || echo off)"
        printf 'hdr           : %s\n' "$([ "$WANT_HDR" = 1 ] && echo on || echo off)"
        echo "managed env   :"
        env | grep -E '^(PROTON_|DXVK|VKD3D|__GL|__NV|__VK_LAYER|__GLX|DRI_PRIME|MESA_|RADV_|AMD_VULKAN_ICD|ENABLE_GAMESCOPE)' \
            | sort | sed 's/^/                /'
        echo "would run     :"
        printf '                '; printf '%q ' "${RUN[@]}"; printf '\n'
        echo "────────────────────────────────────────────────────────────"
    } >&2
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
RUN=()
main() {
    load_config
    parse_args "$@"
    validate_opts

    detect_gpus
    if [ "$LIST_ONLY" = 1 ]; then print_gpus; exit 0; fi

    select_gpu
    apply_env

    local cachyos_on=off
    if is_cachyos; then cachyos_on=on; apply_cachyos; fi

    # gamescope: auto enables it for integrated GPUs (where render-scale + FSR
    # is the biggest win) and leaves discrete GPUs on native. on/off force it.
    local use_gs=off
    case "$USE_GAMESCOPE" in
        on)
            have gamescope || die "--gamescope requested but gamescope not found"
            use_gs=on ;;
        auto)
            case "$SEL_TYPE" in
                integrated-*)
                    if have gamescope; then
                        use_gs=on
                    else
                        log "integrated GPU selected but gamescope not found: running at native resolution (install gamescope for FSR upscaling, or pass --no-gamescope)"
                    fi ;;
            esac ;;
        off) : ;;
    esac
    [ "$use_gs" = on ] && build_gamescope_args

    # gamemode
    local use_gm=off
    case "$USE_GAMEMODE" in
        on)   if have gamemoderun; then use_gm=on; else warn "--gamemode requested but gamemoderun not found; continuing without it"; fi ;;
        auto) have gamemoderun && use_gm=on ;;
        off)  : ;;
    esac

    # power profile: honoured only if requested and the daemon is present
    local pp="off"
    local do_pp=0
    if [ "$DO_POWER_PROFILE" = 1 ]; then
        if have powerprofilesctl; then do_pp=1; pp="$POWER_PROFILE"
        else warn "power-profiles-daemon not present; leaving power profile unchanged"; fi
    fi

    # Assemble: gamescope -- [gamemoderun] <command>
    RUN=()
    [ "$use_gs" = on ] && RUN+=(gamescope "${GS_ARGS[@]}" --)
    [ "$use_gm" = on ] && RUN+=(gamemoderun)
    if [ "${#COMMAND[@]}" -eq 0 ]; then
        if [ "$DRYRUN" = 1 ]; then RUN+=("<command>"); else die "no command given — use '$SELF %command%' in Steam launch options"; fi
    else
        RUN+=("${COMMAND[@]}")
    fi

    if [ "$DRYRUN" = 1 ] || [ "$VERBOSE" = 1 ]; then print_plan "$use_gs" "$use_gm" "$cachyos_on" "$pp"; fi
    [ "$DRYRUN" = 1 ] && exit 0

    if [ "$do_pp" = 1 ]; then
        ppd_start
        trap ppd_restore EXIT
        trap 'exit' INT TERM        # ensure the EXIT trap (restore) runs on TERM/INT
        "${RUN[@]}"                 # no exec: stay alive so the trap fires
    else
        exec "${RUN[@]}"
    fi
}

main "$@"
