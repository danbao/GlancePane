#!/bin/sh
set -eu

ARCH="${ARCH:-$(uname -m)}"
MIN_MACOS_VERSION="14.0"

mkdir -p ".build/debug"

swiftc \
  -target "${ARCH}-apple-macosx${MIN_MACOS_VERSION}" \
  $(find "Sources/GlancePane" -name '*.swift' | sort) \
  -o ".build/debug/GlancePane"

echo ".build/debug/GlancePane"
