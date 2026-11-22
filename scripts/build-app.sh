#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE_NAME="ELMUsageTracker"
APP_BUNDLE_NAME="ELM API Tracker"
LEGACY_BUNDLE_NAME="ELMUsageTracker"
ARTIFACT_PREFIX="ELM-API-Tracker"
BUNDLE_ID="uk.ac.edina.elm-api-usage-tracker"
VERSION="1.0.0"

INSTALL=false
OPEN_APP=false
UNIVERSAL=false
PACKAGE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL=true
      shift
      ;;
    --open)
      OPEN_APP=true
      shift
      ;;
    --universal)
      UNIVERSAL=true
      shift
      ;;
    --package)
      PACKAGE=true
      shift
      ;;
    --version)
      if [[ $# -lt 2 ]]; then
        echo "Error: --version requires an argument (e.g. 1.0.0)" >&2
        exit 1
      fi
      VERSION="${2#v}"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--universal] [--version X.Y.Z] [--package] [--install] [--open]"
      echo "  --universal      Build a universal (arm64 + x86_64) binary"
      echo "  --version X.Y.Z  Set CFBundleShortVersionString (default: ${VERSION})"
      echo "  --package        Create release .dmg, .zip, and SHA256SUMS.txt in dist/"
      echo "  --install        Copy built .app bundle into /Applications"
      echo "  --open           Quit any existing instance and launch the newly built app"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

ARCH_FLAGS=()
ARCH_LABEL="arm64"
if [[ "${UNIVERSAL}" == true ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
  ARCH_LABEL="universal"
else
  ARCH_LABEL="$(uname -m)"
fi

echo "Building ${APP_BUNDLE_NAME} v${VERSION} (${ARCH_LABEL}, release)..."
cd "${ROOT_DIR}"
swift build -c release "${ARCH_FLAGS[@]}"

BIN_PATH="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/${EXECUTABLE_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "Error: compiled binary not found at ${BIN_PATH}" >&2
  exit 1
fi

DIST_DIR="${ROOT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_BUNDLE_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${DIST_DIR}/${LEGACY_BUNDLE_NAME}.app" "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BIN_PATH}" "${MACOS_DIR}/${EXECUTABLE_NAME}"
chmod +x "${MACOS_DIR}/${EXECUTABLE_NAME}"

echo "Generating AppIcon.icns..."
swift "${ROOT_DIR}/scripts/generate-icon.swift" "${RESOURCES_DIR}/AppIcon.icns"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_BUNDLE_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_BUNDLE_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "Ad-hoc signing ${APP_DIR}..."
xattr -cr "${APP_DIR}"
codesign --force --deep --sign - "${APP_DIR}"
codesign --verify --verbose "${APP_DIR}"

if [[ "${PACKAGE}" == true ]]; then
  ZIP_NAME="${ARTIFACT_PREFIX}-v${VERSION}-${ARCH_LABEL}.zip"
  DMG_NAME="${ARTIFACT_PREFIX}-v${VERSION}-${ARCH_LABEL}.dmg"
  ZIP_PATH="${DIST_DIR}/${ZIP_NAME}"
  DMG_PATH="${DIST_DIR}/${DMG_NAME}"
  CHECKSUMS_PATH="${DIST_DIR}/SHA256SUMS.txt"

  rm -f "${ZIP_PATH}" "${DMG_PATH}" "${CHECKSUMS_PATH}"

  echo "Creating ${ZIP_NAME}..."
  ditto -c -k --sequesterRsrc --keepParent "${APP_DIR}" "${ZIP_PATH}"

  echo "Creating ${DMG_NAME}..."
  DMG_STAGE="$(mktemp -d)"
  trap 'rm -rf "${DMG_STAGE}"' EXIT
  cp -R "${APP_DIR}" "${DMG_STAGE}/"
  ln -s /Applications "${DMG_STAGE}/Applications"
  hdiutil create \
    -volname "${APP_BUNDLE_NAME}" \
    -srcfolder "${DMG_STAGE}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null
  rm -rf "${DMG_STAGE}"
  trap - EXIT

  echo "Generating SHA256SUMS.txt..."
  (
    cd "${DIST_DIR}"
    shasum -a 256 "${DMG_NAME}" "${ZIP_NAME}" > "${CHECKSUMS_PATH}"
  )

  echo "Packaged artifacts:"
  echo "  ${DMG_PATH}"
  echo "  ${ZIP_PATH}"
  echo "  ${CHECKSUMS_PATH}"
fi

TARGET_APP="${APP_DIR}"
if [[ "${INSTALL}" == true ]]; then
  DEST_APP="/Applications/${APP_BUNDLE_NAME}.app"
  LEGACY_DEST_APP="/Applications/${LEGACY_BUNDLE_NAME}.app"
  echo "Installing to ${DEST_APP}..."
  rm -rf "${LEGACY_DEST_APP}" "${DEST_APP}"
  cp -R "${APP_DIR}" "${DEST_APP}"
  TARGET_APP="${DEST_APP}"
fi

echo "Done: ${TARGET_APP}"

if [[ "${OPEN_APP}" == true ]]; then
  killall "${EXECUTABLE_NAME}" 2>/dev/null || true
  sleep 0.2
  echo "Launching ${TARGET_APP}..."
  open "${TARGET_APP}"
fi
