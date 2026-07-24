#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SNAPSHOT_DIR="${ROOT_DIR}/.build/tests/snapshots"
OUTPUT_DIR="${ROOT_DIR}/docs/screenshots"

cd "${ROOT_DIR}"

if [ "${SKIP_TESTS:-0}" != "1" ]; then
  sh scripts/test.sh
fi

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

copy_snapshot() {
  source_name="$1"
  destination_name="$2"
  cp "${SNAPSHOT_DIR}/${source_name}.png" "${OUTPUT_DIR}/${destination_name}.png"
}

copy_snapshot "clock" "clock"
copy_snapshot "system-no-battery" "system"
copy_snapshot "performance-m4" "performance"
copy_snapshot "agents-unlimited" "agents"
copy_snapshot "market-8-symbols" "market"
copy_snapshot "weather-dry" "weather"

swift scripts/sanitize-png.swift "${OUTPUT_DIR}"/*.png
swift scripts/sanitize-png.swift --check "${OUTPUT_DIR}"/*.png

for image in "${OUTPUT_DIR}"/*.png; do
  test "$(sips -g pixelWidth "${image}" | awk '/pixelWidth:/ { print $2 }')" = "1280"
  test "$(sips -g pixelHeight "${image}" | awk '/pixelHeight:/ { print $2 }')" = "720"
done

echo "${OUTPUT_DIR}"
