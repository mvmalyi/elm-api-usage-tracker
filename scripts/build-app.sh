#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXECUTABLE_NAME="ELMUsageTracker"
APP_BUNDLE_NAME="ELM API Tracker"
LEGACY_BUNDLE_NAME="ELMUsageTracker"
BUNDLE_ID="uk.ac.edina.elm-api-usage-tracker"
VERSION="1.0.0"

INSTALL=false
OPEN_APP=false

for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=true ;;
    --open) OPEN_APP=true ;;
    -h|--help)
      echo "Usage: $0 [--install] [--open]"
      echo "  --install  Copy built .app bundle into /Applications"
      echo "  --open     Quit any existing instance and launch the newly built app"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

echo "Building ${APP_BUNDLE_NAME} (release)..."
cd "${ROOT_DIR}"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/${EXECUTABLE_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
  echo "Error: compiled binary not found at ${BIN_PATH}" >&2
  exit 1
fi

APP_DIR="${ROOT_DIR}/dist/${APP_BUNDLE_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${ROOT_DIR}/dist/${LEGACY_BUNDLE_NAME}.app" "${APP_DIR}"
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
    <string>1</string>
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
