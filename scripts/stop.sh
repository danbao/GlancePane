#!/bin/sh
set -eu

APP_NAME="GlancePane"
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CONFIG_DIR="${HOME}/.glancepane"
PID_FILE="${CONFIG_DIR}/glancepane.pid"
BINARY="${ROOT_DIR}/.build/debug/${APP_NAME}.app/Contents/MacOS/${APP_NAME}"

if [ -f "${PID_FILE}" ]; then
  PID="$(sed -n '1p' "${PID_FILE}" 2>/dev/null || true)"
else
  PID=""
fi

if [ -z "${PID}" ] || ! kill -0 "${PID}" 2>/dev/null; then
  PID="$(pgrep -f "${BINARY}" | sed -n '1p' || true)"
fi

if [ -z "${PID}" ] || ! kill -0 "${PID}" 2>/dev/null; then
  rm -f "${PID_FILE}"
  echo "${APP_NAME} is not running: no pid file"
  exit 0
fi

kill "${PID}"

COUNT=0
while kill -0 "${PID}" 2>/dev/null; do
  COUNT=$((COUNT + 1))
  if [ "${COUNT}" -ge 20 ]; then
    echo "${APP_NAME} did not stop after 10 seconds: ${PID}" >&2
    exit 1
  fi
  sleep 0.5
done

rm -f "${PID_FILE}"
echo "${APP_NAME} stopped: ${PID}"
