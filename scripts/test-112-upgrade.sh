#!/usr/bin/env bash
set -euo pipefail

from_ref="${TSRS_UPGRADE_FROM_REF:-v1.1.2}"
current_relay="${TSRS_CURRENT_RELAY:-dist/macos/Tri-State Relay Service.app/Contents/MacOS/relay}"
root="${TSRS_UPGRADE_TEST_ROOT:-$(mktemp -d)}"
keep_root="${TSRS_UPGRADE_TEST_ROOT:-}"

if [[ ! -x "$current_relay" ]]; then
  echo "current bundled relay is missing: $current_relay" >&2
  echo "run scripts/build-macos.sh direct first" >&2
  exit 1
fi

cleanup() {
  if [[ -z "$keep_root" ]]; then
    git worktree remove --force "$root/source-$from_ref" >/dev/null 2>&1 || true
    rm -rf "$root"
  fi
}
trap cleanup EXIT

old_source="$root/source-$from_ref"
old_symroot="$root/xcode-$from_ref"
old_relay="$old_symroot/Release/relay-native"
database_path="$root/relay.db"
config_path="$root/config.toml"

mkdir -p "$root"
git worktree add --detach "$old_source" "$from_ref" >/dev/null

xcodebuild \
  -project "$old_source/src/macos/TriStateRelayService.xcodeproj" \
  -target relay-native \
  -configuration Release \
  "SYMROOT=$old_symroot" \
  "ARCHS=$(uname -m)" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO >/dev/null

if [[ "$("$old_relay" --version)" != "relay 1.1.2" ]]; then
  echo "expected $from_ref relay to report relay 1.1.2" >&2
  exit 1
fi

export TSRS_DB_PATH="$database_path"
export TSRS_CONFIG_PATH="$config_path"

"$old_relay" line Brain >/dev/null
"$old_relay" combiner --command "llm prompt <input> --system <system> --no-stream --no-log" >/dev/null
"$old_relay" settings --speech-command "/usr/bin/say -v Samantha <message>" >/dev/null
"$old_relay" --line Brain --message "pre-upgrade relay" >/dev/null
"$old_relay" first-start complete >/dev/null
"$old_relay" live >/dev/null
"$old_relay" mute >/dev/null

config_show="$("$current_relay" config show)"
config_validate="$("$current_relay" config validate)"
status_json="$("$current_relay" status)"

case "$config_show" in
  *'command = "/usr/bin/say -f <text-file> -o <output-file>"'* ) ;;
  * ) echo "config preview did not include the active default voice command" >&2; exit 1 ;;
esac

case "$config_show" in
  *'command = "llm prompt <input> --system <system> --no-stream --no-log"'* ) ;;
  * ) echo "config preview did not include the 1.1.2 combiner command" >&2; exit 1 ;;
esac

case "$config_show" in
  *'\\n# Voice command.'* | *'Speechify example'* )
    echo "config preview leaked escaped Settings template comments" >&2
    exit 1
    ;;
esac

if [[ -e "$config_path" ]]; then
  echo "config preview should not create $config_path before the write migration exists" >&2
  exit 1
fi

if [[ "$config_validate" != "config valid: $config_path (upgrade preview; file does not exist yet)" ]]; then
  echo "unexpected config validate output: $config_validate" >&2
  exit 1
fi

python3 - "$status_json" <<'PY'
import json
import sys

status = json.loads(sys.argv[1])
expected = {
    "mode": "live",
    "muted": True,
    "activeLine": "Brain",
    "inactiveLineCombiner": "custom",
}
for key, value in expected.items():
    if status.get(key) != value:
        raise SystemExit(f"expected status[{key!r}] to be {value!r}, got {status.get(key)!r}")

if status.get("queueCount") != 1:
    raise SystemExit(f"expected queued relay to survive upgrade, got queueCount={status.get('queueCount')!r}")
PY

echo "1.1.2 upgrade preview passed with current relay $("$current_relay" --version)"
