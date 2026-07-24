#!/bin/sh
set -eu

PREDICATE='process == "GlancePane" OR process == "GlancePaneWatchdog"'

case "${1:-}" in
  --follow|-f)
    exec /usr/bin/log stream --style compact --predicate "${PREDICATE}"
    ;;
  "")
    exec /usr/bin/log show --last 30m --style compact --predicate "${PREDICATE}"
    ;;
  *)
    exec /usr/bin/log show --last "$1" --style compact --predicate "${PREDICATE}"
    ;;
esac
