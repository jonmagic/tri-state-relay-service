#!/usr/bin/env bash
set -euo pipefail

app_name="Tri-State Relay Service.app"
app_path="dist/macos/$app_name"
app_executable="$app_path/Contents/MacOS/Tri-State Relay Service"
relay_executable="$app_path/Contents/MacOS/relay"
speechify_executable="$app_path/Contents/MacOS/speechify"
info_plist="$app_path/Contents/Info.plist"
releases_dir="dist/releases"
submission_zip="$releases_dir/notary-submission.zip"
version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" src/macos/Info.plist)"
build_archs="${TSRS_MACOS_ARCHS:-arm64}"
if [[ "$build_archs" != "arm64" && "$build_archs" != "x86_64" && "$build_archs" != "arm64 x86_64" && "$build_archs" != "x86_64 arm64" ]]; then
  echo "unsupported TSRS_MACOS_ARCHS: $build_archs" >&2
  echo "supported values: arm64, x86_64, 'arm64 x86_64'" >&2
  exit 1
fi

if [[ "$build_archs" == "arm64 x86_64" || "$build_archs" == "x86_64 arm64" ]]; then
  release_arch="universal"
else
  release_arch="$build_archs"
fi
release_zip="$releases_dir/Tri-State Relay Service-$version-macos-$release_arch.zip"
notary_profile="${TSRS_NOTARYTOOL_PROFILE:-}"

ensure_developer_id() {
  if [[ "$1" != Developer\ ID\ Application:\ * ]]; then
    echo "TSRS_CODESIGN_IDENTITY must be a Developer ID Application identity" >&2
    exit 1
  fi
}

selected_identity() {
  if [[ -n "${TSRS_CODESIGN_IDENTITY:-}" ]]; then
    ensure_developer_id "$TSRS_CODESIGN_IDENTITY"
    echo "$TSRS_CODESIGN_IDENTITY"
    return
  fi

  local identities=()
  while IFS= read -r identity_name; do
    [[ -n "$identity_name" ]] && identities+=("$identity_name")
  done < <(security find-identity -v -p codesigning | sed -n 's/.*"\(.*\)".*/\1/p')

  local developer_ids=()
  local development_ids=()
  for identity_name in "${identities[@]}"; do
    if [[ "$identity_name" == Developer\ ID\ Application:\ * ]]; then
      developer_ids+=("$identity_name")
    elif [[ "$identity_name" == Apple\ Development:\ * ]]; then
      development_ids+=("$identity_name")
    fi
  done

  if [[ "${#developer_ids[@]}" -eq 1 ]]; then
    echo "${developer_ids[0]}"
    return
  fi

  if [[ "${#developer_ids[@]}" -gt 1 ]]; then
    echo "multiple Developer ID Application identities found; set TSRS_CODESIGN_IDENTITY" >&2
    exit 1
  fi

  if [[ "${#development_ids[@]}" -gt 0 ]]; then
    echo "Apple Development certificates are not sufficient for sharing outside your machines; install a Developer ID Application certificate" >&2
    exit 1
  fi

  echo "no Developer ID Application signing identity found" >&2
  exit 1
}

assert_relay_processor_not_bundled() {
  local found
  found="$(find "$1" -name relay-processor -print -quit)"
  if [[ -n "$found" ]]; then
    echo "relay-processor must not be bundled in the macOS app: $found" >&2
    exit 1
  fi
}

assert_built_bundle() {
  for path in "$app_path" "$app_executable" "$relay_executable" "$speechify_executable" "$info_plist"; do
    if [[ ! -e "$path" ]]; then
      echo "expected build output is missing: $path" >&2
      exit 1
    fi
  done

  assert_relay_processor_not_bundled "$app_path"
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$info_plist"
}

assert_version_matches() {
  local bundle_version
  bundle_version="$(plist_value CFBundleShortVersionString)"

  if [[ "$bundle_version" != "$version" ]]; then
    echo "release version $version does not match app version $bundle_version" >&2
    exit 1
  fi
}

sign_path() {
  codesign --force --options runtime --timestamp --sign "$identity" "$1"
}

verify_signed_bundle() {
  codesign --verify --strict --deep --verbose=2 "$app_path"
  codesign --display --verbose=2 "$app_path"
}

zip_app() {
  local output_path="$1"
  (
    cd "dist/macos"
    ditto -c -k --keepParent "$app_name" "../../$output_path"
  )
}

if [[ -z "$version" ]]; then
  echo "could not read app version" >&2
  exit 1
fi

if [[ -z "$notary_profile" ]]; then
  echo "TSRS_NOTARYTOOL_PROFILE is required for a shareable notarized build" >&2
  exit 1
fi

identity="$(selected_identity)"

scripts/build-macos.sh direct
assert_built_bundle
assert_version_matches

mkdir -p "$releases_dir"
rm -f "$submission_zip" "$release_zip"

sign_path "$relay_executable"
sign_path "$speechify_executable"
"$relay_executable" status
sign_path "$app_path"
verify_signed_bundle

zip_app "$submission_zip"
xcrun notarytool submit "$submission_zip" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type exec --verbose=2 "$app_path"

zip_app "$release_zip"
rm -f "$submission_zip"

echo "Wrote $release_zip"
