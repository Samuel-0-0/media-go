#!/bin/sh
set -eu

DATA_DIR="${DATA_DIR:-/data}"
APP_BIN="${MEDIAGO_APP_BIN:-/app/mediago}"
HOT_BIN="${MEDIAGO_HOT_BIN:-$DATA_DIR/bin/mediago}"
HOT_BAK="${HOT_BIN}.bak"

/opt/venv/bin/python /app/docker-healthcheck.py --snapshot

pick_binary() {
  if [ -x "$HOT_BIN" ]; then
    hot_ver="$("$HOT_BIN" --version 2>/dev/null | head -n 1 | tr -d '\r\n' || true)"
    app_ver="$("$APP_BIN" --version 2>/dev/null | head -n 1 | tr -d '\r\n' || true)"
    if [ -n "$hot_ver" ]; then
      if [ -z "$app_ver" ]; then
        printf '%s\n' "$HOT_BIN"
        return
      fi
      prefer_hot="$(/opt/venv/bin/python -c '
import re, sys
def key(s):
    s = re.sub(r"^[vV]", "", s.strip())
    nums = [int(x) for x in re.findall(r"\d+", s.split("-")[0])]
    while len(nums) < 4:
        nums.append(0)
    return tuple(nums[:4])
print("1" if key(sys.argv[1]) >= key(sys.argv[2]) else "0")
' "$hot_ver" "$app_ver" 2>/dev/null || echo "1")"
      if [ "$prefer_hot" = "1" ]; then
        printf '%s\n' "$HOT_BIN"
        return
      fi
    fi
  fi
  printf '%s\n' "$APP_BIN"
}

CHILD_PID=""
STOPPING=0

forward_signal() {
  STOPPING=1
  if [ -n "$CHILD_PID" ]; then
    kill -TERM "$CHILD_PID" 2>/dev/null || true
    wait "$CHILD_PID" 2>/dev/null || true
  fi
  exit 0
}

trap forward_signal TERM INT

while true; do
  BIN="$(pick_binary)"
  START_TS="$(date +%s)"
  "$BIN" "$@" &
  CHILD_PID=$!
  set +e
  wait "$CHILD_PID"
  RC=$?
  set -e
  CHILD_PID=""

  if [ "$STOPPING" = "1" ]; then
    exit 0
  fi

  # Exit code 42 indicates an intentional in-container hot-restart after binary upgrade.
  if [ "$RC" = "42" ]; then
    echo "INFO [entrypoint] Hot-restarting MediaGo after in-container binary upgrade..."
    /opt/venv/bin/python /app/docker-healthcheck.py --snapshot || true
    continue
  fi

  # Auto-rollback if a hot-upgraded binary crashes within 8 seconds of launch.
  END_TS="$(date +%s)"
  ELAPSED=$((END_TS - START_TS))
  if [ "$BIN" = "$HOT_BIN" ] && [ "$RC" != "0" ] && [ "$ELAPSED" -lt 8 ]; then
    echo "WARN [entrypoint] Hot-upgraded binary crashed quickly (rc=$RC, ${ELAPSED}s); rolling back..." >&2
    if [ -x "$HOT_BAK" ]; then
      mv -f "$HOT_BAK" "$HOT_BIN" 2>/dev/null || rm -f "$HOT_BIN"
    else
      rm -f "$HOT_BIN"
    fi
    continue
  fi

  exit "$RC"
done
