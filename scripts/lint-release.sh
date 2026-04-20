#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLACEHOLDER="YOUR_""ORG"
NETWORK_PATTERN="URLSession|URLRequest|WKWebView|NWConnection|CFSocketCreate|import Network"

PLACEHOLDER_HITS=$(grep -RIn "${PLACEHOLDER}" "${ROOT_DIR}" \
  --exclude-dir=.git \
  --exclude-dir=build || true)

if [[ -n "${PLACEHOLDER_HITS}" ]]; then
  echo "ERROR: Release placeholder detected:" >&2
  echo "${PLACEHOLDER_HITS}" >&2
  exit 1
fi

NETWORK_HITS=$(grep -RInE "${NETWORK_PATTERN}" "${ROOT_DIR}/ClipStack" \
  --include="*.swift" || true)

if [[ -n "${NETWORK_HITS}" ]]; then
  echo "ERROR: Network API detected in app source:" >&2
  echo "${NETWORK_HITS}" >&2
  exit 1
fi
