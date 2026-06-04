#!/bin/bash
set -e

assert_relay_processor_not_bundled() {
  local app_path="$1"
  
  if [ ! -d "$app_path" ]; then
    echo "Error: App path does not exist: $app_path"
    exit 1
  fi
  
  # Find any file or directory named 'relay-processor'
  local matches=$(find "$app_path" -name "relay-processor")
  
  if [ -n "$matches" ]; then
    echo "Error: relay-processor must not be bundled in the macOS app: $matches"
    exit 1
  fi
}

# If executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" -ef "$0" ]; then
  if [ -z "$1" ]; then
    echo "Usage: $0 <app_path>"
    exit 1
  fi
  assert_relay_processor_not_bundled "$1"
fi
