#!/bin/sh
set -eu

APP_NAME="GlancePane"
ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CONFIG_DIR="${HOME}/.glancepane"
PID_FILE="${CONFIG_DIR}/glancepane.pid"
APP_DIR="${ROOT_DIR}/.build/debug/${APP_NAME}.app"
BINARY="${APP_DIR}/Contents/MacOS/${APP_NAME}"

mkdir -p "${CONFIG_DIR}"
chmod 700 "${CONFIG_DIR}"

if [ -f "${PID_FILE}" ]; then
  EXISTING_PID="$(sed -n '1p' "${PID_FILE}" 2>/dev/null || true)"
  if [ -n "${EXISTING_PID}" ] && kill -0 "${EXISTING_PID}" 2>/dev/null; then
    echo "${APP_NAME} already running: ${EXISTING_PID}"
    echo "Logs: sh scripts/logs.sh"
    exit 0
  fi
  rm -f "${PID_FILE}"
fi

RUNNING_PID="$(pgrep -f "${BINARY}" | sed -n '1p' || true)"
if [ -n "${RUNNING_PID}" ] && kill -0 "${RUNNING_PID}" 2>/dev/null; then
  printf '%s\n' "${RUNNING_PID}" > "${PID_FILE}"
  chmod 600 "${PID_FILE}"
  echo "${APP_NAME} already running: ${RUNNING_PID}"
  echo "PID file: ${PID_FILE}"
  echo "Logs: sh scripts/logs.sh"
  exit 0
fi

(cd "${ROOT_DIR}" && APP_DIR="${APP_DIR}" BUILD_CONFIGURATION="debug" sh "scripts/build-app.sh" >/dev/null)

open -g "${APP_DIR}" >/dev/null 2>&1

sleep 2

PID="$(pgrep -f "${BINARY}" | sed -n '1p' || true)"

if [ -n "${PID}" ] && kill -0 "${PID}" 2>/dev/null; then
  printf '%s\n' "${PID}" > "${PID_FILE}"
  chmod 600 "${PID_FILE}"
  echo "${APP_NAME} running: ${PID}"
  echo "PID file: ${PID_FILE}"
  echo "Logs: sh scripts/logs.sh"
else
  echo "${APP_NAME} failed to stay running. Inspect with: sh scripts/logs.sh" >&2
  exit 1
fi
