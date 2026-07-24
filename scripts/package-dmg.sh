#!/bin/sh
set -eu

APP_NAME="GlancePane"
BUNDLE_ID="dev.danbao.glancepane"
MIN_MACOS_VERSION="14.0"
ARCH="arm64"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
APP_VERSION="${APP_VERSION:-}"

if [ -z "${APP_VERSION}" ] && [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
  case "${GITHUB_REF_NAME:-}" in
    v[0-9]*)
      APP_VERSION="${GITHUB_REF_NAME#v}"
      ;;
  esac
fi

BUILD_DIR=".build/${BUILD_CONFIGURATION}"
DIST_DIR=".build/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
DMG_ROOT="${DIST_DIR}/dmg-root"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${ARCH}.dmg"
SHA_PATH="${DMG_PATH}.sha256"

rm -rf "${APP_DIR}" "${DMG_ROOT}" "${DMG_PATH}" "${SHA_PATH}"
mkdir -p "${BUILD_DIR}" "${DIST_DIR}"

APP_DIR="${APP_DIR}" \
ARCH="${ARCH}" \
BUILD_CONFIGURATION="${BUILD_CONFIGURATION}" \
BUILD_NUMBER="${BUILD_NUMBER}" \
APP_VERSION="${APP_VERSION}" \
sh "scripts/build-app.sh" >/dev/null

sh "scripts/verify-distribution.sh" "${APP_DIR}"

mkdir -p "${DMG_ROOT}"
cp -R "${APP_DIR}" "${DMG_ROOT}/"
ln -s "/Applications" "${DMG_ROOT}/Applications"

hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

(
  cd "${DIST_DIR}"
  shasum -a 256 "$(basename -- "${DMG_PATH}")" > "$(basename -- "${SHA_PATH}")"
)

echo "${DMG_PATH}"
