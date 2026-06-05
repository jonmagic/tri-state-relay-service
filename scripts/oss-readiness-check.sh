#!/usr/bin/env bash
set -euo pipefail

ruby -e 'require "yaml"; Dir[".github/**/*.yml", ".github/**/*.yaml"].each { |path| YAML.load_file(path); puts "YAML OK #{path}" }'

if grep -R -n \
  --exclude-dir=.git \
  --exclude-dir=dist \
  --exclude-dir=node_modules \
  --exclude='*.png' \
  --exclude='*.xcuserstate' \
  --exclude='oss-readiness-check.sh' \
  --exclude='oss-history-scan.sh' \
  -E '(/Users/|hooks\.slack|xox[baprs]-|gh[pousr]_[A-Za-z0-9_]+|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH|EC|DSA|PRIVATE) KEY)' .; then
  echo "Potential private path or secret-looking material found; review before publication." >&2
  exit 1
fi

if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source . --no-banner --redact
else
  echo "gitleaks not installed; install it before final publication scanning." >&2
fi

git --no-pager diff --check
