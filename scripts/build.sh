#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: $0 <version>  e.g. $0 0.1.0}"
SCHEME="ClipStack"
CONFIGURATION="Release"
BUILD_DIR="$(pwd)/build"
APP_NAME="ClipStack"
ZIP_NAME="${APP_NAME}-${VERSION}.zip"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

echo "════════════════════════════════════════"
echo "  ClipStack build — v${VERSION}"
echo "  Universal binary: arm64 + x86_64"
echo "════════════════════════════════════════"

# Clean previous build artifacts for this version
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/output"

echo "→ Building universal binary..."
xcodebuild \
  -project "${SCHEME}.xcodeproj" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${BUILD_DIR}/derived" \
  ONLY_ACTIVE_ARCH=NO \
  ARCHS="arm64 x86_64" \
  VALID_ARCHS="arm64 x86_64" \
  MARKETING_VERSION="${VERSION}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_REQUIRED=NO \
  SYMROOT="${BUILD_DIR}/output" \
  build

APP_PATH="${BUILD_DIR}/output/${CONFIGURATION}/${APP_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
  echo "ERROR: App bundle not found at expected path: ${APP_PATH}"
  echo "Check SYMROOT and scheme output path in your Xcode project."
  exit 1
fi

echo "→ Verifying universal binary..."
ARCHS_FOUND=$(lipo -archs "${APP_PATH}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true)
echo "   Architectures: ${ARCHS_FOUND}"
if [[ "${ARCHS_FOUND}" != *"arm64"* ]] || [[ "${ARCHS_FOUND}" != *"x86_64"* ]]; then
  echo "WARNING: Binary is not universal. Found: ${ARCHS_FOUND}"
  echo "Continuing — for personal use this may be acceptable."
fi

echo "→ Ad-hoc signing..."
# Ad-hoc sign satisfies Apple Silicon kernel requirement without Developer ID
# Source: https://eclecticlight.co/2019/01/17/code-signing-for-the-concerned-3-signing-an-app/
codesign --deep --force --sign - "${APP_PATH}"

echo "→ Verifying signature..."
codesign --verify --deep --strict "${APP_PATH}" && echo "   Signature: OK"

DERIVED_APP_PATH="${BUILD_DIR}/derived/Build/Products/${CONFIGURATION}/${APP_NAME}.app"
if [ "${APP_PATH}" != "${DERIVED_APP_PATH}" ]; then
  mkdir -p "$(dirname "${DERIVED_APP_PATH}")"
  rm -rf "${DERIVED_APP_PATH}"
  ditto "${APP_PATH}" "${DERIVED_APP_PATH}"
fi

echo "→ Packaging with ditto (preserves xattrs and code seal)..."
# ditto must be used instead of plain zip to preserve macOS extended attributes
# Source: https://github.com/n8felton/proper-packaging-principles
ditto -c -k --keepParent "${APP_PATH}" "${BUILD_DIR}/${ZIP_NAME}"

echo "→ Computing SHA-256..."
SHA256=$(shasum -a 256 "${BUILD_DIR}/${ZIP_NAME}" | awk '{print $1}')

echo ""
echo "════════════════════════════════════════"
echo "  BUILD COMPLETE"
echo "  Artifact : build/${ZIP_NAME}"
echo "  SHA-256  : ${SHA256}"
echo ""
echo "  Next steps:"
echo "  1. git tag v${VERSION} && git push origin v${VERSION}"
echo "  2. Create GitHub Release for v${VERSION}"
echo "  3. Upload build/${ZIP_NAME} to the release"
echo "  4. Update install.sh VERSION variable to ${VERSION}"
echo "  5. Commit and push install.sh"
echo "════════════════════════════════════════"
