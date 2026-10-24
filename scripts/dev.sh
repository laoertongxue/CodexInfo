#!/usr/bin/env bash
# Runs the panel for UI work.
#
# The script starts the Vite dev server and opens the panel in the browser.
# Without a native bridge the page falls back to the mock snapshot, so the
# layout, the states and the fixtures can be worked on without an account.
#
# With `--app` the menu bar app is started as well; it loads the panel from
# the dev server and shows the real data of this machine.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WITH_APP=0
for argument in "$@"; do
  case "$argument" in
    --app) WITH_APP=1 ;;
    *) echo "usage: bash scripts/dev.sh [--app]" >&2; exit 2 ;;
  esac
done

HOST="127.0.0.1"
PORT="5173"
URL="http://$HOST:$PORT/"

if [ ! -d "$ROOT/Web/node_modules" ]; then
  echo "==> Installing the web dependencies"
  pnpm --dir "$ROOT/Web" install --frozen-lockfile
fi

echo "==> Starting the dev server"
pnpm --dir "$ROOT/Web" exec vite --host "$HOST" --port "$PORT" &
WEB_PID=$!
trap 'kill "$WEB_PID" 2>/dev/null || true' EXIT INT TERM

echo "==> Waiting for the dev server"
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null "$URL" 2>/dev/null; then
    break
  fi
  sleep 0.5
done
if ! curl -fsS -o /dev/null "$URL" 2>/dev/null; then
  echo "The dev server did not come up on $URL" >&2
  exit 1
fi

echo "Panel:  $URL"
echo "States: $URL?fixture=suspected, $URL?fixture=single-source, $URL?fixture=degraded-source"
if ! open "$URL"; then
  echo "The browser could not be opened; open $URL by hand." >&2
fi

if [ "$WITH_APP" -eq 1 ]; then
  echo "==> Starting the menu bar app"
  CODEXINFO_DEV_URL="$URL" swift run CodexInfoApp
else
  echo "Press Ctrl+C to stop the dev server."
  wait "$WEB_PID"
fi
