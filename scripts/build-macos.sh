#!/usr/bin/env bash
set -euo pipefail

profile="${1:-direct}"
macos_archs="${TSRS_MACOS_ARCHS:-}"

if [[ "$profile" != "direct" && "$profile" != "app-store" ]]; then
  echo "unknown macOS build profile: $profile" >&2
  exit 1
fi

if [[ -z "$macos_archs" ]]; then
  if [[ "$profile" == "direct" ]]; then
    macos_archs="arm64"
  else
    macos_archs="$(uname -m)"
  fi
fi

if [[ "$macos_archs" != "arm64" && "$macos_archs" != "x86_64" && "$macos_archs" != "arm64 x86_64" && "$macos_archs" != "x86_64 arm64" ]]; then
  echo "unsupported TSRS_MACOS_ARCHS: $macos_archs" >&2
  echo "supported values: arm64, x86_64, 'arm64 x86_64'" >&2
  exit 1
fi

app_name="Tri-State Relay Service.app"
project="src/macos/TriStateRelayService.xcodeproj"
target="Tri-State Relay Service"
scheme="Tri-State Relay Service"
source_app_icon="src/macos/Assets/AppIcon.png"
app_icon_name="AppIcon.icns"

if [[ "$profile" == "app-store" ]]; then
  dist_root="dist/macos-app-store"
  derived_data="dist/xcode/app-store"
else
  dist_root="dist/macos"
  derived_data="dist/xcode/direct"
fi

built_app="$derived_data/Build/Products/Release/$app_name"
output_app="$dist_root/$app_name"
output_macos="$output_app/Contents/MacOS"
output_resources="$output_app/Contents/Resources"
relay_build_root="$derived_data/relay-native"
relay_native="$relay_build_root/Release/relay-native"

install_app_icon() {
  if [[ ! -f "$source_app_icon" ]]; then
    echo "source app icon missing: $source_app_icon" >&2
    exit 1
  fi

  local iconset_path="dist/macos-icon.iconset"
  rm -rf "$iconset_path"
  mkdir -p "$iconset_path" "$output_resources"

  sips -z 16 16 "$source_app_icon" --out "$iconset_path/icon_16x16.png"
  sips -z 32 32 "$source_app_icon" --out "$iconset_path/icon_16x16@2x.png"
  sips -z 32 32 "$source_app_icon" --out "$iconset_path/icon_32x32.png"
  sips -z 64 64 "$source_app_icon" --out "$iconset_path/icon_32x32@2x.png"
  sips -z 128 128 "$source_app_icon" --out "$iconset_path/icon_128x128.png"
  sips -z 256 256 "$source_app_icon" --out "$iconset_path/icon_128x128@2x.png"
  sips -z 256 256 "$source_app_icon" --out "$iconset_path/icon_256x256.png"
  sips -z 512 512 "$source_app_icon" --out "$iconset_path/icon_256x256@2x.png"
  sips -z 512 512 "$source_app_icon" --out "$iconset_path/icon_512x512.png"
  sips -z 1024 1024 "$source_app_icon" --out "$iconset_path/icon_512x512@2x.png"
  iconutil -c icns "$iconset_path" -o "$output_resources/$app_icon_name"
  rm -rf "$iconset_path"
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1"
}

assert_relay_processor_not_bundled() {
  local found
  found="$(find "$1" -name relay-processor -print -quit)"
  if [[ -n "$found" ]]; then
    echo "relay-processor must not be bundled in the macOS app: $found" >&2
    exit 1
  fi
}

normalize_archs() {
  printf "%s\n" $1 | sort | xargs
}

verify_archs() {
  local binary="$1"
  local expected="$2"
  local actual
  actual="$(lipo -archs "$binary")"

  if [[ "$(normalize_archs "$actual")" != "$(normalize_archs "$expected")" ]]; then
    echo "unexpected architectures for $binary: $actual; expected: $expected" >&2
    exit 1
  fi
}

verify_bundle() {
  local app_path="$1"
  local info_plist="$app_path/Contents/Info.plist"
  local executable
  executable="$(plist_value "$info_plist" CFBundleExecutable)"

  if [[ "$executable" != "$target" ]]; then
    echo "unexpected CFBundleExecutable: $executable" >&2
    exit 1
  fi

  if [[ ! -f "$app_path/Contents/MacOS/$executable" ]]; then
    echo "bundle executable missing: $executable" >&2
    exit 1
  fi

  if [[ ! -f "$app_path/Contents/MacOS/relay" ]]; then
    echo "relay helper missing from bundle" >&2
    exit 1
  fi

  if [[ "$(plist_value "$info_plist" CFBundleIconFile)" != "AppIcon" ]]; then
    echo "CFBundleIconFile was not preserved" >&2
    exit 1
  fi

  if [[ ! -f "$app_path/Contents/Resources/$app_icon_name" ]]; then
    echo "$app_icon_name missing from bundle resources" >&2
    exit 1
  fi

  assert_relay_processor_not_bundled "$app_path"
  verify_archs "$app_path/Contents/MacOS/$executable" "$macos_archs"
  verify_archs "$app_path/Contents/MacOS/relay" "$macos_archs"

  local ui_element
  ui_element="$(plist_value "$info_plist" LSUIElement)"
  if [[ "$ui_element" != "1" && "$ui_element" != "true" ]]; then
    echo "LSUIElement was not preserved" >&2
    exit 1
  fi
}

rm -rf "$derived_data" "$output_app"
mkdir -p "$dist_root"

xcodebuild_args=(
  -project "$project"
  -scheme "$scheme"
  -configuration Release
  -derivedDataPath "$derived_data"
  "ARCHS=$macos_archs"
  ONLY_ACTIVE_ARCH=NO
  CODE_SIGNING_ALLOWED=NO
)

if [[ "$profile" == "app-store" ]]; then
  xcodebuild_args+=(SWIFT_ACTIVE_COMPILATION_CONDITIONS=APP_STORE)
fi

xcodebuild "${xcodebuild_args[@]}"
xcodebuild \
  -project "$project" \
  -target relay-native \
  -configuration Release \
  "SYMROOT=$PWD/$relay_build_root" \
  "ARCHS=$macos_archs" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO

cp -R "$built_app" "$dist_root"
cp "$relay_native" "$output_macos/relay"
install_app_icon
verify_bundle "$output_app"
