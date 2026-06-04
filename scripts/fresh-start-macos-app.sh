#!/usr/bin/env bash
set -e

APP_PATH="dist/macos/Tri-State Relay Service.app"
RELAY_CLI_PATH="${APP_PATH}/Contents/MacOS/relay"

if [ ! -x "${RELAY_CLI_PATH}" ]; then
  echo "Error: bundled relay CLI missing: ${RELAY_CLI_PATH}"
  echo "Run scripts/build-macos.sh direct first."
  exit 1
fi

"${RELAY_CLI_PATH}" first-start dev-reset-database --confirm
scripts/restart-macos-app.sh
