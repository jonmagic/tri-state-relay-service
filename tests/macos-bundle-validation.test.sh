#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATION_SCRIPT="$SCRIPT_DIR/../scripts/macos-bundle-validation.sh"
FIXTURE_ROOT="$SCRIPT_DIR/../dist/test-bundle-validation"

setup() {
  rm -rf "$FIXTURE_ROOT"
  mkdir -p "$FIXTURE_ROOT"
}

teardown() {
  rm -rf "$FIXTURE_ROOT"
}

fixture_app() {
  local name="$1"
  local app_path="$FIXTURE_ROOT/$name"
  mkdir -p "$app_path/Contents/MacOS"
  mkdir -p "$app_path/Contents/Resources/Nested"
  echo "$app_path"
}

run_test() {
  setup
  local name="$1"
  local description="$2"
  
  echo "Testing: $description"
  
  if $name; then
    echo "✅ Passed: $description"
  else
    echo "❌ Failed: $description"
    teardown
    exit 1
  fi
}

test_accepts_good() {
  local app_path=$(fixture_app "Good.app")
  
  if "$VALIDATION_SCRIPT" "$app_path" > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

test_rejects_bad() {
  local app_path=$(fixture_app "Bad.app")
  touch "$app_path/Contents/Resources/Nested/relay-processor"
  
  if ! "$VALIDATION_SCRIPT" "$app_path" > /dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

echo "Running macOS bundle validation tests..."
run_test test_accepts_good "Accepts app bundles without relay-processor"
run_test test_rejects_bad "Rejects relay-processor anywhere in the app bundle"

teardown
echo "All tests passed!"
