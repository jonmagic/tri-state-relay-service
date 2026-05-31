#!/usr/bin/env bash
set -euo pipefail

npm run build:native

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

TSRS_DB_PATH="$tmpdir/voicemail.db" ./dist/native/voicemail --line Brain --message "Native smoke test."
TSRS_DB_PATH="$tmpdir/voicemail.db" ./dist/native/voicemail list

