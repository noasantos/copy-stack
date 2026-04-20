#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -d "$XCODE_DIR" ]]; then
  echo "Xcode not found at $XCODE_DIR" >&2
  echo "Install Xcode or run with DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer" >&2
  exit 1
fi

export DEVELOPER_DIR="$XCODE_DIR"

bash "$ROOT_DIR/scripts/lint-release.sh"

xcodebuild test \
  -project "$ROOT_DIR/ClipStack.xcodeproj" \
  -scheme ClipStack \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$ROOT_DIR/build"
