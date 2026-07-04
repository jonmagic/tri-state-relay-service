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
settings_json="$("$current_relay" settings)"

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

if [[ ! -f "$config_path" ]]; then
  echo "upgrade should create $config_path exactly once" >&2
  exit 1
fi

if [[ "$config_validate" != "config valid: $config_path" ]]; then
  echo "unexpected config validate output: $config_validate" >&2
  exit 1
fi

python3 - "$status_json" "$settings_json" <<'PY'
import json
import sys

status = json.loads(sys.argv[1])
settings = json.loads(sys.argv[2])
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

if settings.get("configError") is not None:
    raise SystemExit(f"expected no config error after upgrade, got {settings.get('configError')!r}")
PY

checksum_before="$(shasum -a 256 "$config_path" | awk '{print $1}')"
"$current_relay" status >/dev/null
checksum_after="$(shasum -a 256 "$config_path" | awk '{print $1}')"
if [[ "$checksum_before" != "$checksum_after" ]]; then
  echo "upgrade should not rewrite an existing config file" >&2
  exit 1
fi

existing_config_root="$root/existing-config"
mkdir -p "$existing_config_root"
export TSRS_DB_PATH="$existing_config_root/relay.db"
export TSRS_CONFIG_PATH="$existing_config_root/config.toml"
cat >"$TSRS_CONFIG_PATH" <<'TOML'
[voice]
command = "/usr/bin/say -f <text-file> -o <output-file>"

[combiner]
command = "apfel --system <system> --output plain <input>"

[retention]
cleanup_retention_minutes = 42
TOML

"$old_relay" combiner --command "llm prompt <input>" >/dev/null
existing_show="$("$current_relay" config show)"
case "$existing_show" in
  *'command = "apfel --system <system> --output plain <input>"'* ) ;;
  * ) echo "existing TOML config was not preserved as source of truth" >&2; exit 1 ;;
esac

invalid_config_root="$root/invalid-config"
mkdir -p "$invalid_config_root"
export TSRS_DB_PATH="$invalid_config_root/relay.db"
export TSRS_CONFIG_PATH="$invalid_config_root/config.toml"
cat >"$TSRS_CONFIG_PATH" <<'TOML'
[voice]
command = "/usr/bin/say -f <text-file> -o <output-file>"

[combiner]
command = "llm prompt <secret-file>"

[retention]
cleanup_retention_minutes = 525600
TOML

"$old_relay" --line Brain --message "must stay queued" >/dev/null
"$old_relay" ready >/dev/null
if "$current_relay" config validate >/dev/null 2>&1; then
  echo "invalid config should fail validation" >&2
  exit 1
fi
invalid_claim="$(TSRS_PROCESSOR_AUTH=app-owned-processor "$current_relay" app-claim-next)"
if [[ "$invalid_claim" != "null" ]]; then
  echo "invalid config should fail quiet and not claim speech, got $invalid_claim" >&2
  exit 1
fi
invalid_status="$("$current_relay" status)"
python3 - "$invalid_status" <<'PY'
import json
import sys

status = json.loads(sys.argv[1])
if status.get("muted") is not True:
    raise SystemExit(f"expected invalid config to report muted=true, got {status.get('muted')!r}")
if status.get("queueCount") != 1:
    raise SystemExit(f"expected invalid config to preserve queued relay, got queueCount={status.get('queueCount')!r}")
if not status.get("configError"):
    raise SystemExit("expected invalid config error in status JSON")
PY

echo "1.1.2 upgrade migration passed with current relay $("$current_relay" --version)"
