#!/usr/bin/env bash
set -euo pipefail

target="${TSRS_RELAY_INSTALL_TARGET:-/usr/local/bin/relay}"
source="${TSRS_RELAY_SOURCE:-dist/macos/Tri-State Relay Service.app/Contents/MacOS/relay}"

if [[ ! -x "$source" ]]; then
  echo "rebuilt bundled relay is missing or not executable: $source" >&2
  echo "run scripts/build-macos.sh direct first" >&2
  exit 1
fi

target_dir="$(dirname "$target")"
mkdir -p "$target_dir"

if [[ -e "$target" || -L "$target" ]]; then
  if [[ ! -w "$target" && ! -w "$target_dir" ]]; then
    echo "$target is not writable by $(id -un)." >&2
    echo "Run this once with sudo to replace the stale installed relay with a dev symlink:" >&2
    printf '  sudo TSRS_RELAY_INSTALL_TARGET=%q TSRS_RELAY_SOURCE=%q %q\n' "$target" "$source" "$0" >&2
    exit 1
  fi
  rm -f "$target"
fi

ln -s "$PWD/$source" "$target"
echo "linked $target -> $PWD/$source"
"$target" --version
