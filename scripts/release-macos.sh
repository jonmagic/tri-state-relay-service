#!/usr/bin/env bash
set -euo pipefail

notary_profile="${TSRS_NOTARYTOOL_PROFILE:-tsrs}"

echo "Releasing macOS app with notarytool profile: $notary_profile"
TSRS_NOTARYTOOL_PROFILE="$notary_profile" scripts/package-macos-direct.sh
