#!/bin/bash
set -e

APP_PATH="dist/macos/Tri-State Relay Service.app"
EXECUTABLE_PATH="${APP_PATH}/Contents/MacOS/Tri-State Relay Service"

if [ ! -x "${EXECUTABLE_PATH}" ]; then
  echo "Error: rebuilt app executable missing: ${EXECUTABLE_PATH}"
  exit 1
fi

PIDS=$(pgrep -f "${EXECUTABLE_PATH}" || true)

if [ -n "$PIDS" ]; then
  for PID in $PIDS; do
    kill "$PID" || true
  done
  sleep 1
  PIDS_AFTER=$(pgrep -f "${EXECUTABLE_PATH}" || true)
  if [ -n "$PIDS_AFTER" ]; then
    for PID in $PIDS_AFTER; do
      kill -9 "$PID" || true
    done
  fi
fi

open "${APP_PATH}"
sleep 2

NEW_PIDS=$(pgrep -f "${EXECUTABLE_PATH}" || true)

if [ -z "$NEW_PIDS" ]; then
  echo "Error: rebuilt app did not start"
  exit 1
fi

# Just print the first PID
FIRST_PID=$(echo "$NEW_PIDS" | head -n 1)
echo "running ${FIRST_PID} ${EXECUTABLE_PATH}"
