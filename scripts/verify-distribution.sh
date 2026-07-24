#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
APP_PATH="${1:-${ROOT_DIR}/.build/dist/GlancePane.app}"
BINARY_PATH="${APP_PATH}/Contents/MacOS/GlancePane"
RESOURCES_PATH="${APP_PATH}/Contents/Resources"
PLIST_PATH="${APP_PATH}/Contents/Info.plist"
WATCHDOG_PATH="${APP_PATH}/Contents/Library/Helpers/GlancePaneWatchdog"
WATCHDOG_PLIST="${APP_PATH}/Contents/Library/LaunchAgents/dev.danbao.glancepane.watchdog.plist"

test -d "${APP_PATH}"
test -x "${BINARY_PATH}"
test -f "${PLIST_PATH}"
test -x "${WATCHDOG_PATH}"
test -s "${WATCHDOG_PLIST}"
/usr/bin/plutil -lint "${WATCHDOG_PLIST}" >/dev/null
test -s "${RESOURCES_PATH}/AppIcon.icns"
test -s "${RESOURCES_PATH}/Fonts/Oswald.ttf"
test -s "${RESOURCES_PATH}/Fonts/Oswald-OFL.txt"
test -s "${RESOURCES_PATH}/THIRD_PARTY_NOTICES.md"

ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "${PLIST_PATH}")"
MINIMUM_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${PLIST_PATH}")"
ARCHS="$(lipo -archs "${BINARY_PATH}")"
WATCHDOG_ARCHS="$(lipo -archs "${WATCHDOG_PATH}")"

test "${ICON_NAME}" = "AppIcon"
test "${MINIMUM_VERSION}" = "14.0"
test "${ARCHS}" = "arm64"
test "${WATCHDOG_ARCHS}" = "arm64"

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

NON_SYSTEM_DEPENDENCIES="$(
  otool -L "${BINARY_PATH}" |
    tail -n +2 |
    awk '{ print $1 }' |
    awk '
      index($0, "/System/Library/") != 1 &&
      index($0, "/usr/lib/") != 1 &&
      index($0, "/System/Cryptexes/OS/usr/lib/") != 1 {
        print
      }
    '
)"

if [ -n "${NON_SYSTEM_DEPENDENCIES}" ]; then
  echo "Non-system dynamic dependencies found:" >&2
  echo "${NON_SYSTEM_DEPENDENCIES}" >&2
  exit 1
fi

echo "Verified ${APP_PATH}"
