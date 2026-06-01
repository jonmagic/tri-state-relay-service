#!/usr/bin/env bash
set -euo pipefail

npm run build:native

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

TSRS_DB_PATH="$tmpdir/relay.db" ./dist/native/relay --line Brain --message "Native smoke test."
TSRS_DB_PATH="$tmpdir/relay.db" ./dist/native/relay list
