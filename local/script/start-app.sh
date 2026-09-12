#!/bin/bash

set -e

# --- Load env ---
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "❌ .env file not found"
  exit 1
fi

WEB_PORT="${WEB_PORT:-3000}"
LOG_FILE="local/server.log"
MAX_TRIES=30
RETRY_INTERVAL=1
SERVER_PID=""

# --- Clean shutdown ---
# Fires on Ctrl+C (INT), a normal `kill` (TERM), and plain script exit
# (EXIT) alike, so the backgrounded server never survives this script --
# no orphaned process left running after Ctrl+C.
cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    echo ""
    echo "🛑 Stopping server (pid $SERVER_PID)..."
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup INT TERM EXIT

echo "🚀 Starting Postgres and applying migrations..."
make run-postgres
make migrate-up

mkdir -p "$(dirname "$LOG_FILE")"
# Truncate first so each run starts from an empty log rather than
# appending onto a previous run's output -- '>' below would truncate on
# its own the moment the server writes its first line, but doing it
# explicitly up front means a startup failure (before the app logs
# anything) still leaves an empty file, not a stale one from last time.
: > "$LOG_FILE"
echo "🚀 Starting the app in the background..."
echo "📝 Logging to $LOG_FILE"
cabal run server > "$LOG_FILE" 2>&1 &
SERVER_PID=$!

# --- Wait for readiness ---
# A fixed sleep is fragile -- poll the app itself until it answers, or
# give up after MAX_TRIES.
echo "⏳ Waiting for the app to become ready..."
TRIES=0
until curl --silent --fail --output /dev/null "http://localhost:${WEB_PORT}/ui/projects/vw"; do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "❌ Server process exited unexpectedly -- see $LOG_FILE"
    cat "$LOG_FILE"
    exit 1
  fi
  ((TRIES++))
  if [ "$TRIES" -ge "$MAX_TRIES" ]; then
    echo "❌ App not ready after $MAX_TRIES tries -- see $LOG_FILE"
    exit 1
  fi
  echo "  🔁 Try $TRIES/$MAX_TRIES..."
  sleep "$RETRY_INTERVAL"
done
echo "✅ App ready"

# Reference data through the app's own endpoint; the demo projects
# straight into Postgres, with the app uninvolved.
make seed-db
make seed-demo-data
echo ""
echo "✅ App running at http://localhost:${WEB_PORT} (pid $SERVER_PID)"
echo "   Logs: $LOG_FILE"
echo "   Press Ctrl+C to stop."

# Block here so this script -- and `make start-app` -- keeps running
# (and Ctrl+C keeps working normally) for as long as the server does,
# same as a foregrounded `cabal run server` would.
wait "$SERVER_PID"
