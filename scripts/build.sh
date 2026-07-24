#!/bin/sh
set -eu

mkdir -p ".build/debug"

swiftc $(find "Sources/GlancePane" -name '*.swift' | sort) -o ".build/debug/GlancePane"

echo ".build/debug/GlancePane"
