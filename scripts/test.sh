#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/tests"
BINARY_PATH="${BUILD_DIR}/GlancePaneTests"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

cd "${ROOT_DIR}"

sh "scripts/build-icon.sh" "${BUILD_DIR}/AppIcon.icns" >/dev/null
test -s "${BUILD_DIR}/AppIcon.icns"

swiftc \
  $(find "Sources/GlancePane" -name '*.swift' ! -name 'GlancePaneMain.swift' | sort) \
  $(find "Tests/GlancePaneTests" -name '*.swift' | sort) \
  -o "${BINARY_PATH}"

"${BINARY_PATH}"
