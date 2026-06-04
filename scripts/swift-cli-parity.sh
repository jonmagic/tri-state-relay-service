#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_RELAY="${TSRS_PARITY_SWIFT:-"$ROOT/dist/macos/Tri-State Relay Service.app/Contents/MacOS/relay"}"
ORACLE="${TSRS_PARITY_ORACLE:-"$SWIFT_RELAY"}"
RUN_ROOT="$ROOT/.swift-cli-parity"
STRICT="${TSRS_PARITY_STRICT:-0}"

pass_count=0
skip_count=0
gap_count=0

cleanup() {
  rm -rf "$RUN_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_executable() {
  local path="$1"
  [[ -x "$path" ]] || fail "missing executable: $path"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

log_pass() {
  pass_count=$((pass_count + 1))
  printf 'ok - %s\n' "$1"
}

log_skip() {
  skip_count=$((skip_count + 1))
  printf 'skip - %s\n' "$1"
}

log_gap() {
  gap_count=$((gap_count + 1))
  printf 'gap - %s\n' "$1"
  if [[ "$STRICT" == "1" ]]; then
    fail "$1"
  fi
}

normalize_text() {
  sed -E 's/#[0-9]+/#<id>/g'
}

assert_equal() {
  local label="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$expected" != "$actual" ]]; then
    printf '--- oracle %s ---\n%s\n' "$label" "$expected" >&2
    printf '--- swift %s ---\n%s\n' "$label" "$actual" >&2
    fail "$label mismatch"
  fi
}

run_cli() {
  local side="$1"
  local bin="$2"
  local db="$3"
  shift 3

  local out="$RUN_ROOT/$side.out"
  local err="$RUN_ROOT/$side.err"
  set +e
  TSRS_DISTRIBUTION_PROFILE=direct TSRS_DB_PATH="$db" "$bin" "$@" >"$out" 2>"$err"
  local code=$?
  set -e

  printf '%s\n' "$code" >"$RUN_ROOT/$side.code"
}

run_cli_auth() {
  local side="$1"
  local bin="$2"
  local db="$3"
  shift 3

  local out="$RUN_ROOT/$side.out"
  local err="$RUN_ROOT/$side.err"
  set +e
  TSRS_DISTRIBUTION_PROFILE=direct TSRS_PROCESSOR_AUTH=app-owned-processor TSRS_DB_PATH="$db" "$bin" "$@" >"$out" 2>"$err"
  local code=$?
  set -e

  printf '%s\n' "$code" >"$RUN_ROOT/$side.code"
}

stdout_of() {
  cat "$RUN_ROOT/$1.out"
}

stderr_of() {
  cat "$RUN_ROOT/$1.err"
}

code_of() {
  cat "$RUN_ROOT/$1.code"
}

run_pair() {
  local oracle_db="$1"
  local swift_db="$2"
  shift 2

  run_cli oracle "$ORACLE" "$oracle_db" "$@"
  run_cli swift "$SWIFT_RELAY" "$swift_db" "$@"
}

run_pair_auth() {
  local oracle_db="$1"
  local swift_db="$2"
  shift 2

  run_cli_auth oracle "$ORACLE" "$oracle_db" "$@"
  run_cli_auth swift "$SWIFT_RELAY" "$swift_db" "$@"
}

assert_text_command() {
  local label="$1"
  local oracle_db="$2"
  local swift_db="$3"
  shift 3

  run_pair "$oracle_db" "$swift_db" "$@"
  assert_equal "$label exit" "$(code_of oracle)" "$(code_of swift)"
  assert_equal "$label stderr" "$(stderr_of oracle)" "$(stderr_of swift)"
  assert_equal "$label stdout" "$(stdout_of oracle | normalize_text)" "$(stdout_of swift | normalize_text)"
  log_pass "$label"
}

assert_auth_text_command() {
  local label="$1"
  local oracle_db="$2"
  local swift_db="$3"
  shift 3

  run_pair_auth "$oracle_db" "$swift_db" "$@"
  assert_equal "$label exit" "$(code_of oracle)" "$(code_of swift)"
  assert_equal "$label stderr" "$(stderr_of oracle)" "$(stderr_of swift)"
  assert_equal "$label stdout" "$(stdout_of oracle | normalize_text)" "$(stdout_of swift | normalize_text)"
  log_pass "$label"
}

json_compare() {
  local label="$1"
  local mode="$2"
  python3 - "$label" "$mode" "$RUN_ROOT/oracle.out" "$RUN_ROOT/swift.out" <<'PY'
import json
import sys

label, mode, oracle_path, swift_path = sys.argv[1:5]
with open(oracle_path, encoding="utf-8") as handle:
    oracle = json.load(handle)
with open(swift_path, encoding="utf-8") as handle:
    swift = json.load(handle)

def normalize_install(value):
    return {
        "status": value.get("status"),
        "targetDirectoryOnPath": value.get("targetDirectoryOnPath"),
        "version": value.get("version"),
        "hasSourceSignature": "sourceSignature" in value,
        "hasTargetSignature": "targetSignature" in value,
    }

def project_status(value):
    return {
        "profile": value.get("profile"),
        "mode": value.get("mode"),
        "muted": value.get("muted"),
        "inactiveLineCombiner": value.get("inactiveLineCombiner"),
        "hasInactiveLineCombinerCommand": bool(value.get("inactiveLineCombinerCommand")),
        "hasSpeechCommand": bool(value.get("speechCommand")),
        "activeLine": value.get("activeLine"),
        "counts": value.get("counts"),
        "queueCount": value.get("queueCount"),
        "attentionCount": value.get("attentionCount"),
        "lines": value.get("lines"),
        "hasOverview": "overview" in value,
        "hasCapabilities": "capabilities" in value,
        "hasLineSources": "lineSources" in value,
    }

def normalize(value):
    if mode == "install":
        return normalize_install(value)
    if mode == "status":
        return project_status(value)
    if mode == "claim":
        return value
    return value

left = normalize(oracle)
right = normalize(swift)
if left != right:
    print(f"{label} JSON mismatch", file=sys.stderr)
    print("oracle:", json.dumps(left, sort_keys=True), file=sys.stderr)
    print("swift: ", json.dumps(right, sort_keys=True), file=sys.stderr)
    sys.exit(1)

PY
}

assert_json_command() {
  local label="$1"
  local mode="$2"
  local oracle_db="$3"
  local swift_db="$4"
  shift 4

  run_pair "$oracle_db" "$swift_db" "$@"
  assert_equal "$label exit" "$(code_of oracle)" "$(code_of swift)"
  assert_equal "$label stderr" "$(stderr_of oracle)" "$(stderr_of swift)"

  json_compare "$label" "$mode" >/dev/null
  log_pass "$label"
}

assert_auth_json_command() {
  local label="$1"
  local mode="$2"
  local oracle_db="$3"
  local swift_db="$4"
  shift 4

  run_pair_auth "$oracle_db" "$swift_db" "$@"
  assert_equal "$label exit" "$(code_of oracle)" "$(code_of swift)"
  assert_equal "$label stderr" "$(stderr_of oracle)" "$(stderr_of swift)"
  json_compare "$label" "$mode" >/dev/null
  log_pass "$label"
}

db_snapshot() {
  local db="$1"
  python3 - "$db" <<'PY'
import json
import sqlite3
import sys

db = sys.argv[1]
connection = sqlite3.connect(db)
connection.row_factory = sqlite3.Row

def rows(sql):
    return [dict(row) for row in connection.execute(sql)]

snapshot = {
    "settings": rows("SELECT key, value FROM settings WHERE key <> 'last_spoken_line' ORDER BY key"),
    "relays": rows("""
        SELECT id, line, message, type, priority, session, app, cwd, url, status
        FROM relays
        ORDER BY id
    """),
}
print(json.dumps(snapshot, sort_keys=True))
PY
}

assert_db_equal() {
  local label="$1"
  local oracle_db="$2"
  local swift_db="$3"
  local oracle_snapshot
  local swift_snapshot

  oracle_snapshot="$(db_snapshot "$oracle_db")"
  swift_snapshot="$(db_snapshot "$swift_db")"
  assert_equal "$label database" "$oracle_snapshot" "$swift_snapshot"
  log_pass "$label database"
}

supports_app_claim_next() {
  local side="$1"
  local bin="$2"
  local db="$RUN_ROOT/app-helper-probe/$side/relay.db"
  mkdir -p "$(dirname "$db")"

  run_cli_auth "$side" "$bin" "$db" app-claim-next
  ! grep -q "unknown command" "$RUN_ROOT/$side.err"
}

fresh_pair_vars() {
  local name="$1"
  local dir="$RUN_ROOT/$name"
  rm -rf "$dir"
  mkdir -p "$dir/oracle" "$dir/swift"
  ORACLE_DB="$dir/oracle/relay.db"
  SWIFT_DB="$dir/swift/relay.db"
}

require_executable "$ORACLE"
require_executable "$SWIFT_RELAY"
require_command python3

rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT"

fresh_pair_vars version
assert_text_command "version flag" "$ORACLE_DB" "$SWIFT_DB" --version
assert_text_command "version command" "$ORACLE_DB" "$SWIFT_DB" version

fresh_pair_vars queue
queue_oracle_db="$ORACLE_DB"
queue_swift_db="$SWIFT_DB"
assert_text_command "initial state" "$queue_oracle_db" "$queue_swift_db" state
assert_text_command "initial list" "$queue_oracle_db" "$queue_swift_db" list
assert_text_command "enqueue" "$queue_oracle_db" "$queue_swift_db" \
  --line "Brain" \
  --message "  Hello   relay  " \
  --type complete \
  --priority high \
  --session sess-1 \
  --app Copilot \
  --cwd "$ROOT" \
  --url "https://example.invalid/item"
assert_text_command "list after enqueue" "$queue_oracle_db" "$queue_swift_db" list
assert_json_command "status after enqueue" status "$queue_oracle_db" "$queue_swift_db" status
assert_db_equal "queue sequence" "$queue_oracle_db" "$queue_swift_db"

fresh_pair_vars state
state_oracle_db="$ORACLE_DB"
state_swift_db="$SWIFT_DB"
assert_text_command "ready" "$state_oracle_db" "$state_swift_db" ready
assert_text_command "mute while ready" "$state_oracle_db" "$state_swift_db" mute
assert_text_command "ready while muted" "$state_oracle_db" "$state_swift_db" ready
assert_text_command "unmute" "$state_oracle_db" "$state_swift_db" unmute
assert_text_command "focus" "$state_oracle_db" "$state_swift_db" focus
assert_text_command "line set positional" "$state_oracle_db" "$state_swift_db" line "Tri-State Relay Service"
assert_text_command "line get" "$state_oracle_db" "$state_swift_db" line
assert_text_command "combiner default" "$state_oracle_db" "$state_swift_db" combiner
assert_text_command "combiner custom" "$state_oracle_db" "$state_swift_db" combiner --command "printf <input>"
assert_text_command "state with combiner" "$state_oracle_db" "$state_swift_db" state
assert_json_command "settings with combiner" exact "$state_oracle_db" "$state_swift_db" settings --combiner-command "printf <input>"
assert_db_equal "state/settings sequence" "$state_oracle_db" "$state_swift_db"

fresh_pair_vars mutations
mut_oracle_db="$ORACLE_DB"
mut_swift_db="$SWIFT_DB"
assert_text_command "enqueue first mutation relay" "$mut_oracle_db" "$mut_swift_db" --line Brain --message First --priority low
assert_text_command "enqueue second mutation relay" "$mut_oracle_db" "$mut_swift_db" --line Brain --message Second --priority high
assert_text_command "skip next" "$mut_oracle_db" "$mut_swift_db" skip-next
assert_text_command "clear line" "$mut_oracle_db" "$mut_swift_db" clear-line --line Brain
assert_text_command "clear" "$mut_oracle_db" "$mut_swift_db" clear
assert_db_equal "mutation sequence" "$mut_oracle_db" "$mut_swift_db"

fresh_pair_vars install
install_dir="$RUN_ROOT/install"
mkdir -p "$install_dir/oracle-target" "$install_dir/swift-target"
assert_json_command "cli-status missing target" install "$ORACLE_DB" "$SWIFT_DB" cli-status \
  --source "$ORACLE" \
  --target "$install_dir/oracle-target/relay"
run_cli oracle "$ORACLE" "$ORACLE_DB" install-cli --source "$ORACLE" --target "$install_dir/oracle-target/relay"
run_cli swift "$SWIFT_RELAY" "$SWIFT_DB" install-cli --source "$SWIFT_RELAY" --target "$install_dir/swift-target/relay"
assert_equal "install-cli exit" "$(code_of oracle)" "$(code_of swift)"
assert_equal "install-cli stderr" "$(stderr_of oracle)" "$(stderr_of swift)"
json_compare "install-cli" install >/dev/null
log_pass "install-cli"

fresh_pair_vars app-helpers
app_oracle_db="$ORACLE_DB"
app_swift_db="$SWIFT_DB"
assert_text_command "app helper enqueue" "$app_oracle_db" "$app_swift_db" --line Brain --message "Needs hearing"
assert_auth_json_command "app claim next" claim "$app_oracle_db" "$app_swift_db" app-claim-next
assert_auth_text_command "app mark heard" "$app_oracle_db" "$app_swift_db" app-mark-heard --id 1
assert_db_equal "app helper sequence" "$app_oracle_db" "$app_swift_db"

fresh_pair_vars speech-settings
assert_json_command "settings speech command" exact "$ORACLE_DB" "$SWIFT_DB" settings --speech-command "/usr/bin/say -v Samantha <message>"
assert_db_equal "speech settings sequence" "$ORACLE_DB" "$SWIFT_DB"

printf 'swift CLI parity harness: %d passed, %d skipped, %d gaps (strict=%s)\n' "$pass_count" "$skip_count" "$gap_count" "$STRICT"
