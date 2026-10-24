#!/usr/bin/env bash
# Generates Anixart.xcodeproj from project.yml and opens it.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is not installed. Install it with:" >&2
    echo "  brew install xcodegen" >&2
    exit 1
fi

xcodegen generate
echo "Generated Anixart.xcodeproj"

if [[ "${1:-}" != "--no-open" ]]; then
    open Anixart.xcodeproj
fi
