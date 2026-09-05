#!/usr/bin/env bash
set -euo pipefail

# ── ClipStack Installer ────────────────────────────────────────
# Installs ClipStack to /Applications without Apple Developer ID signing.
# Uses ad-hoc codesign + quarantine removal — standard practice for
# developer tools distributed outside the Mac App Store.
# Source: https://github.com/proto-hatchery/copy-stack
# ──────────────────────────────────────────────────────────────

LATEST_VERSION="0.5.0"   # ← Update this on each release
VERSION="${CLIPSTACK_VERSION:-${1:-${LATEST_VERSION}}}"
APP_NAME="ClipStack"
REPO="proto-hatchery/copy-stack"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ZIP_NAME}"
case "${VERSION}" in
  0.1.0)
    EXPECTED_SHA256="4d4e5717267d0c63bb58e24f4619dcbc7fb7fa4944f1ab62f16affa632f0cded"
    ;;
  0.1.1)
    EXPECTED_SHA256="2ed4b3f51d8bec88cd2df652be21f07e17c20de8814bc44ec45fc9f1d9670fb3"
    ;;
  0.2.0)
    EXPECTED_SHA256="2639be8aacc270890c971fb37c520fb23034a87253d28d34bb5e0f08f26b1a32"
    ;;
  0.2.1)
    EXPECTED_SHA256="71add0060db6b44363b14347f7088d23771164d965466ac8213f58e7829ab686"
    ;;
  0.3.0)
    EXPECTED_SHA256="8fdb4b8713b56efc1692b810683600be86fe188a7a39b9abcd34184404eb6ed6"
    ;;
  0.4.0)
    EXPECTED_SHA256="74a6e8f25a6e527d8617051eed03ca1c13dcc64eb893c77983786a452c9098ab"
    ;;
  0.4.1)
    EXPECTED_SHA256="7326237bcd5ecb4c26096b2dbd487eb3f5d3968a9785ebb5f7f35e6a6aa2db28"
    ;;
  0.4.2)
    EXPECTED_SHA256="dfce3c8b5122d638453797b1f2cba4f9f6270c22c8d10e7329611c05d3141a83"
    ;;
  0.5.0)
    EXPECTED_SHA256="0f92a02b5e9f8095388bcde8d60eca6fd0cd80464fcc0dece7185ee3be199a52"
    ;;
  *)
    echo "  ✗ ERROR: Unsupported ClipStack version: ${VERSION}" >&2
    echo "  Supported versions: 0.1.0, 0.1.1, 0.2.0, 0.2.1, 0.3.0, 0.4.0, 0.4.1, 0.4.2, 0.5.0" >&2
    exit 1
    ;;
esac
INSTALL_DIR="/Applications"
TMP_DIR=$(mktemp -d)

if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  LOCAL_ZIP="${SCRIPT_DIR}/build/${ZIP_NAME}"
  if [ -f "${LOCAL_ZIP}" ]; then
    DOWNLOAD_URL="file://${LOCAL_ZIP}"
  fi
fi

# ── Cleanup on exit ───────────────────────────────────────────
cleanup() { rm -rf "${TMP_DIR}"; }
trap cleanup EXIT

# ── Helpers ───────────────────────────────────────────────────
info()    { echo "  → $*"; }
success() { echo "  ✓ $*"; }
warn()    { echo "  ⚠ $*" >&2; }
abort()   { echo "  ✗ ERROR: $*" >&2; exit 1; }

# ── Preflight ─────────────────────────────────────────────────
echo ""
echo "  ┌─────────────────────────────────────┐"
echo "  │  ClipStack ${VERSION} Installer             │"
echo "  │  macOS menu bar clipboard manager   │"
echo "  └─────────────────────────────────────┘"
echo ""

# macOS version check
MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [ "${MACOS_MAJOR}" -lt 13 ]; then
  abort "ClipStack requires macOS 13 (Ventura) or later. Found: $(sw_vers -productVersion)"
fi

ARCH=$(uname -m)
case "${ARCH}" in
  arm64|x86_64)
    info "Detected architecture: ${ARCH}"
    ;;
  *)
    warn "Unexpected architecture: ${ARCH}. Continuing because the app archive is universal."
    ;;
esac

# Check for curl
command -v curl >/dev/null 2>&1 || abort "curl is required but not found."
command -v shasum >/dev/null 2>&1 || abort "shasum is required but not found."

# ── Download ──────────────────────────────────────────────────
info "Downloading ClipStack ${VERSION}..."
curl -fsSL --progress-bar "${DOWNLOAD_URL}" -o "${TMP_DIR}/${ZIP_NAME}" || \
  abort "Download failed. Check your internet connection or visit: https://github.com/${REPO}/releases"

# ── SHA-256 Verification ──────────────────────────────────────
info "Verifying download integrity (SHA-256)..."
ACTUAL_SHA256=$(shasum -a 256 "${TMP_DIR}/${ZIP_NAME}" | awk '{print $1}')
if [ "${ACTUAL_SHA256}" != "${EXPECTED_SHA256}" ]; then
  abort "SHA-256 mismatch.\n  Expected : ${EXPECTED_SHA256}\n  Got      : ${ACTUAL_SHA256}\n  The download may be corrupt or tampered with."
fi
success "Integrity verified"

# ── Extract ───────────────────────────────────────────────────
info "Extracting..."
if command -v ditto >/dev/null 2>&1; then
  # ditto preserves macOS extended attributes and resource forks
  ditto -x -k "${TMP_DIR}/${ZIP_NAME}" "${TMP_DIR}/extracted/"
else
  unzip -q "${TMP_DIR}/${ZIP_NAME}" -d "${TMP_DIR}/extracted/"
fi

APP_SRC="${TMP_DIR}/extracted/${APP_NAME}.app"
[ -d "${APP_SRC}" ] || abort "Expected ${APP_NAME}.app not found in archive."

# ── Install ───────────────────────────────────────────────────
APP_DEST="${INSTALL_DIR}/${APP_NAME}.app"
USER_DOMAIN="gui/$(id -u)"
EXISTING_PLIST_PATH="${HOME}/Library/LaunchAgents/com.clipstack.app.plist"

launchctl bootout "${USER_DOMAIN}/com.clipstack.app" 2>/dev/null || true
launchctl unload "${EXISTING_PLIST_PATH}" 2>/dev/null || true
pkill -x "${APP_NAME}" 2>/dev/null || true

if [ -d "${APP_DEST}" ]; then
  info "Removing previous installation..."
  rm -rf "${APP_DEST}" 2>/dev/null || sudo rm -rf "${APP_DEST}"
fi

info "Installing to ${INSTALL_DIR}..."
# Try without sudo first; fall back to sudo if permission denied
if ditto "${APP_SRC}" "${APP_DEST}" 2>/dev/null; then
  success "Copied to ${INSTALL_DIR}"
else
  warn "Permission denied. Retrying with sudo..."
  sudo ditto "${APP_SRC}" "${APP_DEST}"
  success "Copied to ${INSTALL_DIR} (via sudo)"
fi

# ── Remove Quarantine ─────────────────────────────────────────
# The quarantine xattr is set by macOS on all downloaded content.
# Removing it allows Gatekeeper to skip the "unknown developer" prompt.
# This is the documented mechanism for distributing apps to technical users
# who are explicitly opting in.
# Source: https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac
info "Removing quarantine attribute..."
xattr -dr com.apple.quarantine "${APP_DEST}" 2>/dev/null || true
success "Quarantine removed"

# ── Verify signed release ─────────────────────────────────────
# Preserve the exact ad-hoc signature shipped in the verified archive. Re-signing
# during every update changes the identity macOS associates with Accessibility.
info "Verifying release signature..."
codesign --verify --deep --strict "${APP_DEST}" 2>/dev/null || \
  abort "The installed app has an invalid code signature."
success "Signature valid"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "${LSREGISTER}" ]; then
  "${LSREGISTER}" -f "${APP_DEST}"
fi

# ── Launch at Login (LaunchAgent) ─────────────────────────────
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
PLIST_PATH="${LAUNCH_AGENTS_DIR}/com.clipstack.app.plist"

info "Configuring launch at login..."
mkdir -p "${LAUNCH_AGENTS_DIR}"
cat > "${PLIST_PATH}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.clipstack.app</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/ClipStack.app/Contents/MacOS/ClipStack</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
PLIST
launchctl bootout "${USER_DOMAIN}/com.clipstack.app" 2>/dev/null || true
launchctl enable "${USER_DOMAIN}/com.clipstack.app"
if launchctl bootstrap "${USER_DOMAIN}" "${PLIST_PATH}" 2>/dev/null; then
  launchctl kickstart -k "${USER_DOMAIN}/com.clipstack.app" 2>/dev/null || true
  success "Launch at login and automatic restart configured"
else
  launchctl load "${PLIST_PATH}" 2>/dev/null || true
  success "Launch at login configured"
fi

# ── Launch app immediately ────────────────────────────────────
info "Launching ClipStack..."
APP_EXEC="${APP_DEST}/Contents/MacOS/${APP_NAME}"
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if pgrep -f "^${APP_EXEC}$" >/dev/null 2>&1; then
    success "ClipStack launched by its background agent"
    break
  fi
  sleep 1
done
pgrep -f "^${APP_EXEC}$" >/dev/null 2>&1 || \
  abort "ClipStack did not start through its background agent."

# ── Done ──────────────────────────────────────────────────────
echo ""
echo "  ✓ ClipStack ${VERSION} installed successfully"
echo ""
echo "  Launch: open /Applications/ClipStack.app"
echo "  Or:     open -a ClipStack"
echo "  Or:     Spotlight → ClipStack"
echo ""
echo "  ClipStack will appear in your menu bar."
echo "  Clipboard history is stored locally at:"
echo "    ~/Library/Application Support/ClipStack/"
echo ""
echo "  To uninstall:"
echo "    curl -fsSL https://raw.githubusercontent.com/${REPO}/main/uninstall.sh | bash"
echo ""
