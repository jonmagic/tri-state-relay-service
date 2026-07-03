#!/usr/bin/env bash
set -euo pipefail

app_path="dist/macos/Tri-State Relay Service.app"
app_executable="${app_path}/Contents/MacOS/Tri-State Relay Service"
relay_cli="${app_path}/Contents/MacOS/relay"
artifact_root="${TSRS_SETTINGS_UI_ARTIFACT_DIR:-.artifacts/settings-ui/$(date -u +%Y%m%dT%H%M%SZ)}"

if [[ "${TSRS_SETTINGS_UI_SKIP_BUILD:-0}" != "1" ]]; then
  scripts/build-macos.sh direct
fi

if [[ ! -x "$app_executable" || ! -x "$relay_cli" ]]; then
  echo "rebuilt direct app or bundled relay CLI is missing" >&2
  exit 1
fi

mkdir -p "$artifact_root"
"$relay_cli" focus >/dev/null

scripts/restart-macos-app.sh
"$relay_cli" debug open-settings --panel setup >/dev/null
sleep 0.5

settings_window_id=""
if settings_window_id="$(
  osascript 2>/dev/null <<'APPLESCRIPT'
tell application "System Events"
  if UI elements enabled is false then
    error "Accessibility permission is not granted."
  end if

  tell process "Tri-State Relay Service"
    set frontmost to true
    repeat 40 times
      if exists window "Tri-State Relay Service Settings" then
        set settingsWindow to window "Tri-State Relay Service Settings"
        return value of attribute "AXWindowNumber" of settingsWindow
      end if
      delay 0.25
    end repeat
  end tell
end tell

error "Tri-State Relay Service Settings window did not open."
APPLESCRIPT
)"; then
  :
else
  settings_window_id=""
  echo "Accessibility permission is not available; capturing full-screen Settings screenshots instead of cropped window screenshots." >&2
fi

capture_panel() {
  local panel="$1"
  local name="$panel"

  "$relay_cli" debug open-settings --panel "$panel" >/dev/null
  sleep 0.5
  if [[ -n "$settings_window_id" ]]; then
    screencapture -x -l "$settings_window_id" "$artifact_root/${name}.png"
  else
    screencapture -x "$artifact_root/${name}.png"
  fi
}

capture_panel "setup"
capture_panel "voice"
capture_panel "secondary"
capture_panel "advanced"

echo "captured Settings screenshots in ${artifact_root}"
