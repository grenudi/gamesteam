# gamesteam

**One line in your Steam launch options. Every game, every GPU, tuned right.**

```
gamesteam %command%
```

That's the whole setup. `gamesteam` reads your hardware straight from the kernel,
picks the correct GPU, forces the game onto it, applies current Proton/DXVK/VKD3D
tuning, runs it under [gamemode](https://github.com/FeralInteractive/gamemode),
and puts the system into a performance power profile for the session — then puts
everything back the way it was when you quit. No per-game fiddling, no PRIME
env-var incantations, no wrapper soup.

The core is a single, standalone, **distro-agnostic** Bash script — every
external tool is optional and probed at runtime, so it degrades gracefully
anywhere. The repo also ships a man page, bash/zsh/fish completions,
`install.sh`/`uninstall.sh` for non-NixOS distros, and a thin Nix flake with a
NixOS module.

## Why it's good

- **Never pick a GPU again.** GPUs are read from `/sys` (no `lspci`), the
  discrete card is preferred, and the game is *forced onto it* with the correct
  vendor mechanism — NVIDIA PRIME offload, or Mesa `DRI_PRIME` +
  `MESA_VK_DEVICE_SELECT`, plus gamescope `--prefer-vk-device`. Offload only
  engages when a second GPU actually exists, so desktops aren't touched.

- **The same command adapts to the machine.** On a discrete card gamesteam gets
  out of the way and runs native. On an integrated GPU (Iris Xe, Radeon
  780M/Vega, …) it **automatically** drops into gamescope and renders at 75% with
  FSR upscaling to your native resolution — so the exact command that's invisible
  on your RTX desktop quietly turns a thin-and-light into a playable handheld.
  Zero flags. Force it either way with `--gamescope` / `--no-gamescope`.

- **A whole-system race tune, cleaned up after.** Performance power profile
  (restored on exit **and** on Ctrl-C / SIGINT), gamemode, fat shader caches, and
  up-to-date Proton/DXVK/VKD3D environment — every piece individually toggleable.

- **Fluent in CachyOS.** Auto-detected via `/etc/os-release`, a `*-cachyos`
  kernel, or a `game-performance` binary — so it lights up even on a stock distro
  running the CachyOS kernel/Proton. The CachyOS-Proton knobs (NTSYNC, DLSS /
  FSR4 / XeSS auto-upgrade, borderless fixes) are **gated by GPU vendor**, so you
  never ship a no-op or a footgun to the wrong card.

- **Actually shippable.** One-liner install, a real `man gamesteam`, bash/zsh/fish
  completions, config files for persistent defaults, input validation, and
  `--dry-run` / `--list-gpus` / `--verbose` to see precisely what it will do
  before it does it.

## Requirements

Everything is optional and skipped if absent: `gamescope`, `gamemode`
(`gamemoderun`), `mangohud`, `power-profiles-daemon` (`powerprofilesctl`), and —
on CachyOS — `game-performance`. For the `PROTON_*`/`VKD3D_*` tuning to take
effect you need a Proton build that implements those variables (Proton-CachyOS or
Proton-GE); stock Valve Proton ignores the CachyOS-specific ones harmlessly.
gamescope is what powers the automatic iGPU upscaling, so integrated-GPU users
will want it installed — the installer offers to do that for you.

## Install

### Quick install — non-NixOS (one-liner)

Installs the script, man page, and shell completions, and offers to install the
optional dependencies with your package manager:

```sh
curl -fsSL https://raw.githubusercontent.com/grenudi/gamesteam/main/install.sh | sh
```

or with wget:

```sh
wget -qO- https://raw.githubusercontent.com/grenudi/gamesteam/main/install.sh | sh
```

System-wide install goes to `/usr/local` (uses `sudo`). For a no-sudo install
into `~/.local` instead, pass `--user`:

```sh
curl -fsSL https://raw.githubusercontent.com/grenudi/gamesteam/main/install.sh | sh -s -- --user
```

`install.sh` flags: `--user`, `--prefix DIR`, `--no-deps`. To remove everything:

```sh
curl -fsSL https://raw.githubusercontent.com/grenudi/gamesteam/main/uninstall.sh | sh
```

(The installer detects pacman / apt / dnf / zypper / xbps / emerge. On NixOS it
refuses and points you to the module below.)

### Manual — any distro, no Nix

It's one self-contained script:

```sh
curl -fsSLO https://raw.githubusercontent.com/grenudi/gamesteam/main/gamesteam.sh
chmod +x gamesteam.sh
./gamesteam.sh --help
```

Install `gamescope`, `gamemode`, `mangohud`, and `power-profiles-daemon` with
your package manager for full functionality.

### Nix — standalone

```sh
nix run github:grenudi/gamesteam -- --help
nix profile install github:grenudi/gamesteam
```

### NixOS flake — module

Add the input and the module to your system flake:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    gamesteam.url = "github:grenudi/gamesteam";
    # Safe to follow here: the NixOS module builds against *your* pkgs, so this
    # follows only affects gamesteam's own standalone package outputs.
    gamesteam.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, gamesteam, ... }: {
    nixosConfigurations.YOURHOST = nixpkgs.lib.nixosSystem {
      modules = [
        ./configuration.nix
        gamesteam.nixosModules.default
      ];
    };
  };
}
```

Then enable it anywhere in your config:

```nix
programs.gamesteam.enable = true;
```

That installs the `gamesteam` binary (with its man page and completions) and
enables `programs.gamescope` (with `capSysNice`, so the automatic iGPU gamescope
gets realtime scheduling), `programs.gamemode`, and
`services.power-profiles-daemon`. Opt out of any of those:

```nix
programs.gamesteam = {
  enable = true;
  powerProfilesDaemon.enable = false;  # e.g. if you use TLP (they conflict)
  # gamescope.enable = false;
  # gamemode.enable  = false;
  # package = pkgs.gamesteam;          # override the wrapped package
};
```

## Usage

Set it as your Steam launch options (per game, or globally under
Settings → Compatibility):

```
gamesteam %command%
```

Examples:

```
gamesteam %command%                          # dGPU native, or auto-gamescope an iGPU
gamesteam --no-gamescope %command%           # force native even on an integrated GPU
gamesteam -g nvidia %command%                # pin a specific GPU
gamesteam --gamescope --res 2560x1440 --refresh 144 --hdr %command%
gamesteam --no-power-profile --no-gamemode %command%   # just the GPU/Proton env
```

Inspect the full plan for any machine without launching anything:

```sh
gamesteam -n -v -- /bin/true     # detected GPUs, selection, env, final command
gamesteam --list-gpus
man gamesteam                    # or: gamesteam --help
```

### Options

| Group | Option | Meaning |
|---|---|---|
| GPU | `-g, --graphics <t>` | `auto`·`discrete`·`integrated`·`nvidia`·`amd`·`intel`·`integrated-intel`·`integrated-amd` |
| | `--force-discrete` / `--force-integrated` | aliases for `-g discrete` / `-g integrated` |
| | `--list-gpus` | list detected GPUs and exit |
| gamescope | `--gamescope` / `--no-gamescope` | force gamescope on/off (**default: auto — on for integrated GPUs, off for discrete**) |
| | `--res <WxH>` `--refresh <Hz>` | output resolution / refresh cap (auto-detected otherwise) |
| | `--render-scale <f>` `--native` | internal scale 0.1–1.0 / render at output res |
| | `--fsr` / `--no-fsr` `--hdr` | FSR upscaling toggle / enable HDR |
| system | `--gamemode` / `--no-gamemode` | wrap in `gamemoderun` (on when available) |
| | `--power-profile <p>` / `--no-power-profile` | session power profile (default `performance`) |
| | `--hud` / `--no-hud` | MangoHud overlay (or `MANGOHUD=1`) |
| tuning | `--cachyos` / `--no-cachyos` | CachyOS-Proton tuning (auto-detected) |
| general | `-n, --dry-run` `-v, --verbose` `-q, --quiet` | inspect / explain / silence |
| | `-h, --help` `-V, --version` | help / version |

The gamescope resolution/upscaling options only take effect when gamescope is
active (automatically on integrated GPUs, or forced with `--gamescope`).

### Config files (persistent defaults)

Set defaults once instead of passing flags every time. Both files are shell
fragments assigning the option variables; **command-line flags always override
them**:

- `/etc/gamesteam/config` — system-wide
- `${XDG_CONFIG_HOME:-~/.config}/gamesteam/config` — per user

```sh
# ~/.config/gamesteam/config
GRAPHICS=nvidia
USE_GAMESCOPE=off      # auto | on | off — e.g. force native everywhere
POWER_PROFILE=performance
```

## How it works

GPUs are read from `/sys/bus/pci/devices`, classified by vendor and `boot_vga`,
and the discrete one is chosen by default. gamesteam applies vendor-correct
device-selection environment and, on hybrid systems, gamescope
`--prefer-vk-device`. Around the game it sets the performance power profile and
runs `gamemoderun`. When the **selected** GPU is integrated it also enables
gamescope automatically, auto-detects the display's native resolution, and
renders at 0.75 scale with FSR upscaling (tune with `--render-scale`, `--native`,
`--no-fsr`, or turn it off with `--no-gamescope`). Discrete GPUs render native
unless you pass `--gamescope`.

No DirectX version is forced — the game selects its own renderer. To force one
for a single game, append `-dx11` / `-dx12` / `-vulkan` in that game's own launch
options.

## Caveats

- gamescope `--adaptive-sync` (VRR) only passes through when nested if your
  compositor has VRR enabled (on GNOME: the experimental `variable-refresh-rate`
  feature).
- NVIDIA + gamescope wants a recent driver (≥ 555). This mostly matters if you
  force `--gamescope` on an NVIDIA discrete card; the automatic path only enables
  gamescope for integrated GPUs.
- Intel Arc (discrete) is not auto-distinguished from an Intel iGPU — pass
  `-g intel` and it is selected regardless. (Note it is then treated as
  integrated for the auto-gamescope decision; use `--no-gamescope` for native.)
- `services.power-profiles-daemon` conflicts with TLP; see the module option
  above.

## License

GPL-3.0-or-later. Add the license text as `LICENSE` when you publish:

```sh
curl -fsSL https://www.gnu.org/licenses/gpl-3.0.txt -o LICENSE
```

(or pick "GNU General Public License v3.0" in GitHub's license picker). Replace
the `YOUR NAME <idunerg@gmail.com>` placeholder in the copyright headers of
`gamesteam.sh` and `gamesteam.1`, and `grenudi` throughout.
