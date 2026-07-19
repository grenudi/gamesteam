#!/usr/bin/env bash
#
# One-shot setup + refresh for the gamesteam dev environment.
# Run it once after cloning, and any time you want a clean rebuild:
#     bash initdirenv.sh        (or ./initdirenv.sh once it is executable)
# It is idempotent and safe to re-run.
set -euo pipefail

# Work from the repo root regardless of where this is invoked from.
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"

nixflags=(--extra-experimental-features "nix-command flakes")

echo "🧹 Removing Nix build symlinks (result, result-*)..."
find . -maxdepth 2 -type l \( -name 'result' -o -name 'result-*' \) -exec rm -f {} + 2>/dev/null || true

command -v nix    >/dev/null 2>&1 || { echo "❌ nix not found — install Nix (with flakes) first."          >&2; exit 1; }
command -v direnv >/dev/null 2>&1 || { echo "❌ direnv not found — install it and hook it into your shell." >&2; exit 1; }

echo "🔒 Locking the dev flake (creates/refreshes dev/flake.lock)..."
nix "${nixflags[@]}" flake lock ./dev

echo "✅ Allowing direnv for this project..."
direnv allow "$root"

echo "🏗️  Building the dev shell (first run downloads the VSCodium extension set)..."
direnv exec "$root" true

echo "✨ Ready — open the isolated IDE with:  code .   (or: code-dev .)"
echo "   The environment auto-loads on your next shell prompt here (or run: direnv reload)."
