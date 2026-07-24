#!/bin/sh
set -eu

APP_NAME="GlancePane"
BUNDLE_ID="dev.danbao.glancepane"
MIN_MACOS_VERSION="14.0"
ARCH="${ARCH:-$(uname -m)}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

APP_VERSION="${APP_VERSION:-}"
if [ -z "${APP_VERSION}" ]; then
  if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
    TAG_VERSION="${GITHUB_REF_NAME:-}"
  else
    TAG_VERSION="$(git -C "${ROOT_DIR}" describe --tags --exact-match --match 'v[0-9]*' 2>/dev/null || true)"
  fi
  APP_VERSION="${TAG_VERSION#v}"
fi
if [ -z "${APP_VERSION}" ]; then
  APP_VERSION="0.1.0"
fi

DEFAULT_BUILD_NUMBER="$(git -C "${ROOT_DIR}" rev-list --count HEAD 2>/dev/null || echo 1)"
BUILD_NUMBER="${BUILD_NUMBER:-${DEFAULT_BUILD_NUMBER}}"
BUILD_DIR="${ROOT_DIR}/.build/${BUILD_CONFIGURATION}"
APP_DIR="${APP_DIR:-${BUILD_DIR}/${APP_NAME}.app}"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
HELPERS_DIR="${CONTENTS_DIR}/Library/Helpers"
LAUNCH_AGENTS_DIR="${CONTENTS_DIR}/Library/LaunchAgents"
GENERATED_ICON="${BUILD_DIR}/AppIcon.icns"

rm -rf "${APP_DIR}"
mkdir -p "${BUILD_DIR}" "${MACOS_DIR}" "${RESOURCES_DIR}" "${HELPERS_DIR}" "${LAUNCH_AGENTS_DIR}"

if [ "${BUILD_CONFIGURATION}" = "release" ]; then
  SWIFTC_OPT="-O"
else
  SWIFTC_OPT=""
fi

cd "${ROOT_DIR}"

swiftc \
  ${SWIFTC_OPT} \
  -target "${ARCH}-apple-macosx${MIN_MACOS_VERSION}" \
  $(find "Sources/GlancePane" -name '*.swift' | sort) \
  -o "${MACOS_DIR}/${APP_NAME}"

swiftc \
  ${SWIFTC_OPT} \
  -target "${ARCH}-apple-macosx${MIN_MACOS_VERSION}" \
  "Sources/GlancePaneWatchdog/GlancePaneWatchdog.swift" \
  -o "${HELPERS_DIR}/GlancePaneWatchdog"

cat > "${LAUNCH_AGENTS_DIR}/dev.danbao.glancepane.watchdog.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.danbao.glancepane.watchdog</string>
  <key>BundleProgram</key>
  <string>Contents/Library/Helpers/GlancePaneWatchdog</string>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>ThrottleInterval</key>
  <integer>10</integer>
</dict>
</plist>
PLIST

cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_MACOS_VERSION}</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key>
  <true/>
</dict>
</plist>
PLIST

chmod +x "${MACOS_DIR}/${APP_NAME}" "${HELPERS_DIR}/GlancePaneWatchdog"

if [ -d "${ROOT_DIR}/Resources" ]; then
  cp -R "${ROOT_DIR}/Resources/." "${RESOURCES_DIR}/"
fi

sh "${ROOT_DIR}/scripts/build-icon.sh" "${GENERATED_ICON}" >/dev/null
rm -rf "${RESOURCES_DIR}/AppIcon"
cp "${GENERATED_ICON}" "${RESOURCES_DIR}/AppIcon.icns"

if [ -f "${ROOT_DIR}/THIRD_PARTY_NOTICES.md" ]; then
  cp "${ROOT_DIR}/THIRD_PARTY_NOTICES.md" "${RESOURCES_DIR}/THIRD_PARTY_NOTICES.md"
fi

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "${APP_DIR}"
fi

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "${APP_DIR}" >/dev/null
  codesign --verify --deep --strict "${APP_DIR}"
fi

echo "${APP_DIR}"
