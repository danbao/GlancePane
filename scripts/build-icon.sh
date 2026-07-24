#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE_PATH="${ROOT_DIR}/Resources/AppIcon/AppIcon-1024.png"
OUTPUT_PATH="${1:-${ROOT_DIR}/.build/generated/AppIcon.icns}"
WORK_DIR="${ROOT_DIR}/.build/icon-work"
ICONSET_DIR="${WORK_DIR}/AppIcon.iconset"

if [ ! -f "${SOURCE_PATH}" ]; then
  echo "Missing app icon source: ${SOURCE_PATH}" >&2
  exit 1
fi

WIDTH="$(sips -g pixelWidth "${SOURCE_PATH}" | awk '/pixelWidth:/ { print $2 }')"
HEIGHT="$(sips -g pixelHeight "${SOURCE_PATH}" | awk '/pixelHeight:/ { print $2 }')"
HAS_ALPHA="$(sips -g hasAlpha "${SOURCE_PATH}" | awk '/hasAlpha:/ { print $2 }')"

if [ "${WIDTH}" != "1024" ] || [ "${HEIGHT}" != "1024" ]; then
  echo "App icon source must be 1024x1024, got ${WIDTH}x${HEIGHT}" >&2
  exit 1
fi

if [ "${HAS_ALPHA}" != "yes" ]; then
  echo "App icon source must contain an alpha channel" >&2
  exit 1
fi

rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}" "$(dirname -- "${OUTPUT_PATH}")"

make_icon() {
  SIZE="$1"
  NAME="$2"
  sips -z "${SIZE}" "${SIZE}" "${SOURCE_PATH}" --out "${ICONSET_DIR}/${NAME}" >/dev/null
}

make_icon 16 "icon_16x16.png"
make_icon 32 "icon_16x16@2x.png"
make_icon 32 "icon_32x32.png"
make_icon 64 "icon_32x32@2x.png"
make_icon 128 "icon_128x128.png"
make_icon 256 "icon_128x128@2x.png"
make_icon 256 "icon_256x256.png"
make_icon 512 "icon_256x256@2x.png"
make_icon 512 "icon_512x512.png"
make_icon 1024 "icon_512x512@2x.png"

iconutil -c icns "${ICONSET_DIR}" -o "${OUTPUT_PATH}"
test -s "${OUTPUT_PATH}"

echo "${OUTPUT_PATH}"
