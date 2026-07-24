#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
cd "${ROOT_DIR}"

forbidden_pattern='/Users/[^/[:space:]]+|10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}'
if rg -n --hidden \
  --glob '!.git/**' \
  --glob '!.build/**' \
  --glob '!scripts/audit-public-tree.sh' \
  --glob '!Resources/AppIcon/AppIcon-1024.png' \
  "${forbidden_pattern}" .; then
  echo "Personal data marker found in public tree" >&2
  exit 1
fi

if rg -n --hidden \
  --glob '!.git/**' \
  --glob '!.build/**' \
  'BEGIN (OPENSSH|RSA|EC|DSA|PRIVATE) PRIVATE KEY|gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}' .; then
  echo "Credential-like content found in public tree" >&2
  exit 1
fi

test "$(find docs/screenshots -type f -name '*.png' | wc -l | tr -d ' ')" = "6"
swift scripts/sanitize-png.swift --check docs/screenshots/*.png

for image in docs/screenshots/*.png; do
  test "$(sips -g pixelWidth "${image}" | awk '/pixelWidth:/ { print $2 }')" = "1280"
  test "$(sips -g pixelHeight "${image}" | awk '/pixelHeight:/ { print $2 }')" = "720"
done

echo "Public tree audit passed"
