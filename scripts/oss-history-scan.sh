#!/usr/bin/env bash
set -euo pipefail

git rev-list --all | while read -r revision; do
  git grep -I -n -E \
    '(/Users/|hooks\.slack|xox[baprs]-|gh[pousr]_[A-Za-z0-9_]+|AKIA[0-9A-Z]{16}|BEGIN (RSA|OPENSSH|EC|DSA|PRIVATE) KEY)' \
    "$revision" -- . ':(exclude)dist' ':(exclude)*.png' ':(exclude)*.xcuserstate' || true
done

