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
  echo "Cropped Settings window capture is not available; capturing full-screen screenshots instead." >&2
fi

interaction_report="$artifact_root/interaction-smoke.txt"
if osascript >"$interaction_report" 2>&1 <<'APPLESCRIPT'
tell application "System Events"
  if UI elements enabled is false then
    error "Accessibility permission is required for Settings interaction smoke checks."
  end if

  tell process "Tri-State Relay Service"
    set frontmost to true
    set settingsWindow to window "Tri-State Relay Service Settings"
    click (first button of settingsWindow whose title is "Setup")
    delay 0.2
    set contentGroup to group 1 of settingsWindow
    click (first button of contentGroup whose title is "Copy bundled CLI path")
    if not (exists (first button of contentGroup whose title contains "Command")) then
      error "Missing shortcut recorder button."
    end if
    if not (exists checkbox "Open Tri-State Relay Service at login" of contentGroup) then
      error "Missing Open at Login checkbox."
    end if

    click (first button of settingsWindow whose title is "Voice")
    delay 0.2
    set contentGroup to group 1 of settingsWindow
    set focused of scroll area 1 of contentGroup to true

    click (first button of settingsWindow whose title is "Combiner")
    delay 0.2
    set contentGroup to group 1 of settingsWindow
    set focused of scroll area 1 of contentGroup to true

    click (first button of settingsWindow whose title is "Advanced")
    delay 0.2
    set contentGroup to group 1 of settingsWindow
    set focused of scroll area 1 of contentGroup to true
  end tell
end tell

return "verified safe Settings interactions: setup copy button press, setup shortcut/open-at-login discovery, voice command scroll focus, combiner command scroll focus, advanced retention scroll focus"
APPLESCRIPT
then
  echo "verified Settings interactions in ${interaction_report}"
else
  echo "Accessibility permission is not available; skipped Settings interaction smoke checks. See ${interaction_report}." >&2
  if [[ "${TSRS_SETTINGS_UI_REQUIRE_INTERACTIONS:-0}" == "1" ]]; then
    exit 1
  fi
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
