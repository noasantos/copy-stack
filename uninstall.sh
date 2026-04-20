#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ClipStack"
BUNDLE_ID="com.clipstack.app"

echo "  → Stopping ClipStack if running..."
osascript -e 'quit app "ClipStack"' 2>/dev/null || true
sleep 1

echo "  → Removing application bundle..."
if [ -d "/Applications/${APP_NAME}.app" ]; then
  rm -rf "/Applications/${APP_NAME}.app"
  echo "  ✓ Removed /Applications/${APP_NAME}.app"
else
  echo "  ⚠ /Applications/${APP_NAME}.app not found — skipping"
fi

echo "  → Removing application data..."
rm -rf ~/Library/Application\ Support/ClipStack 2>/dev/null && \
  echo "  ✓ Removed ~/Library/Application Support/ClipStack" || true

echo "  → Removing preferences..."
rm -f ~/Library/Preferences/${BUNDLE_ID}.plist 2>/dev/null && \
  echo "  ✓ Removed preferences" || true
defaults delete ${BUNDLE_ID} 2>/dev/null || true

echo "  → Removing caches..."
rm -rf ~/Library/Caches/${BUNDLE_ID} 2>/dev/null || true

echo ""
echo "  ✓ ClipStack has been fully uninstalled."
echo ""
