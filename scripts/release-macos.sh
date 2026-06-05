#!/usr/bin/env bash
set -euo pipefail

notary_profile="${TSRS_NOTARYTOOL_PROFILE:-tsrs}"
downloads_dir="${TSRS_DOWNLOADS_DIR:-$HOME/code/jonmagic/jonmagic.com/src/downloads}"

echo "Releasing macOS app with notarytool profile: $notary_profile"
release_zip="$(TSRS_NOTARYTOOL_PROFILE="$notary_profile" scripts/package-macos-direct.sh | tee /dev/stderr | awk '/^Wrote / {print substr($0, 7)}' | tail -n 1)"

if [[ -z "$release_zip" || ! -f "$release_zip" ]]; then
  echo "could not find packaged release zip" >&2
  exit 1
fi

mkdir -p "$downloads_dir"
download_zip="$downloads_dir/$(basename "$release_zip")"
if [[ -e "$download_zip" ]]; then
  echo "release download already exists: $download_zip" >&2
  echo "Increment CFBundleShortVersionString in src/macos/Info.plist and relayCliVersion in src/macos/RelayCore.swift before cutting another release." >&2
  exit 1
fi

cp "$release_zip" "$download_zip"
echo "Copied $download_zip"
