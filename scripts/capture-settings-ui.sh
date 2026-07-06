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
config_path="$("$relay_cli" config path)"
config_backup="$artifact_root/config.toml.before"
first_start_status="$("$relay_cli" first-start status)"
if [[ -f "$config_path" ]]; then
  cp "$config_path" "$config_backup"
else
  "$relay_cli" config show >/dev/null
  cp "$config_path" "$config_backup"
fi
"$relay_cli" first-start reset >/dev/null

restore_first_start() {
  if [[ "$first_start_status" == "complete" ]]; then
    "$relay_cli" first-start complete >/dev/null || true
  fi
}
trap restore_first_start EXIT

scripts/restart-macos-app.sh
sleep 1
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
    repeat 40 times
      if exists window "Tri-State Relay Service Settings" then
        set settingsWindow to window "Tri-State Relay Service Settings"
        exit repeat
      end if
      delay 0.25
    end repeat
    if not (exists window "Tri-State Relay Service Settings") then error "Tri-State Relay Service Settings window did not open."
    click (first button of settingsWindow whose title is "Setup")
    delay 0.2
    set contentGroup to group 1 of settingsWindow
    click (first button of contentGroup whose title is "Copy bundled CLI path")
    if not (exists (first button of contentGroup whose title contains "Command")) then
      error "Missing shortcut recorder button."
    end if
    set _openAtLoginCheckbox to my firstElementByRole(contentGroup, "AXCheckBox")

    click (first button of settingsWindow whose title is "Voice")
    delay 0.2
    set contentGroup to group 1 of settingsWindow
    set targetElement to missing value
    repeat with e in entire contents of contentGroup
      try
        if role of e is "AXTextArea" then
          set targetElement to e
          exit repeat
        end if
      end try
    end repeat
    if targetElement is missing value then error "Missing Voice text area."
    set focused of targetElement to true

    click (first button of settingsWindow whose title is "Combiner")
    delay 0.2
    set contentGroup to group 1 of settingsWindow
    set targetElement to missing value
    repeat with e in entire contents of contentGroup
      try
        if role of e is "AXTextArea" then
          set targetElement to e
          exit repeat
        end if
      end try
    end repeat
    if targetElement is missing value then error "Missing Combiner text area."
    set focused of targetElement to true

    click (first button of settingsWindow whose title is "Advanced")
    delay 0.2
    set contentGroup to group 1 of settingsWindow
    set targetElement to missing value
    repeat with e in entire contents of contentGroup
      try
        if role of e is "AXTextField" then
          set targetElement to e
          exit repeat
        end if
      end try
    end repeat
    if targetElement is missing value then error "Missing Advanced retention field."
    set focused of targetElement to true
  end tell
end tell

return "verified safe Settings interactions: setup copy button press, setup shortcut/open-at-login discovery, voice command scroll focus, combiner command scroll focus, advanced retention scroll focus"
APPLESCRIPT
then
  echo "verified Settings interactions in ${interaction_report}"
else
  echo "Accessibility permission is not available; skipped Settings interaction smoke checks. See ${interaction_report}." >&2
  if [[ "${TSRS_SETTINGS_UI_REQUIRE_INTERACTIONS:-0}" == "1" && "${TSRS_SETTINGS_UI_ROUNDTRIP:-0}" != "1" ]]; then
    exit 1
  fi
fi

roundtrip_report="$artifact_root/settings-roundtrip.txt"
if [[ "${TSRS_SETTINGS_UI_ROUNDTRIP:-0}" == "1" ]]; then
  voice_command="/bin/cp <text-file> <output-file>"
  combiner_command="llm prompt <input> --system <system> --no-stream --no-log"
  retention_minutes="1440"

  if "$relay_cli" debug settings-roundtrip --voice-command "$voice_command" --combiner-command "$combiner_command" --cleanup-retention-minutes "$retention_minutes" >"$roundtrip_report" 2>&1
  then
    for _ in {1..40}; do
      "$relay_cli" status >"$artifact_root/settings-after-modify.json"
      if python3 - "$artifact_root/settings-after-modify.json" "$voice_command" "$combiner_command" "$retention_minutes" <<'PY'
import json
import sys

path, voice, combiner, retention = sys.argv[1:]
settings = json.load(open(path))
if (
    settings.get("voiceCommand") == voice
    and settings.get("inactiveLineCombinerCommand") == combiner
    and settings.get("cleanupRetentionMinutes") == int(retention)
):
    raise SystemExit(0)
raise SystemExit(1)
PY
      then
        break
      fi
      sleep 0.25
    done
    "$relay_cli" status >"$artifact_root/settings-after-modify.json"
    python3 - "$artifact_root/settings-after-modify.json" "$voice_command" "$combiner_command" "$retention_minutes" <<'PY'
import json
import sys

path, voice, combiner, retention = sys.argv[1:]
settings = json.load(open(path))
expected = {
    "voiceCommand": voice,
    "inactiveLineCombinerCommand": combiner,
    "cleanupRetentionMinutes": int(retention),
}
for key, value in expected.items():
    if settings.get(key) != value:
        raise SystemExit(f"{key} expected {value!r}, got {settings.get(key)!r}")
PY
    cp "$config_backup" "$config_path"
    "$relay_cli" config reload >/dev/null
    "$relay_cli" status >"$artifact_root/settings-after-restore.json"
    python3 - "$artifact_root/settings-after-restore.json" "$config_backup" <<'PY'
import json
import subprocess
import sys

settings_path, config_path = sys.argv[1:]
settings = json.load(open(settings_path))
config = open(config_path).read()
for key, value in {
    "voiceCommand": "command = ",
    "inactiveLineCombinerCommand": "[combiner]",
}.items():
    if key not in settings:
        raise SystemExit(f"missing restored setting {key}")
if settings.get("configError") is not None:
    raise SystemExit(f"restore left config error: {settings.get('configError')!r}")
if "[voice]" not in config or "[retention]" not in config:
    raise SystemExit("backup config did not look like TOML")
PY
    echo "verified reversible Settings roundtrip in ${roundtrip_report}"
  else
    echo "Settings roundtrip check failed. See ${roundtrip_report}." >&2
    exit 1
  fi
fi

capture_panel() {
  local panel="$1"
  local name="$panel"

  local title
  case "$panel" in
    setup) title="Setup" ;;
    voice) title="Voice" ;;
    secondary) title="Combiner" ;;
    advanced) title="Advanced" ;;
    *) echo "unknown settings panel: $panel" >&2; exit 1 ;;
  esac
  "$relay_cli" debug open-settings --panel "$panel" >/dev/null
  sleep 1.5
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
