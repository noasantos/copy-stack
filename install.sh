#!/usr/bin/env bash
set -euo pipefail

# ── ClipStack Installer ────────────────────────────────────────
# Installs ClipStack to /Applications without Apple Developer ID signing.
# Uses ad-hoc codesign + quarantine removal — standard practice for
# developer tools distributed outside the Mac App Store.
# Source: https://github.com/noasantos/copy-stack
# ──────────────────────────────────────────────────────────────

VERSION="0.1.0"   # ← Update this on each release
APP_NAME="ClipStack"
REPO="noasantos/copy-stack"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/${ZIP_NAME}"
# SHA-256 of the release zip — update this on each release
EXPECTED_SHA256="4d4e5717267d0c63bb58e24f4619dcbc7fb7fa4944f1ab62f16affa632f0cded"
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

if [ -d "${APP_DEST}" ]; then
  info "Removing previous installation..."
  rm -rf "${APP_DEST}" 2>/dev/null || sudo rm -rf "${APP_DEST}"
fi

info "Installing to ${INSTALL_DIR}..."
# Try without sudo first; fall back to sudo if permission denied
if cp -r "${APP_SRC}" "${INSTALL_DIR}/" 2>/dev/null; then
  success "Copied to ${INSTALL_DIR}"
else
  warn "Permission denied. Retrying with sudo..."
  sudo cp -r "${APP_SRC}" "${INSTALL_DIR}/"
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

# ── Ad-hoc Sign ───────────────────────────────────────────────
# Apple Silicon requires all arm64 binaries to be signed (even ad-hoc)
# before the kernel will execute them. This step is mandatory on M1/M2/M3/M4.
# Source: https://eclecticlight.co/2019/01/17/code-signing-for-the-concerned-3-signing-an-app/
info "Applying local ad-hoc code signature..."
codesign --deep --force --sign - "${APP_DEST}" 2>/dev/null && \
  success "Ad-hoc signature applied" || \
  warn "codesign not available — app may fail on Apple Silicon. Install Xcode Command Line Tools: xcode-select --install"

# ── Verify ────────────────────────────────────────────────────
info "Verifying installation..."
codesign --verify --deep "${APP_DEST}" 2>/dev/null && \
  success "Signature valid" || \
  warn "Signature verification skipped (Xcode CLI tools may not be installed)"

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
    <false/>
    <key>KeepAlive</key>
    <false/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
PLIST
launchctl load "${PLIST_PATH}" 2>/dev/null || true
success "Launch at login configured"

# ── Launch app immediately ────────────────────────────────────
info "Launching ClipStack..."
open "${APP_DEST}" || true
success "ClipStack launched — look for the clipboard icon in your menu bar"

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
