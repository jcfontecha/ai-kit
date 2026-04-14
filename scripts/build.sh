#!/usr/bin/env bash
set -euo pipefail

verbose=false
if [[ "${1:-}" == "--verbose" ]]; then
  verbose=true
  set -x
fi

swift build
xcb demo-swiftui
